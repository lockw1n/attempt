import DerivedValues
import SwiftUI

/// The two commands that end the workout from its own screen (`FR-1.2.11`, `FR-1.2.12`,
/// `FR-16.4.4`).
///
/// **A file of its own rather than the foot of `ActiveSessionView.swift`**, which had reached
/// SwiftLint's file ceiling: the screen grows as the workout gains content, and these grow as
/// leaving one gains conditions.
extension ActiveSessionView {
    /// What this screen's `⋯` holds (`FR-17.9.7`, `OUT-18.6`).
    ///
    /// **Discard, and never Reset day or Skip remaining.** The free workout is the only record of
    /// itself, so the word that promises a loss is the true one here; and there is no plan to skip
    /// the rest of. Written as a function on ``DayView/menuContents(date:progress:)``' reason —
    /// what a body passes a modifier is readable by nothing, so the two hosts' disagreement has to
    /// be stated where a test can read it.
    ///
    /// - Parameter date: The workout's training date, or `nil` where there is no workout.
    /// - Returns: The commands, in order.
    static func menuContents(date: Date?) -> SessionMenuContents {
        SessionMenuContents(
            date: date, offersSkipRemaining: false, destructive: .discardWorkout)
    }

    /// What **Skip remaining** would do on this screen, which is nothing (`OUT-18.6`).
    ///
    /// **A handler that says so, rather than the `nil` the modifier used to take.** An optional
    /// handler beside a ``SessionMenuContents`` that decides whether the item is drawn is one fact
    /// in two places, and the way the two disagree is a menu row that does nothing when it is
    /// pressed — silent, and invisible to every test that reads the contents. The item is never
    /// drawn here, ``menuContents(date:)`` saying so and
    /// `SessionMenuContentsTests.theFreeWorkoutAsksForDiscard` holding it, so reaching this is a
    /// wiring fault rather than a state.
    static func skipRemainingIsNotOffered() {
        assertionFailure("the free workout's menu never offers Skip remaining (`OUT-18.6`)")
    }

    /// Finishes the workout and leaves the screen, unless the write failed.
    ///
    /// The screen stays open on a failure, with the workout still on it: nothing was stored, so the
    /// retry is another tap at the same command rather than a workout the user has to find again.
    ///
    /// **The store decides whether there is a question to ask** (`FR-16.4.4`), and this only draws
    /// it. A workout holding sets nobody attempted is refused by ``ActiveSessionStore/finish(resolving:)``
    /// itself, which counts them from the repository and reports the count back; asking the cards on
    /// screen instead would be a second answer, and empty exactly when the store is holding a
    /// workout whose cards it has dropped. So the first tap runs the command, the command declines,
    /// and the alert opens on the count it declined with.
    ///
    /// - Parameter resolution: What to do with those sets, or `nil` on the first tap.
    func finish(resolving resolution: SessionFinish.Resolution? = nil) async {
        // The note's own **Save** is inside a fold the user may never have opened, and this command
        // is directly beneath it — so what is in the field is committed with the workout rather
        // than dropped by it. Nothing is written where the field and the record already agree.
        await store.finish(
            saving: noteDraft.hasUnsavedChanges ? noteDraft.text : nil, resolving: resolution)
        // A note that would not store keeps the workout — see `finish(saving:)`. Its diagnostic is
        // inside the fold, so the fold is opened: otherwise the tap reports nothing at all, which
        // is the failure that rule exists to prevent.
        if store.noteWriteFailure != nil { areNotesExpanded = true }
        if pendingSetCount > 0 {
            isResolvingPendingSets = true
            return
        }
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
