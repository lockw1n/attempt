import CoreData
import Foundation
import RepositoryInterface

/// CloudKit's own account of what mirroring is doing (`FR-1.12.2`).
///
/// **SwiftData reports nothing, which is why this reaches past it.** Measured against the
/// iPhoneOS 26.5 SDK: SwiftData's entire CloudKit surface is `cloudKitContainerIdentifier`,
/// `cloudKitDatabase` and `allowsCloudEncryption` — no status, no timestamp, no error channel and
/// no event stream. CoreData posts one, and a SwiftData container configured with a private
/// database *is* an `NSPersistentCloudKitContainer` underneath, so the notification arrives whether
/// or not anything in this module ever names that class.
///
/// **It is a notification rather than a container query, so it observes the process and not a
/// store.** A build that opens one store — which this app does — cannot tell the difference. A
/// build that opened two would see both here, and would need `storeIdentifier` to separate them.
public enum CloudKitSyncEvents {
    /// Every mirroring attempt this process is told about, from now on.
    ///
    /// **The stream ends when its consumer stops iterating**, and the observer is removed with it.
    ///
    /// - Returns: The attempts, as they are reported.
    public static func stream() -> AsyncStream<SyncEvent> {
        AsyncStream { continuation in
            // A `Task` over the async sequence rather than `addObserver(forName:…)`, which is a
            // concurrency constraint rather than a preference: the token that call returns is
            // `any NSObjectProtocol`, and removing it from `onTermination` — a `@Sendable` closure
            // — captures a non-Sendable value. A `Task` is Sendable and cancelling it removes the
            // observation, so the same lifetime is expressible without an `@unchecked` wrapper
            // around a token whose only job is to be handed back.
            let task = Task {
                let notifications = NotificationCenter.default.notifications(
                    named: NSPersistentCloudKitContainer.eventChangedNotification)
                for await notification in notifications {
                    guard
                        let event = notification.userInfo?[
                            NSPersistentCloudKitContainer.eventNotificationUserInfoKey
                        ] as? NSPersistentCloudKitContainer.Event
                    else { continue }
                    continuation.yield(syncEvent(from: event))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The framework's event as this app's own value.
    ///
    /// Split out so the mapping is reachable without a notification — `NSPersistentCloudKitContainer.Event`
    /// cannot be constructed, so this is as close to the seam as a test can get.
    ///
    /// - Parameter event: What CoreData reported.
    /// - Returns: The same attempt, in this app's vocabulary.
    static func syncEvent(from event: NSPersistentCloudKitContainer.Event) -> SyncEvent {
        SyncEvent(
            activity: activity(for: event.type),
            startDate: event.startDate,
            endDate: event.endDate,
            succeeded: event.succeeded)
    }

    /// This app's name for one of CoreData's three event types.
    ///
    /// **The unknown case resolves to `.setup` rather than trapping**, which is this module's
    /// four-way rule landing on its most conservative answer: a type nobody has seen is not
    /// evidence that records moved, and `.setup` is the case that claims the least.
    ///
    /// - Parameter type: CoreData's event type.
    /// - Returns: The activity to report.
    static func activity(for type: NSPersistentCloudKitContainer.EventType) -> SyncActivity {
        switch type {
        case .setup: .setup
        case .import: .download
        case .export: .upload
        @unknown default: .setup
        }
    }
}
