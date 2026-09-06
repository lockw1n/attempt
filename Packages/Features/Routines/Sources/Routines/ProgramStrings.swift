import Foundation

/// ``RoutinesStrings``' second file — `FR-16.8`'s programs.
///
/// The same enum in a second file, on `LoggingSetGroupStrings.swift`'s argument: one type is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable. The
/// seam is the requirement — a program is an ordered list of the routines the first file's screens
/// author.
extension RoutinesStrings {
    // MARK: - The list (FR-16.8.1)

    /// The row on the routine list that opens the programs.
    static let programsLink = resource("routines.programs.link")

    /// The list's own navigation title.
    static let programsTitle = resource("routines.programs.title")

    /// The command that opens the one-field prompt writing a new program.
    static let programsNew = resource("routines.programs.new")

    /// That prompt's own title.
    static let programsNewTitle = resource("routines.programs.new.title")

    /// Its placeholder.
    static let programsNewPrompt = resource("routines.programs.new.prompt")

    /// Its confirming button.
    static let programsCreate = resource("routines.programs.new.create")

    /// The heading when nothing has been authored yet.
    static let programsEmptyHeadline = resource("routines.programs.empty.headline")

    /// What a program is, for a lifter who has none.
    static let programsEmptyMessage = resource("routines.programs.empty.message")

    /// The heading when the read failed.
    static let programsErrorHeadline = resource("routines.programs.error.headline")

    /// What to do about a failed read.
    static let programsErrorMessage = resource("routines.programs.error.message")

    /// Why nothing was written — the prompt's field held no name.
    static let programsNameRequiredMessage = resource("routines.programs.name-required.message")

    /// Why nothing was written — the store refused.
    static let programsWriteErrorMessage = resource("routines.programs.write-error.message")

    /// The mark on the one program in force (`FR-16.8.1`).
    static let programsCurrentBadge = resource("routines.programs.current")

    /// A program with no name, which the list draws in place of one.
    static let programsUnnamed = resource("routines.programs.row.unnamed")

    /// How many days a program is made of.
    ///
    /// - Parameter count: The day count.
    /// - Returns: The phrase.
    static func programsDayCount(_ count: Int) -> LocalizedStringResource {
        resource("routines.programs.day-count \(count)")
    }

    // MARK: - The editor (FR-16.8.1)

    /// The editor's navigation title.
    static let programEditorTitle = resource("routines.program-editor.title")

    /// What the name field is for.
    static let programEditorNameLabel = resource("routines.program-editor.name.label")

    /// Its placeholder.
    static let programEditorNamePrompt = resource("routines.program-editor.name.prompt")

    /// What the note field is for.
    static let programEditorNoteLabel = resource("routines.program-editor.note.label")

    /// Its placeholder.
    static let programEditorNotePrompt = resource("routines.program-editor.note.prompt")

    /// Stores the name and the note.
    static let programEditorSave = resource("routines.program-editor.save")

    /// The section the days are listed in.
    static let programEditorDaysSection = resource("routines.program-editor.days.section")

    /// The heading when the program has none.
    static let programEditorDaysEmptyHeadline = resource(
        "routines.program-editor.days.empty.headline")

    /// What to do about it.
    static let programEditorDaysEmptyMessage = resource(
        "routines.program-editor.days.empty.message")

    /// The section the routines a day can name are listed in.
    static let programEditorAddSection = resource("routines.program-editor.add.section")

    /// The heading when the library holds no routine to build a day from.
    static let programEditorAddEmptyHeadline = resource("routines.program-editor.add.empty.headline")

    /// What to do about it.
    static let programEditorAddEmptyMessage = resource("routines.program-editor.add.empty.message")

    /// Takes one day out of the program.
    static let programEditorRemoveDay = resource("routines.program-editor.day.remove")

    /// Moves it one place earlier in the week.
    static let programEditorDayUp = resource("routines.program-editor.day.up")

    /// Moves it one place later.
    static let programEditorDayDown = resource("routines.program-editor.day.down")

    /// Makes this the program Train offers (`FR-16.8.2`).
    static let programEditorMakeCurrent = resource("routines.program-editor.make-current")

    /// What that command says once it has been taken.
    static let programEditorIsCurrent = resource("routines.program-editor.is-current")

    /// A day whose routine has been archived (`FR-15.2.5`).
    static let programEditorArchivedRoutine = resource("routines.program-editor.day.archived")

    /// One day's position, counted from one.
    ///
    /// - Parameter number: Its place in the week.
    /// - Returns: The heading.
    static func programEditorDayNumber(_ number: Int) -> LocalizedStringResource {
        resource("routines.program-editor.day.number \(number)")
    }

    /// The heading when no live program carries the identifier the route named.
    static let programEditorMissingHeadline = resource("routines.program-editor.missing.headline")

    /// What happened to it.
    static let programEditorMissingMessage = resource("routines.program-editor.missing.message")

    /// The heading when the read failed.
    static let programEditorErrorHeadline = resource("routines.program-editor.error.headline")

    /// What to do about it.
    static let programEditorErrorMessage = resource("routines.program-editor.error.message")

    /// Why the last write changed nothing.
    static let programEditorWriteError = resource("routines.program-editor.write-error.message")

    /// Every string this file declares, for the test that renders them all.
    static var allProgramStrings: [LocalizedStringResource] {
        [
            programsLink, programsTitle, programsNew, programsNewTitle, programsNewPrompt,
            programsCreate, programsEmptyHeadline, programsEmptyMessage, programsErrorHeadline,
            programsErrorMessage, programsNameRequiredMessage, programsWriteErrorMessage,
            programsCurrentBadge, programsUnnamed,
            programEditorTitle, programEditorNameLabel, programEditorNamePrompt,
            programEditorNoteLabel, programEditorNotePrompt, programEditorSave,
            programEditorDaysSection, programEditorDaysEmptyHeadline, programEditorDaysEmptyMessage,
            programEditorAddSection, programEditorAddEmptyHeadline, programEditorAddEmptyMessage,
            programEditorRemoveDay, programEditorDayUp, programEditorDayDown,
            programEditorMakeCurrent, programEditorIsCurrent, programEditorArchivedRoutine,
            programEditorMissingHeadline, programEditorMissingMessage, programEditorErrorHeadline,
            programEditorErrorMessage, programEditorWriteError,
        ]
            + [1, 2].map(programsDayCount)
            + [1, 2].map(programEditorDayNumber)
    }
}
