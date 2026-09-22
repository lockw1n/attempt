import Foundation
import RepositoryInterface

// The two questions a day's screen opens over one of its rows — the Log sheet's target, and the
// reset's. Their own file for `DayResetCommand.swift`'s reason: `DayView.swift` is the screen and
// had reached `file_length`'s ceiling, and these grow with what a row can be asked about.

/// Which row's answer is being taken back, and what the question names (`FR-18.5.1`,
/// `FR-18.5.2`).
///
/// **The count is carried rather than looked up when the dialog draws**, so a re-read landing
/// underneath an open question cannot change what it asks. The screen keeps the last count asked
/// beside this (``DayView``'s `askedSetCount`), because the target is `nil` again while the dialog
/// animates out and the title is still on screen then.
struct DayRowResetTarget: Identifiable, Equatable {
    /// The row.
    let rowID: UUID

    /// How many sets it would remove. Whole sets, at least 1 — see ``DayRow/loggedSetCount``.
    let setCount: Int

    /// The row's identity is the question's.
    var id: UUID { rowID }
}

/// Which row the Log sheet is open over (`FR-17.9.3`, `FR-17.9.4`).
///
/// **The row rather than the entry**, because the sheet can be opened on a day that has no session
/// yet: the first answer creates it, and the row is what survives that (see
/// ``DayStore/log(rowID:rows:)``).
struct DayLogTarget: Identifiable, Equatable {
    /// The row.
    let rowID: UUID

    /// The plan, what is already logged, and whether the row is answered — what the sheet's row
    /// mode is drawn from.
    let row: SetEditorRow

    /// What the routine prescribed for the next set, drawn above the fields (`FR-15.3.1`).
    let prescribed: PlannedTargetGroup?

    /// The row's identity is the sheet's.
    var id: UUID { rowID }

    /// The same thing in the shape the shared editor takes.
    var editorTarget: SetEditorTarget {
        SetEditorTarget(entryID: rowID, prescribed: prescribed, row: row)
    }
}
