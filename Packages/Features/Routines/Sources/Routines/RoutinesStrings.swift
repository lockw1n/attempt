import Foundation
import PowerliftingCore

/// This module's copy (`G-3.4`), and the only place a routines string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
enum RoutinesStrings {
    // MARK: - The list (FR-15.2.1)

    /// The list's own navigation title. The screen's rather than the app target's: it is pushed, so
    /// there is no tab whose name it could contradict.
    static let listTitle = resource("routines.list.title")

    /// The command that opens the editor on a new routine.
    static let listNewRoutine = resource("routines.list.new")

    /// The heading when nothing has been authored yet.
    static let listEmptyHeadline = resource("routines.list.empty.headline")

    /// What a routine is, for a lifter who has none.
    static let listEmptyMessage = resource("routines.list.empty.message")

    /// The heading when the read failed.
    static let listErrorHeadline = resource("routines.list.error.headline")

    /// What to do about a failed read.
    static let listErrorMessage = resource("routines.list.error.message")

    /// The command that starts a workout from a routine (`FR-15.2.3`).
    static let listStartAction = resource("routines.list.start")

    /// Why no workout was started — there is already one in progress.
    static let listStartInProgressMessage = resource("routines.list.start.in-progress.message")

    /// Why no workout was started — the session could not be written.
    static let listStartWriteErrorMessage = resource("routines.list.start.write-error.message")

    /// A routine with no name, which the editor cannot save and a foreign row can still hold.
    static let listUnnamed = resource("routines.list.row.unnamed")

    // MARK: - Managing the library (FR-15.2.5)

    /// Copies a routine, content and all.
    static let listDuplicate = resource("routines.list.duplicate")

    /// Opens the one-field prompt that retitles a routine.
    static let listRename = resource("routines.list.rename")

    /// Takes a routine out of the library without touching what was logged from it.
    static let listArchive = resource("routines.list.archive")

    /// Backs out of either prompt.
    static let listCancel = resource("routines.list.cancel")

    /// The rename prompt's own title.
    static let listRenameTitle = resource("routines.list.rename.title")

    /// The rename prompt's placeholder — the editor's, so one field is asked for one way.
    static let listRenamePrompt = resource("routines.editor.name.prompt")

    /// The archive prompt's title, which is the question it asks.
    static let listArchiveTitle = resource("routines.list.archive.title")

    /// What archiving costs and what it does not — the sentence that makes the confirmation worth
    /// showing, this being the one command here with no way back.
    static let listArchiveMessage = resource("routines.list.archive.message")

    /// Why a rename changed nothing: the field was empty.
    static let listNameRequiredMessage = resource("routines.list.manage.name-required.message")

    /// Why a duplicate, rename or archive changed nothing: the store refused the write.
    static let listManageWriteErrorMessage = resource("routines.list.manage.write-error.message")

    /// What a copy is called, from what the original is called (`FR-15.2.5`).
    ///
    /// **Resolved against the process locale, not the screen's**, and then *stored* — so the copy
    /// keeps the wording of the language the lifter duplicated it in, exactly as the name they
    /// typed themselves would. A name is user data the moment it is written.
    ///
    /// - Parameter name: The original routine's name.
    /// - Returns: The copy's name.
    static func listDuplicateName(_ name: String) -> LocalizedStringResource {
        resource("routines.list.duplicate.name \(name)")
    }

    /// How many exercises a routine prescribes.
    ///
    /// **Plural, and the count is an argument** — see the `.stringsdict` beside the catalogue for
    /// why Ukrainian needs four forms where English needs two.
    ///
    /// - Parameter count: The routine's exercise count.
    /// - Returns: The line under the routine's name.
    static func listExerciseCount(_ count: Int) -> LocalizedStringResource {
        resource("routines.list.row.exercises \(count)")
    }

    // MARK: - The editor (FR-15.2.1, FR-15.2.2)

    /// The editor's title while a routine is being authored.
    static let editorCreateTitle = resource("routines.editor.create.title")

    /// The editor's title over an existing routine.
    static let editorEditTitle = resource("routines.editor.edit.title")

    /// The name field's label.
    static let editorNameLabel = resource("routines.editor.name.label")

    /// The name field's placeholder.
    static let editorNamePrompt = resource("routines.editor.name.prompt")

    /// Why the save command is off while the name is empty.
    static let editorNameCaption = resource("routines.editor.name.caption")

    /// The heading over the exercise slots.
    static let editorExercisesSection = resource("routines.editor.exercises.section")

    /// The heading when the routine has no exercises in it yet.
    static let editorExercisesEmptyHeadline = resource("routines.editor.exercises.empty.headline")

    /// What to do about a routine with no exercises.
    static let editorExercisesEmptyMessage = resource("routines.editor.exercises.empty.message")

    /// The command that pushes the catalogue as a chooser.
    static let editorAddExercise = resource("routines.editor.exercise.add")

    /// The command that drops an exercise from the routine.
    static let editorRemoveExercise = resource("routines.editor.exercise.remove")

    /// A slot whose catalogue row could not be read — drawn broken rather than dropped.
    static let editorUnnamedExercise = resource("routines.editor.exercise.unnamed")

    /// Moves an exercise one place earlier.
    static let editorMoveUp = resource("routines.editor.move.up")

    /// Moves an exercise one place later.
    static let editorMoveDown = resource("routines.editor.move.down")

    /// One target group's heading, by position — the top set, then the backoffs.
    ///
    /// - Parameter position: The group's one-based position within its exercise.
    /// - Returns: The heading.
    static func editorGroupHeading(_ position: Int) -> LocalizedStringResource {
        resource("routines.editor.group.heading \(position)")
    }

    /// The target load's label.
    static let editorWeightLabel = resource("routines.editor.group.weight.label")

    /// The target load's placeholder, which is where `FR-15.2.2`'s blank target is offered.
    static let editorWeightPrompt = resource("routines.editor.group.weight.prompt")

    /// The prescribed repetitions' label.
    static let editorRepsLabel = resource("routines.editor.group.reps.label")

    /// The prescribed sets' label.
    static let editorSetsLabel = resource("routines.editor.group.sets.label")

    /// The badge on a group whose load is deliberately blank (`FR-15.2.2`).
    ///
    /// **A word rather than an empty field speaking for itself**, and a word rather than a tint
    /// (`G-4.5`): a blank load and a load of zero must not be told apart by the absence of
    /// something.
    static let editorBlankTarget = resource("routines.editor.group.blank")

    /// Adds a target group to an exercise (`FR-15.2.1`'s amendment).
    static let editorAddGroup = resource("routines.editor.group.add")

    /// Drops one target group.
    static let editorRemoveGroup = resource("routines.editor.group.remove")

    /// Moves a target group one place earlier.
    static let editorGroupUp = resource("routines.editor.group.up")

    /// Moves a target group one place later.
    static let editorGroupDown = resource("routines.editor.group.down")

    /// Why the save command is off while a group is incomplete.
    static let editorGroupRefusal = resource("routines.editor.group.refusal")

    /// The command that commits the draft.
    static let editorSave = resource("routines.editor.save")

    /// The heading when the editor's read failed.
    static let editorErrorHeadline = resource("routines.editor.error.headline")

    /// What to do about a failed read.
    static let editorErrorMessage = resource("routines.editor.error.message")

    /// The heading when the routine is no longer there.
    static let editorMissingHeadline = resource("routines.editor.missing.headline")

    /// Why reading again would not help.
    static let editorMissingMessage = resource("routines.editor.missing.message")

    /// What a failed save says, beside the command that retries it.
    static let editorWriteError = resource("routines.editor.write.error")

    /// The load's unit, which is the user's display preference rather than a constant (`G-3.1`).
    ///
    /// - Parameter unit: The unit loads are entered in.
    /// - Returns: The symbol.
    static func unitSymbol(for unit: MassUnit) -> LocalizedStringResource {
        switch unit {
        case .kilograms: resource("routines.editor.group.unit.kilograms")
        case .pounds: resource("routines.editor.group.unit.pounds")
        }
    }

    /// Every resource this type can produce, for the test that resolves each one against the
    /// catalogue — `ExerciseLibraryStrings`' own suite has the argument for why a list is kept.
    static var allResources: [LocalizedStringResource] {
        [
            listTitle, listNewRoutine, listEmptyHeadline, listEmptyMessage, listErrorHeadline,
            listErrorMessage, listStartAction, listStartInProgressMessage,
            listStartWriteErrorMessage, listUnnamed, listDuplicate, listRename, listArchive,
            listCancel, listRenameTitle, listRenamePrompt, listArchiveTitle, listArchiveMessage,
            listNameRequiredMessage, listManageWriteErrorMessage,
            editorCreateTitle, editorEditTitle, editorNameLabel,
            editorNamePrompt, editorNameCaption, editorExercisesSection,
            editorExercisesEmptyHeadline, editorExercisesEmptyMessage, editorAddExercise,
            editorRemoveExercise, editorUnnamedExercise, editorMoveUp, editorMoveDown,
            editorWeightLabel, editorWeightPrompt, editorRepsLabel, editorSetsLabel,
            editorBlankTarget, editorAddGroup, editorRemoveGroup, editorGroupUp, editorGroupDown,
            editorGroupRefusal, editorSave, editorErrorHeadline, editorErrorMessage,
            editorMissingHeadline, editorMissingMessage, editorWriteError,
        ]
            + [listDuplicateName("Push")]
            + [1, 2].map(listExerciseCount)
            + [1, 2].map(editorGroupHeading)
            + MassUnit.allCases.map(unitSymbol(for:))
    }

    /// Binds a key to this module's catalogue.
    static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
