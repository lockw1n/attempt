import Foundation
import RepositoryInterface
import SwiftUI

/// What `ActiveSessionView` does to one logged set: opens the editor over it, writes what comes
/// back, and marks it (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.5`, `FR-1.2.6`, `FR-1.2.7`).
///
/// A second file rather than a longer one, on ``ActiveSessionStore``'s split: the screen proper is
/// the workout and its states, and this is every command a set row or the editor can issue.
///
/// **Every one of them pins the card open, and that is one rule rather than five.** `FR-1.2.13`
/// folds a finished exercise, and *finished* is read off the very columns these commands write — a
/// set's kind, its outcome, and whether it exists at all. So each of these can flip the answer and
/// fold the card under the thumb that just tapped it, taking with it the control that would undo
/// what was done. The pins are dictionary entries and last as long as the screen: a card the user
/// has been shown once stays shown, rather than folding again behind the next set.
extension ActiveSessionView {
    // Internal rather than private throughout: `private` is file-scoped, and these are the screen's
    // own members held in a second file. Nothing outside `Logging` can reach them.

    /// The draft the editor opens holding — blank, or `FR-1.2.6`'s copy of the last set.
    ///
    /// - Parameter target: Which exercise the editor is open over.
    /// - Returns: The draft.
    func draft(for target: SetEditorTarget) -> SetDraft {
        guard let values = target.values else {
            return SetDraft(unit: store.displayUnit, locale: locale)
        }
        // The two differ by the note: an edit is the same set, so a form that opened without it
        // would delete it on the next confirm; a duplicate is a set that has not been performed.
        return target.editing == nil
            ? SetDraft(repeating: values, unit: store.displayUnit, locale: locale)
            : SetDraft(editing: values, unit: store.displayUnit, locale: locale)
    }

    /// The editor, opened over a set that already exists (`FR-1.2.7`).
    ///
    /// **Every field the editor collects comes from the row**, the note included — see
    /// ``draft(for:)``. The outcome and the position do not: neither is on this form, and both are
    /// carried across by the write.
    ///
    /// - Parameter set: The set to edit.
    /// - Returns: The target the sheet presents over.
    static func target(editing set: SetEntry) -> SetEditorTarget {
        SetEditorTarget(
            entryID: set.entryID,
            values: SetEntryValues(
                weight: set.weight,
                reps: set.reps,
                rpe: set.rpe,
                isWarmup: set.isWarmup,
                notes: set.notes
            ),
            editing: set.id
        )
    }

    /// Logs the drafted set and closes the editor (`FR-1.2.3`, `NFR-1.8`).
    ///
    /// **The sheet closes before the write is awaited**, which is what `NFR-1.2` is asking for: the
    /// row appears as the store publishes it, with no spinner and nothing between the tap and the
    /// card. The write is local (`G-2.3`), so there is no window in which the card is visibly behind.
    ///
    /// **The card is pinned open.** Every set logged here is `isCompleted`, so the first working one
    /// makes the exercise complete by `FR-1.2.13`'s rule — and the rule collapses completed cards,
    /// which would fold the card the user is logging into at the moment they log into it. An
    /// explicit entry in the fold overrides that for this card only: one the user has not touched
    /// still follows the rule, which is what a workout reopened tomorrow should do.
    ///
    /// **A warmup pins the warmup group open too, and only a warmup does.** Logging a *working*
    /// set may fold that group by ``SessionExerciseList/defaultWarmupExpansion(for:)``'s rule, and
    /// that fold is harmless: it happens above the new row and shortens the card, pulling the set
    /// towards the thumb rather than off screen. Logging a *warmup* into a card that already has
    /// work in it is the opposite case — the same rule would fold the row being written, so the set
    /// would be logged and then immediately hidden. See ``markSet(_:asWarmup:)``, which is the same
    /// hazard reached by the other control.
    ///
    /// A draft that does not resolve is ignored rather than trusted — the confirming command is
    /// disabled in that state, so this is the second reading of a guard the editor already applies.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - entryID: The exercise to log against.
    func write(_ draft: SetDraft, _ target: SetEditorTarget) {
        guard let setID = target.editing else {
            log(draft, into: target.entryID)
            return
        }
        save(draft, editing: setID, in: target.entryID)
    }

    /// Saves an edit to a logged set and closes the editor (`FR-1.2.7`, `NFR-1.8`).
    ///
    /// **The card is pinned open, and both directions of the kind need it.** Editing can change
    /// whether the set is a warmup, which is the column `FR-1.2.13`'s rule reads to decide whether
    /// the exercise is finished — so the card can fold under the thumb that confirmed the edit,
    /// exactly as ``markSet(_:asWarmup:)`` can. The warmup group is pinned in the one direction that
    /// hides the row, for that command's reason.
    ///
    /// A draft that does not resolve is ignored, for ``log(_:into:)``'s reason.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - setID: The set being edited.
    ///   - entryID: The exercise it belongs to.
    func save(_ draft: SetDraft, editing setID: UUID, in entryID: UUID) {
        guard let weight = draft.weight, let reps = draft.reps, draft.isLoggable else { return }
        let values = SetEntryValues(
            weight: weight,
            reps: reps,
            rpe: draft.storedRPE,
            isWarmup: draft.isWarmup,
            notes: draft.notes
        )
        editing = nil
        expansion[entryID] = true
        if draft.isWarmup { warmupExpansion[entryID] = true }
        Task { await store.editSet(id: setID, inEntryID: entryID, to: values) }
    }

    /// Soft-deletes the set the editor is open over and closes it (`FR-1.2.7`, `G-1.3`).
    ///
    /// **The card is pinned open**, and the case is the one the marking controls have: the deleted
    /// set may be the only working set that was not completed, so the exercise becomes finished by
    /// `FR-1.2.13`'s rule and the card folds the moment the row leaves it.
    ///
    /// A target that is not an edit cannot reach this — the command is drawn only while one is.
    ///
    /// - Parameter target: What the editor is open over.
    func delete(_ target: SetEditorTarget) {
        guard let setID = target.editing else { return }
        editing = nil
        expansion[target.entryID] = true
        Task { await store.deleteSet(id: setID, inEntryID: target.entryID) }
    }

    func log(_ draft: SetDraft, into entryID: UUID) {
        guard let weight = draft.weight, let reps = draft.reps, draft.isLoggable else { return }
        let values = SetEntryValues(
            weight: weight,
            reps: reps,
            rpe: draft.storedRPE,
            isWarmup: draft.isWarmup,
            notes: draft.notes
        )
        editing = nil
        expansion[entryID] = true
        if draft.isWarmup { warmupExpansion[entryID] = true }
        Task { await store.addSet(toEntryID: entryID, values: values) }
    }

    /// Marks a logged set as a warmup or as working (`FR-1.2.4`).
    ///
    /// **A set becoming a warmup pins its card's warmup group open**, for the reason
    /// ``log(_:into:)`` pins the card: the group is folded by default once the work has started, so
    /// a row moved into it would vanish under a heading at the far end of the card, taking the
    /// control that undoes the marking with it. The reverse direction needs nothing *there* — a set
    /// leaving the group is already on screen, and the group it leaves can only have been open for
    /// the badge to have been tappable at all.
    ///
    /// **The card itself is pinned in both directions**, which the group is not, and that is
    /// `FR-1.2.13`'s rule reading a column this control writes: an exercise is finished when its
    /// working sets are all completed and there is at least one, so changing a set's *kind* moves
    /// that answer as surely as ``markSet(_:asCompleted:)`` does. Made working, a completed set can
    /// be the one that finishes the exercise; made a warmup, an uncompleted one can leave behind a
    /// list that is finished without it. Either way the card folds under the thumb that tapped it
    /// and takes the badge that would undo the marking with it.
    ///
    /// Both pins are dictionary entries and so last as long as the screen: a card or a group the
    /// user has been shown once stays shown, rather than folding again behind the next set.
    ///
    /// - Parameters:
    ///   - set: The set to mark.
    ///   - isWarmup: Which kind it becomes.
    func markSet(_ set: SetEntry, asWarmup isWarmup: Bool) {
        expansion[set.entryID] = true
        if isWarmup { warmupExpansion[set.entryID] = true }
        Task { await store.markSet(id: set.id, inEntryID: set.entryID, isWarmup: isWarmup) }
    }

    /// Marks a logged set as completed or failed (`FR-1.2.5`).
    ///
    /// **A set becoming completed pins its card open**, and it is ``log(_:into:)``'s hazard reached
    /// by the other control: an exercise is finished when every working set on it is completed, so
    /// marking the last outstanding one flips `FR-1.2.13`'s rule and folds the card under the thumb
    /// that just tapped it. A card the user opened by hand already carries an entry of its own; the
    /// one this is for is the card that was open because the exercise was *unfinished*, which is
    /// exactly the card this command finishes.
    ///
    /// **The other direction needs no pin.** Marking a set failed can only make its exercise less
    /// finished, and a card that grew more open under a tap is not a card anything was lost from.
    ///
    /// - Parameters:
    ///   - set: The set to mark.
    ///   - isCompleted: Which it becomes.
    func markSet(_ set: SetEntry, asCompleted isCompleted: Bool) {
        if isCompleted { expansion[set.entryID] = true }
        Task { await store.markSet(id: set.id, inEntryID: set.entryID, isCompleted: isCompleted) }
    }
}
