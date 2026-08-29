import Foundation

/// What a sync attempt was doing (`FR-1.12.2`).
///
/// The three cases are CloudKit's own, named in this module's words so a screen can draw them
/// without importing the framework that raised them. **Setup is not a data transfer** — it is the
/// account and zone check that runs once per launch — so a screen that says "syncing" for all
/// three would report activity where none is moving.
public enum SyncActivity: Equatable, Sendable, CaseIterable {
    /// The account and the record zone are being checked. Runs once, before anything moves.
    case setup

    /// Records are arriving from the account.
    case download

    /// Records are being sent to the account.
    case upload
}

/// One attempt CloudKit made, as much of it as this app is told (`FR-1.12.2`).
///
/// **A value rather than the framework's event object**, which is the whole reason it exists:
/// `NSPersistentCloudKitContainerEvent` cannot be constructed — its `init` is unavailable — so a
/// reducer that took one could never be tested against a finished attempt, only observed against a
/// real account. Mapping at the seam and reducing over this leaves the rule testable.
///
/// **`endDate` is what says the attempt is over, not `succeeded`.** An attempt still running
/// reports `succeeded == false`, because it has not succeeded *yet* — reading that as failure is
/// the defect this type's shape exists to make hard, and ``SyncStatus/applying(_:)`` is where the
/// rule is written down.
public struct SyncEvent: Equatable, Sendable {
    /// What the attempt was doing.
    public var activity: SyncActivity

    /// When it began.
    public var startDate: Date

    /// When it finished, or `nil` while it is still running.
    public var endDate: Date?

    /// Whether it finished successfully. **Meaningless until `endDate` is non-`nil`.**
    public var succeeded: Bool

    /// Records one attempt.
    ///
    /// - Parameters:
    ///   - activity: What the attempt was doing.
    ///   - startDate: When it began.
    ///   - endDate: When it finished, or `nil` while it runs.
    ///   - succeeded: Whether it finished successfully.
    public init(activity: SyncActivity, startDate: Date, endDate: Date? = nil, succeeded: Bool = false) {
        self.activity = activity
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
    }
}

/// What the sync screen shows (`FR-1.12.2`, `FR-1.12.3`).
///
/// **The error is deliberately not here.** `G-3.4` makes an error's description a diagnostic and
/// never the sentence a user reads, and there is nothing a lifter can do about a CloudKit failure
/// beyond wait — so the status carries *that* it failed and when it last worked, which is the pair
/// `FR-1.12.2` names.
public struct SyncStatus: Equatable, Sendable {
    /// Where sync has got to.
    public enum Phase: Equatable, Sendable {
        /// The lifter turned it off (`FR-1.12.3`). **Not "unavailable"** — off is a choice, and a
        /// screen that conflated the two would offer to fix something nobody broke.
        case off

        /// On, with nothing in flight.
        case idle

        /// On, with an attempt running.
        case active(SyncActivity)

        /// On, and the last finished attempt did not succeed.
        case failed
    }

    /// Where sync has got to.
    public var phase: Phase

    /// When an attempt last finished successfully, or `nil` if none ever has.
    ///
    /// **It survives a failure**, which is what makes it worth showing: "last synced at 09:12" is
    /// the useful half of a failure, and clearing it would leave the screen saying only that
    /// something is wrong.
    public var lastSucceededAt: Date?

    /// Builds a status.
    ///
    /// - Parameters:
    ///   - phase: Where sync has got to.
    ///   - lastSucceededAt: When an attempt last finished successfully.
    public init(phase: Phase, lastSucceededAt: Date? = nil) {
        self.phase = phase
        self.lastSucceededAt = lastSucceededAt
    }

    /// Sync as it stands before any event has arrived, for a build that has it switched on.
    public static let waiting = SyncStatus(phase: .idle)

    /// Sync as it stands when the lifter has turned it off (`FR-1.12.3`).
    public static let off = SyncStatus(phase: .off)

    /// The status after `event`, or this one unchanged where the event says nothing new.
    ///
    /// **Three rules, and the first is the one every naive version gets wrong:**
    ///
    /// - An event with no `endDate` is *running*, whatever `succeeded` says — CloudKit reports
    ///   `succeeded == false` throughout an attempt that is going perfectly well.
    /// - A finished, successful attempt is what moves ``lastSucceededAt``. Nothing else does, so a
    ///   long run of failures leaves the last good time readable.
    /// - **An event arriving while sync is off is dropped.** Turning mirroring off does not reach
    ///   in and cancel an attempt already in flight, so its completion lands afterwards; applying
    ///   it would put the screen back into a phase the lifter just left.
    ///
    /// - Parameter event: The attempt CloudKit reported.
    /// - Returns: The status to show.
    public func applying(_ event: SyncEvent) -> SyncStatus {
        guard phase != .off else { return self }
        guard let endDate = event.endDate else {
            return SyncStatus(phase: .active(event.activity), lastSucceededAt: lastSucceededAt)
        }
        guard event.succeeded else {
            return SyncStatus(phase: .failed, lastSucceededAt: lastSucceededAt)
        }
        return SyncStatus(phase: .idle, lastSucceededAt: max(endDate, lastSucceededAt ?? endDate))
    }
}
