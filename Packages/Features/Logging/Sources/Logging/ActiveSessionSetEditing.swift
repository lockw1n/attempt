import Foundation
import PowerliftingCore
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

    /// The draft the editor opens holding — blank, `FR-1.2.6`'s copy of the last set, or
    /// `FR-1.2.7`'s set being edited.
    ///
    /// - Parameter target: What the editor is open over.
    /// - Returns: The draft.
    func draft(for target: SetEditorTarget) -> SetDraft {
        Self.draft(for: target, unit: store.displayUnit, locale: locale)
    }

    /// What a routine planned for one already-logged set, or `nil` (`FR-15.3.1`).
    ///
    /// **Resolved here rather than handed up from the row**, which keeps the card's `edit` closure
    /// the one-argument thing every caller of it already passes — `PastSessionView` included, where
    /// there is no plan to resolve. The card knows the answer too; asking the held list for it
    /// again costs one walk of one exercise's sets, against a signature change through four types.
    ///
    /// - Parameter set: The set the editor is opening over.
    /// - Returns: The group it was planned against, where one planned it.
    func prescription(for set: SetEntry) -> PlannedTargetGroup? {
        store.exercises.first { $0.id == set.entryID }?.plannedTargets[set.id]
    }

    /// ``draft(for:)`` with the unit and the locale passed rather than read off the screen.
    ///
    /// **The choice between the three initialisers is this function's whole content.** A plan comes
    /// first and is the only one whose load can be blank (`FR-15.2.3`); between the other two it is
    /// the note that separates them — an edit is the *same* set, so a form that opened without the
    /// note would delete it on the next confirm, while a duplicate is a set that has not been
    /// performed and repeating a note puts words in the user's mouth.
    ///
    /// - Parameters:
    ///   - target: What the editor is open over.
    ///   - unit: The unit to render the load in.
    ///   - locale: The locale to render the numbers in.
    /// - Returns: The draft.
    static func draft(for target: SetEditorTarget, unit: MassUnit, locale: Locale) -> SetDraft {
        if let planned = target.planned {
            return SetDraft(planning: planned, unit: unit, locale: locale)
        }
        guard let values = target.values else { return SetDraft(unit: unit, locale: locale) }
        return target.editing == nil
            ? SetDraft(repeating: values, unit: unit, locale: locale)
            : SetDraft(editing: values, unit: unit, locale: locale)
    }

    /// The editor, opened over a set that already exists (`FR-1.2.7`).
    ///
    /// **Every field the editor collects comes from the row**, the note and `FR-1.2.8`'s modifiers
    /// included — see ``draft(for:)``. The outcome and the position do not: neither is on this form,
    /// and both are carried across by the write.
    ///
    /// **The prescription is carried but seeds nothing** (`FR-15.3.1`). An edit opens holding the
    /// set as it was logged, plan or no plan — what the group adds is the line above the fields
    /// saying what was asked for, which is the whole of the requirement on a form the sheet covers
    /// the card with.
    ///
    /// - Parameters:
    ///   - set: The set to edit.
    ///   - prescribed: The group that set was planned against, where a routine planned it.
    /// - Returns: The target the sheet presents over.
    static func target(
        editing set: SetEntry, prescribed: PlannedTargetGroup? = nil
    ) -> SetEditorTarget {
        SetEditorTarget(
            entryID: set.entryID,
            values: SetEntryValues(
                weight: set.weight,
                reps: set.reps,
                rpe: set.rpe,
                isWarmup: set.isWarmup,
                modifiers: set.modifiers,
                notes: set.notes
            ),
            editing: set.id,
            prescribed: prescribed
        )
    }

    /// Writes what the confirmed editor decided and closes it (`FR-1.2.3`, `FR-1.2.7`, `NFR-1.8`).
    ///
    /// **The sheet closes before the write is awaited**, which is what `NFR-1.2` is asking for: the
    /// row appears as the store publishes it, with no spinner and nothing between the tap and the
    /// card. The write is local (`G-2.3`), so there is no window in which the card is visibly behind.
    ///
    /// **The card is pinned open, and both kinds of write need it.** Every set logged here is
    /// `isCompleted`, so the first working one makes the exercise complete by `FR-1.2.13`'s rule —
    /// and the rule collapses completed cards, which would fold the card the user is logging into at
    /// the moment they log into it. An edit reaches the same rule by the other column: it can change
    /// whether the set is a warmup, which is what that rule reads to decide whether the exercise is
    /// finished, so the card can fold under the thumb that confirmed the edit exactly as
    /// ``markSet(_:asWarmup:)`` can. An explicit entry in the fold overrides the rule for this card
    /// only: one the user has not touched still follows it, which is what a workout reopened
    /// tomorrow should do.
    ///
    /// **A warmup pins the warmup group open too, and only a warmup does.** Writing a *working*
    /// set may fold that group by ``SessionExerciseList/defaultWarmupExpansion(for:)``'s rule, and
    /// that fold is harmless: it happens above the new row and shortens the card, pulling the set
    /// towards the thumb rather than off screen. Writing a *warmup* into a card that already has
    /// work in it is the opposite case — the same rule would fold the row being written, so the set
    /// would be written and then immediately hidden. See ``markSet(_:asWarmup:)``, which is the same
    /// hazard reached by the other control.
    ///
    /// A draft that does not resolve is ignored rather than trusted — the confirming command is
    /// disabled in that state, so this is the second reading of a guard the editor already applies.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - target: What the editor was open over.
    func write(_ draft: SetDraft, _ target: SetEditorTarget) {
        guard let write = Self.write(draft, over: target) else { return }
        editing = nil
        expansion[target.entryID] = true
        if draft.isWarmup { warmupExpansion[target.entryID] = true }
        Task { await store.write(write) }
    }

    /// What a confirmed editor writes — the one place `FR-1.2.3`'s logging and `FR-1.2.7`'s editing
    /// part company.
    ///
    /// **A value returned rather than a command issued**, so the branch can be answered without a
    /// screen: taken the wrong way it appends a duplicate set where the user asked for a correction,
    /// which is a defect the store cannot catch — both writes are perfectly ordinary from there.
    ///
    /// A draft that does not resolve is `nil`, for ``write(_:_:)``'s reason.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - target: What the editor was open over.
    /// - Returns: The write, or `nil` where the draft does not resolve.
    static func write(_ draft: SetDraft, over target: SetEditorTarget) -> SetEditorWrite? {
        guard let values = draft.resolved else { return nil }
        guard let setID = target.editing else {
            return .add(entryID: target.entryID, values: values)
        }
        return .rewrite(setID: setID, entryID: target.entryID, values: values)
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

    /// Marks a logged set as a warmup or as working (`FR-1.2.4`).
    ///
    /// **A set becoming a warmup pins its card's warmup group open**, for the reason
    /// ``write(_:_:)`` pins the card: the group is folded by default once the work has started, so
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
    /// **A set becoming completed pins its card open**, and it is ``write(_:_:)``'s hazard reached
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
