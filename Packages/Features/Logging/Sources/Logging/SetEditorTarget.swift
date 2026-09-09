import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface

// A file of its own rather than the top of `SetEditorView.swift`, which had reached
// SwiftLint's file ceiling: this is what the sheet is presented over, not the sheet.

/// Which exercise the set editor is open over, what it opened filled in with, and whether it is
/// editing a set that already exists (`FR-1.2.7`).
///
/// **Identified by the entry while a set is being added**, because that is what makes the sheet
/// re-present when the user closes it and taps another card: two drafts against one exercise are the
/// same sheet, two exercises are two. **An edit is identified by the set instead**, and it has to
/// be: two sets on one card are two different edits, and keyed on the entry the second would
/// re-present the first one's form.
struct SetEditorTarget: Identifiable, Equatable {
    /// The exercise the set belongs to, or is being logged against.
    let entryID: UUID

    /// What the form opens filled in with — `FR-1.2.6`'s duplicate, or the set being edited.
    /// `nil` for a blank one.
    let values: SetEntryValues?

    /// The set being edited (`FR-1.2.7`), or `nil` while one is being added.
    let editing: UUID?

    /// What a routine planned for the next set (`FR-15.2.3`), or `nil` where nothing planned it.
    ///
    /// **A second seeding field rather than a wider ``values``**, and the two are exclusive: that
    /// one is a set that was performed and always has a load, this one is a prescription whose load
    /// may be blank. See ``PlannedSetSeed``.
    let planned: PlannedSetSeed?

    /// What a routine prescribed for the set this form is over, drawn above the fields
    /// (`FR-15.3.1`), or `nil` where nothing planned it.
    ///
    /// **A second field beside ``planned`` because the two have different jobs on different
    /// paths.** That one seeds the fields and is applied only where the form opens blank; this one
    /// is *shown*, whatever the form opened holding — so an edit of a logged set carries it while
    /// carrying no seed at all, and a duplicate carries both. Where both are set they come from one
    /// group, ``SessionExercise/plannedSeed`` being that group's two numbers.
    let prescribed: PlannedTargetGroup?

    /// The day's checklist row this form is answering (`FR-17.9.4`), or `nil` on a free workout.
    ///
    /// **What separates the sheet's two modes**, and it carries the row rather than a flag: the
    /// plan is what the Planned / Actual pair is measured against, and the sets already logged are
    /// what a reopened form fills itself in from (`FR-17.7.5`).
    let row: SetEditorRow?

    /// Which form is drawn — see ``SetEditorMode``.
    var mode: SetEditorMode {
        if let row { return .row(row) }
        return .set(isEditing: editing != nil)
    }

    /// The set being edited, or the entry: see the type's note.
    var id: UUID { editing ?? entryID }

    /// Builds the target.
    ///
    /// - Parameters:
    ///   - entryID: The exercise the set belongs to.
    ///   - values: What the form opens filled in with, where it opens filled in.
    ///   - editing: The set being edited, where one is.
    ///   - planned: What a routine planned for the next set, where one did.
    ///   - prescribed: The group that plan came from, where the form has one to show.
    ///   - row: The checklist row being answered, where the sheet is a day's (`FR-17.9.4`).
    init(
        entryID: UUID,
        values: SetEntryValues? = nil,
        editing: UUID? = nil,
        planned: PlannedSetSeed? = nil,
        prescribed: PlannedTargetGroup? = nil,
        row: SetEditorRow? = nil
    ) {
        self.entryID = entryID
        self.values = values
        self.editing = editing
        self.planned = planned
        self.prescribed = prescribed
        self.row = row
    }
}

/// The checklist row the Log sheet is answering (`FR-17.9.4`, `FR-17.7.5`).
///
/// **The whole plan rather than the next group**, because the sheet answers a whole exercise: the
/// circle writes every planned set in one tap, and a form that could only see the first group would
/// measure a three-set answer against a one-set target.
///
/// **And the sets already logged rather than a count**, because a reopened form is prefilled from
/// them — per-set reps, ratings, warm-up marks and notes included — and the rewrite it saves is
/// matched to them by position (``SetGroupRewrite``).
///
/// **Whether the row is *answered* is deliberately not here.** A skip is an answer holding no sets,
/// so the fact cannot be read off ``logged`` — but it decides a *write*, not a form: what the sheet
/// opens holding is the same either way, and the only screen that needs it reads it from
/// ``DayStore/isAnswered(rowID:)`` at the moment it writes. Carried here it would be read at the
/// moment the sheet opened, which is one whole session-creation earlier.
struct SetEditorRow: Equatable {
    /// What the routine prescribed, in order. Empty for a row the lifter added (`FR-1.2.2`).
    let plan: [WeekPlanTarget]

    /// Every set already logged against the row, in order — warmups included, on
    /// ``SetGroupRewrite``'s rule that the group is the whole entry.
    let logged: [SetEntry]

    /// Builds the row.
    ///
    /// - Parameters:
    ///   - plan: What was prescribed.
    ///   - logged: What is already stored against it.
    init(plan: [WeekPlanTarget], logged: [SetEntry] = []) {
        self.plan = plan
        self.logged = logged
    }
}

/// Which of the sheet's two forms is drawn (`FR-17.1.1`, `OUT-17.8`).
///
/// **A value rather than two booleans on the view**, because the three questions a caller asks of
/// it — the heading, whether the set count is offered, what the confirming command reads — have to
/// agree, and a screen that answered them separately is how *Log set* survives in one of them.
enum SetEditorMode: Equatable {
    /// A day's checklist row: the plan above, the Planned / Actual pair below, the per-set fold,
    /// and **Skip this exercise** beside **Save as done**.
    case row(SetEditorRow)

    /// A free workout's set — today's form, kept as it is until `OUT-17.8`'s phase.
    case set(isEditing: Bool)

    /// Whether this is a checklist row's form.
    var isRow: Bool {
        if case .row = self { return true }
        return false
    }

    /// Whether the form is over a set that already exists (`FR-1.2.7`) — what offers the deletion.
    var isEditing: Bool {
        if case .set(let isEditing) = self { return isEditing }
        return false
    }

    /// Whether the **Sets** field is drawn.
    ///
    /// **Never on an edit of one set.** That form is over a row that exists; a count there would be
    /// asking how many of *this* set there are, which is not a question about it.
    var offersSetCount: Bool { !isEditing }

    /// The sheet's heading. One word — **Log** — wherever a set is being written (`FR-17.1.6`).
    var heading: LocalizedStringResource {
        isEditing ? LoggingStrings.setEditorEditTitle : LoggingStrings.setEditorTitle
    }

    /// What the confirming command reads.
    ///
    /// **A row's says what it does to the row**: it answers the exercise *and* marks it done
    /// (`FR-17.9.4`), which "Save" alone would not say.
    var confirmLabel: LocalizedStringResource {
        switch self {
        case .row: LoggingStrings.setSaveDoneAction
        case .set(let isEditing):
            isEditing ? LoggingStrings.setSaveAction : LoggingStrings.setConfirmAction
        }
    }
}
