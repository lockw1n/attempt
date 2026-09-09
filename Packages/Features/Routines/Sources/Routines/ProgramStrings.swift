import Foundation

/// ``RoutinesStrings``' second file — the week itself (`FR-17.10`).
///
/// The same enum in a second file, on `LoggingSetGroupStrings.swift`'s argument: one type is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable. The
/// seam is the record — a week is a program row and a day is a routine row (`FR-17.10.2`), so this
/// file is the screen's own chrome and the first file is everything inside a day.
extension RoutinesStrings {
    // MARK: - Edit week (FR-17.10.1)

    /// The screen's navigation title. The screen's rather than the app target's: it is pushed, so
    /// there is no tab whose name it could contradict.
    static let weekEditorTitle = resource("routines.week.title")

    /// What a week authored from **Plan your week** is called until the lifter renames it.
    ///
    /// **A name rather than an empty string**, because `FR-17.8.1` draws it as the heading over
    /// Train's root: a week written with no name at all leaves that heading blank with nothing on
    /// the screen to explain it.
    static let weekEditorDefaultName = resource("routines.week.default-name")

    /// The name field's label.
    static let weekEditorNameLabel = resource("routines.week.name.label")

    /// The name field's placeholder.
    static let weekEditorNamePrompt = resource("routines.week.name.prompt")

    /// The screen's one filled accent — the only control here that commits anything typed.
    static let weekEditorSave = resource("routines.week.save")

    /// Why the last **Save** changed nothing: the field held no name.
    static let weekEditorNameRequired = resource("routines.week.name-required.message")

    /// Why the last write changed nothing: the store refused.
    static let weekEditorWriteError = resource("routines.week.write-error.message")

    /// The heading when the read failed.
    static let weekEditorErrorHeadline = resource("routines.week.error.headline")

    /// What to do about a failed read.
    static let weekEditorErrorMessage = resource("routines.week.error.message")

    /// The heading when the week has no days yet (`FR-1.13.2`).
    static let weekEditorEmptyHeadline = resource("routines.week.empty.headline")

    /// What a week is, for a lifter who has none.
    static let weekEditorEmptyMessage = resource("routines.week.empty.message")

    /// Adds a day to the end of the week (`FR-17.10.1`).
    static let weekEditorAddDay = resource("routines.week.day.add")

    /// Every string this file declares, for the test that renders them all.
    static var allWeekStrings: [LocalizedStringResource] {
        [
            weekEditorTitle, weekEditorDefaultName, weekEditorNameLabel, weekEditorNamePrompt,
            weekEditorSave, weekEditorNameRequired, weekEditorWriteError, weekEditorErrorHeadline,
            weekEditorErrorMessage, weekEditorEmptyHeadline, weekEditorEmptyMessage,
            weekEditorAddDay,
        ]
    }
}
