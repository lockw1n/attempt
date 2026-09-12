import Foundation
import Persistence
import RepositoryInterface

/// Sync, as the Settings screen switches and reads it (`FR-1.12.1`–`FR-1.12.3`).
///
/// **In the app target because it is the only place both halves exist.** The preference is a device
/// setting, the events come from `Persistence`, and the container this launch actually opened is
/// known here and nowhere else — a feature module has none of the three.
///
/// **The choice is in `UserDefaults` rather than in the store, and that is not laziness.** A synced
/// row would carry this setting to every other device, so turning sync off on a phone would turn it
/// off on the iPad — and then, having turned itself off, would have no way to say so. A switch over
/// syncing is the one preference that must not sync.
///
/// **IT LISTENS FROM LAUNCH, NOT FROM WHEN A SCREEN ASKS.** Mirroring runs whether or not anyone is
/// looking at it, and CloudKit's notification is only delivered to an observer that exists when it
/// is posted — so a control that started observing inside ``statusUpdates()`` would report only the
/// attempts made since Settings was opened, and would call every earlier success unheard. Measured
/// on 2026-09-11 (`T-1.86`): rows were arriving on one install while its own screen read *Could not
/// sync — Not synced yet*, which is also what a device that has never synced says.
///
/// **And ``RepositoryInterface/SyncStatus/lastSucceededAt`` outlives the process**, which is the
/// other half of the same sentence. `FR-1.12.2` asks for the *last successful sync* timestamp, not
/// for the last one this launch happened to witness; holding it only in memory makes every relaunch
/// look like a device that has never synced.
actor AppSyncControl: SyncControl {
    /// Where the choice is kept. Named once, here.
    static let defaultsKey = "sync.enabled"

    /// Where the last success is kept, so `FR-1.12.2`'s timestamp survives a relaunch.
    ///
    /// **A device setting rather than a synced row, for ``defaultsKey``'s reason one step on**: it
    /// describes when *this* device last reached the account, so a value arriving from another one
    /// would be a different device's answer to the same question.
    static let lastSucceededAtKey = "sync.lastSucceededAt"

    /// Whether a device that has never been asked mirrors.
    ///
    /// `FR-1.12.1` makes sync the app's behaviour and `FR-1.12.3` makes it refusable, so a default
    /// of off would leave a lifter's second device empty until they went looking for this screen.
    ///
    /// **It may be `true` only while `iCloud.lockw1n.Attempt` is provisioned and its schema is
    /// deployed to Production.** With the entitlement present and the container absent, launch takes
    /// `EXC_BREAKPOINT`/`SIGTRAP` on CoreData's mirroring queue — a trap rather than a thrown error,
    /// so no `try` recovers it and no screen can show it instead. Renaming the container, or
    /// pointing a build at one whose schema was never deployed, arms that on every fresh install.
    static let defaultEnabled = true

    /// Whether a device mirrors, as the choice stands in `defaults`.
    ///
    /// **Static, because the launch path needs it before any instance exists**: `cloudKitDatabase`
    /// is fixed when the container is built, so `AppDependencies` has to read the choice before it
    /// can build the store the control reports on.
    ///
    /// `object(forKey:)` rather than `bool(forKey:)`: the latter answers `false` for a key that was
    /// never written, which is exactly the case ``defaultEnabled`` exists to answer differently.
    ///
    /// - Parameter defaults: Where the choice is kept.
    /// - Returns: Whether sync is chosen.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? defaultEnabled
    }

    /// Where the choice is kept.
    private let defaults: UserDefaults

    /// What this launch opened the store as, which no later choice changes.
    private let running: Bool

    /// The status as far as this process has been told.
    private var current: SyncStatus

    /// The screens following the status, each removed when it stops iterating.
    private var followers: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    /// Builds the control over the preference store and the container this launch opened.
    ///
    /// **It starts listening**, on a mirroring launch — see the type's own note. `events` is the
    /// seam that makes that testable: `NSPersistentCloudKitContainer.Event` cannot be constructed,
    /// so an attempt can only be delivered to a test through a stream the test supplies.
    ///
    /// **A suite name rather than a `UserDefaults`, and the compiler decides that.** `UserDefaults`
    /// is not `Sendable`, so handing one to an actor is a *sending* diagnostic — "Sending 'defaults'
    /// risks causing data races" — at every call site that does not simply pass the global. Opening
    /// it here from a name crosses nothing, and a test still gets a domain of its own.
    ///
    /// - Parameters:
    ///   - defaultsSuiteName: The preference domain, or `nil` for the app's own.
    ///   - isRunning: Whether the container this launch built mirrors.
    ///   - events: The attempts to fold, defaulting to the ones CloudKit reports.
    init(
        defaultsSuiteName: String? = nil,
        isRunning: Bool,
        events: @escaping @Sendable () -> AsyncStream<SyncEvent> = CloudKitSyncEvents.stream
    ) {
        // A malformed name, or the app's own domain, answers nil — and falling back to `.standard`
        // there would quietly write the real preference while a test believed it had a scratch one.
        let defaults =
            defaultsSuiteName.map { name in
                guard let suite = UserDefaults(suiteName: name) else {
                    preconditionFailure("\(name) is not a usable preference domain")
                }
                return suite
            } ?? .standard
        self.defaults = defaults
        self.running = isRunning
        let lastSucceededAt = defaults.object(forKey: Self.lastSucceededAtKey) as? Date
        self.current =
            isRunning
            ? SyncStatus(phase: .idle, lastSucceededAt: lastSucceededAt)
            : SyncStatus(phase: .off, lastSucceededAt: lastSucceededAt)
        guard isRunning else { return }
        // NOT HELD IN A PROPERTY, AND THE COMPILER IS WHY: an actor's `init` is nonisolated, so
        // assigning to a stored property after a closure has captured `self` is rejected outright
        // — "Cannot access property 'observation' here in nonisolated initializer". The loop ends
        // itself instead, on the first event after the control is gone, which is the same lifetime
        // a cancelling `deinit` would have given it.
        Task { [weak self] in
            for await event in events() {
                guard let self else { break }
                await self.record(event)
            }
        }
    }

    /// Whether the lifter has sync switched on.
    var isEnabled: Bool { Self.isEnabled(in: defaults) }

    /// Whether this launch is mirroring.
    var isRunning: Bool { running }

    /// Where sync has got to.
    var status: SyncStatus { current }

    /// Folds one event into the status this process holds, and tells everyone following.
    ///
    /// - Parameter event: What CloudKit reported.
    private func record(_ event: SyncEvent) {
        let updated = current.applying(event)
        guard updated != current else { return }
        current = updated
        // ONLY EVER WRITTEN FORWARD. `applying(_:)` carries the old value through a failure, so a
        // failing attempt writes back what was already there rather than clearing it — which is
        // what makes "Could not sync · last synced at 09:12" expressible at all.
        if let lastSucceededAt = updated.lastSucceededAt {
            defaults.set(lastSucceededAt, forKey: Self.lastSucceededAtKey)
        }
        for follower in followers.values {
            follower.yield(updated)
        }
    }

    /// Records the lifter's choice, to be applied at the next launch.
    ///
    /// - Parameter enabled: What the lifter chose.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.defaultsKey)
    }

    /// Begins following, from the status in force.
    ///
    /// - Parameters:
    ///   - id: The follower's own key, so it can stop.
    ///   - continuation: Where its statuses go.
    private func follow(_ id: UUID, _ continuation: AsyncStream<SyncStatus>.Continuation) {
        continuation.yield(current)
        // A store that is not mirroring will never be told about an attempt, so there is nothing
        // further to say and the stream ends rather than being held open for the life of a screen.
        guard running else {
            continuation.finish()
            return
        }
        followers[id] = continuation
    }

    /// Stops following.
    ///
    /// - Parameter id: The follower's key.
    private func stopFollowing(_ id: UUID) {
        followers[id] = nil
    }

    /// Every status from this moment on, beginning with the one in force.
    ///
    /// **The listening is not started here**, unlike the version `T-1.71` shipped — it began at
    /// launch, so the first element is the fold of every attempt made since, rather than of the
    /// ones that happened to arrive after a screen appeared.
    ///
    /// - Returns: The statuses, as CloudKit reports the attempts behind them.
    nonisolated func statusUpdates() -> AsyncStream<SyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            let task = Task { await self.follow(id, continuation) }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.stopFollowing(id) }
            }
        }
    }
}
