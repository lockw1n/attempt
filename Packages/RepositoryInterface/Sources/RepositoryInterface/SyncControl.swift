import Foundation

/// Sync as the Settings screen sees it (`FR-1.12.1`–`FR-1.12.3`).
///
/// **The seventh protocol in this module, and the only one that is not a repository.** It is here
/// for the reason the other six are: a feature module names this module and never `Persistence`,
/// so a screen that reports on mirroring needs a vocabulary that does not drag SwiftData — or, as
/// it turns out, CoreData — across the layer boundary.
///
/// **THE SWITCH CANNOT TAKE EFFECT WHILE THE APP IS RUNNING, AND THAT IS A FRAMEWORK CONSTRAINT
/// RATHER THAN A CHOICE.** `ModelConfiguration.cloudKitDatabase` is a `let` fixed when the
/// `ModelContainer` is built, so turning mirroring on or off means building a different container —
/// which means new repositories, and new stores over them, including the one holding a workout that
/// may be in progress. Dropping a lifter's live session to honour a settings toggle is a worse
/// outcome than the toggle waiting, so the choice is recorded and applied at the next launch.
///
/// That is why this protocol has two booleans rather than one. ``isEnabled`` is what the lifter
/// chose and ``isRunning`` is what this launch is actually doing; they differ exactly between a
/// change and the next start, and a screen that showed only the first would claim a state the app
/// is not in — which is the `G-5.3` failure this whole task exists to correct one screen over.
public protocol SyncControl: Sendable {
    /// Whether the lifter has sync switched on (`FR-1.12.3`).
    ///
    /// **A stored choice, not an observation of CloudKit.** It reads the same on a device with no
    /// network and on one with no account — those are conditions, and this is a preference.
    var isEnabled: Bool { get async }

    /// Whether *this launch* is mirroring, which is the choice as it stood when the store opened.
    var isRunning: Bool { get async }

    /// Where sync has got to, now.
    var status: SyncStatus { get async }

    /// Every status from this moment on, beginning with the one in force.
    ///
    /// - Returns: A stream that finishes when its consumer stops iterating.
    func statusUpdates() -> AsyncStream<SyncStatus>

    /// Records the lifter's choice, to be applied at the next launch (`FR-1.12.3`).
    ///
    /// **Local data is not touched either way, and this call touches nothing at all beyond the
    /// preference.** Disabling stops mirroring at the next start; it does not delete the store, and
    /// it does not ask CloudKit to forget anything — the rows stay exactly where they were, which
    /// is the promise `FR-1.12.3` makes.
    ///
    /// **It does not throw**, because there is nothing here that can fail: writing a preference is
    /// the whole of it, and the container work that could fail happens at launch, where the
    /// existing store-open failure path already catches it.
    ///
    /// - Parameter enabled: What the lifter chose.
    func setEnabled(_ enabled: Bool) async
}
