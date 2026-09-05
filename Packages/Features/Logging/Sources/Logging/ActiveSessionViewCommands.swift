import DerivedValues
import SwiftUI

/// The two commands that end the workout from its own screen (`FR-1.2.11`, `FR-1.2.12`,
/// `FR-16.4.4`).
///
/// **A file of its own rather than the foot of `ActiveSessionView.swift`**, which had reached
/// SwiftLint's file ceiling: the screen grows as the workout gains content, and these grow as
/// leaving one gains conditions.
extension ActiveSessionView {
    /// Finishes the workout and leaves the screen, unless the write failed.
    ///
    /// The screen stays open on a failure, with the workout still on it: nothing was stored, so the
    /// retry is another tap at the same command rather than a workout the user has to find again.
    ///
    /// **The question comes first where there is one to ask** (`FR-16.4.4`). A workout holding sets
    /// nobody attempted cannot be finished without an answer — the store refuses it too — so the
    /// tap opens the alert and the answer taps this again.
    ///
    /// - Parameter resolution: What to do with those sets, or `nil` on the first tap.
    func finish(resolving resolution: SessionFinish.Resolution? = nil) async {
        if resolution == nil, pendingSetCount > 0 {
            isResolvingPendingSets = true
            return
        }
        // The note's own **Save** is inside a fold the user may never have opened, and this command
        // is directly beneath it — so what is in the field is committed with the workout rather
        // than dropped by it. Nothing is written where the field and the record already agree.
        await store.finish(
            saving: noteDraft.hasUnsavedChanges ? noteDraft.text : nil, resolving: resolution)
        // A note that would not store keeps the workout — see `finish(saving:)`. Its diagnostic is
        // inside the fold, so the fold is opened: otherwise the tap reports nothing at all, which
        // is the failure that rule exists to prevent.
        if store.noteWriteFailure != nil { areNotesExpanded = true }
        guard !store.isActive else { return }
        dismiss()
    }

    /// Discards the workout and leaves the screen, unless the write failed. See ``ActiveSessionView/finish(resolving:)``.
    func discard() async {
        await store.discard()
        guard !store.isActive else { return }
        dismiss()
    }
}
