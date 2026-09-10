import Foundation

/// What is left of the Train tab's session-shaped controls after `FR-17.8.7`.
///
/// **An extension in a fourth file rather than more of ``LoggingStrings``**, on
/// `LoggingModifierStrings.swift`'s argument: the catalogue grows once per screen, `file_length` is
/// what keeps one place readable, and ``LoggingStrings/all`` still sees one list.
///
/// The root's own strings are `LoggingWeekStrings.swift`'s now. What stays here is the date control
/// `T-17.11` re-hosts as **Change date** (`FR-17.9.7`), the fact row the free workout's card draws,
/// and the one failed *write* the root still reports.
extension LoggingStrings {
    // MARK: - The date control (FR-1.2.1), hosted by a day from T-17.11

    /// The heading over the date control.
    static let trainDateSection = resource("logging.train.date.section")

    /// The date picker's own label — the backdating half of `FR-1.2.1`.
    static let trainDatePicker = resource("logging.train.date.picker")

    /// What the date control is for, where the label alone does not say it.
    static let trainDateHint = resource("logging.train.date.hint")

    // MARK: - The free workout in progress (FR-17.8.3)

    /// The training day the workout in progress belongs to.
    static let trainInProgressDay = resource("logging.train.in-progress.day")

    /// A start that could not be written — a failed *write*, beside the command that issued it.
    static let trainStartErrorMessage = resource("logging.train.start-error.message")
}
