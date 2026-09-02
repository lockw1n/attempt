import Foundation
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
    init(
        entryID: UUID,
        values: SetEntryValues? = nil,
        editing: UUID? = nil,
        planned: PlannedSetSeed? = nil,
        prescribed: PlannedTargetGroup? = nil
    ) {
        self.entryID = entryID
        self.values = values
        self.editing = editing
        self.planned = planned
        self.prescribed = prescribed
    }
}
