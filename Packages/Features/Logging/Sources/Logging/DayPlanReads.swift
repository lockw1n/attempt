import Foundation
import PowerliftingCore
import RepositoryInterface

// What the Log sheet is opened with, split out of `DayStore.swift` at SwiftLint's file ceiling.
// Every one of these reads and none of them writes, which is the line the split was made on.

extension DayStore {
    /// What the Log sheet opens over `rowID` (`FR-17.9.4`, `FR-17.7.5`).
    ///
    /// **The plan and what is stored** — the two things the sheet needs and the one place they are
    /// read together. Composed here rather than on the screen for ``seed(forRow:)``'s reason: the
    /// mapping from a row to its entry is this store's.
    ///
    /// Whether the row is answered is *not* carried: that decides the write rather than the form,
    /// and it is read at the moment of writing — see ``isAnswered(rowID:)``.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The row, or `nil` where the day has none by that identity.
    func editorRow(forRow rowID: UUID) -> SetEditorRow? {
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        return SetEditorRow(
            plan: row.plan,
            logged: store.exercises.first { $0.id == rowID }?.sets ?? [])
    }

    /// Whether the row has already been answered — what decides between a write and a rewrite.
    ///
    /// **A row the day does not hold is *not* answered**, and the default matters: written as a
    /// comparison against the optional, a missing row reads as answered and the save becomes a
    /// rewrite of a group nobody has logged. Appending is the safe answer to "I cannot tell" —
    /// it is what an unanswered row does, and it is the only one of the two that cannot
    /// soft-delete a set the lifter has.
    ///
    /// **It answers about whatever identity ``rows`` is currently keyed by**, which is the routine's
    /// slots before the day has a session and the entries after — so a caller holding a row id from
    /// before ``startIfNeeded()`` has to translate it through ``entryID(forRow:)`` first. Internal
    /// rather than private so both halves of that can be asserted.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: Whether it carries an answer.
    func isAnswered(rowID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        return row.answer != .unanswered
    }

    /// What the editor opens filled in with for `rowID` (`FR-15.2.3`), or `nil` where nothing was
    /// planned for it.
    ///
    /// **The session's own plan once there is one, the routine's before that.** They are the same
    /// numbers on a day nobody has logged into; once sets exist, only the first knows which planned
    /// group the next set falls in.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The seed, or `nil`.
    public func seed(forRow rowID: UUID) -> PlannedSetSeed? {
        if let exercise = store.exercises.first(where: { $0.id == rowID }) {
            return exercise.plannedSeed
        }
        guard let target = planLines.first(where: { $0.id == rowID })?.targets.first else {
            return nil
        }
        return PlannedSetSeed(weight: target.weight, reps: target.reps)
    }

    /// What the routine prescribed for the next set of `rowID`, drawn above the editor's fields
    /// (`FR-15.3.1`), or `nil`.
    ///
    /// Only where the session exists: the line reports a *group*, and a day not yet started has
    /// none of its own to report.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The group, or `nil`.
    public func prescribed(forRow rowID: UUID) -> PlannedTargetGroup? {
        store.exercises.first { $0.id == rowID }?.nextPlannedGroup
    }
}
