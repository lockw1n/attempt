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
actor AppSyncControl: SyncControl {
    /// Where the choice is kept. Named once, here.
    static let defaultsKey = "sync.enabled"

    /// Whether a device that has never been asked mirrors.
    ///
    /// **OFF, AND ONLY UNTIL THE CONTAINER EXISTS — FLIP THIS TO `true` AS PART OF T-1.70.**
    /// `FR-1.12.1` wants sync to be the app's behaviour and `FR-1.12.3` makes it refusable, so `true`
    /// is the right long-run answer: a default of off leaves a lifter's second device empty until
    /// they find this screen.
    ///
    /// It is `false` today because `iCloud.lockw1n.Attempt` has not been provisioned. Measured, not
    /// assumed: with the entitlement present and the container absent, the app takes
    /// `EXC_BREAKPOINT`/`SIGTRAP` on launch — CoreData's mirroring delegate traps on
    /// `com.apple.coredata.cloudkit.queue`, which is T-0.33's finding arriving on the app's own
    /// launch path rather than in a test process. **It cannot be caught**: it is a trap, not a
    /// thrown error, so there is no `try` that recovers and no state a screen could show instead.
    ///
    /// So the default is the only lever, and this is the one line to change once the container is
    /// real. Nothing else about activation is conditional on it.
    static let defaultEnabled = false

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

    /// Builds the control over the preference store and the container this launch opened.
    ///
    /// - Parameters:
    ///   - defaults: Where the choice is kept.
    ///   - isRunning: Whether the container this launch built mirrors.
    init(defaults: UserDefaults = .standard, isRunning: Bool) {
        self.defaults = defaults
        self.running = isRunning
        self.current = isRunning ? .waiting : .off
    }

    /// Whether the lifter has sync switched on.
    var isEnabled: Bool { Self.isEnabled(in: defaults) }

    /// Whether this launch is mirroring.
    var isRunning: Bool { running }

    /// Where sync has got to.
    var status: SyncStatus { current }

    /// Records the lifter's choice, to be applied at the next launch.
    ///
    /// - Parameter enabled: What the lifter chose.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.defaultsKey)
    }

    /// Folds one event into the status this process holds.
    ///
    /// - Parameter event: What CloudKit reported.
    /// - Returns: The status after it.
    private func record(_ event: SyncEvent) -> SyncStatus {
        current = current.applying(event)
        return current
    }

    /// Every status from this moment on, beginning with the one in force.
    ///
    /// - Returns: The statuses, as CloudKit reports the attempts behind them.
    nonisolated func statusUpdates() -> AsyncStream<SyncStatus> {
        AsyncStream { continuation in
            let task = Task {
                continuation.yield(await self.status)
                // A store that is not mirroring will never be told about an attempt, so there is
                // nothing to listen to — and `CloudKitSyncEvents` would hold an observer open for
                // the life of the screen to hear silence.
                guard await self.isRunning else {
                    continuation.finish()
                    return
                }
                for await event in CloudKitSyncEvents.stream() {
                    continuation.yield(await self.record(event))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
