import Foundation

/// ``LoggingStrings``' tenth file — `FR-16.8`'s program on Train.
///
/// The same type in a tenth file, on `LoggingSetGroupStrings.swift`'s argument. The seam is the
/// requirement: every string here exists because a workout can now be the next day of a plan rather
/// than a day on its own.
extension LoggingStrings {
    // MARK: - The next day of the program in force (FR-16.8.2)

    /// The Next-up card's own heading.
    static let programSection = resource("logging.train.program.section")

    /// Where the run has got to, under the program's name — `Week 3 · Day 2`.
    ///
    /// **A format string rather than two labels**, `G-3.4`: the separator is punctuation this
    /// catalogue owns, and a translation is free to reorder the two numbers.
    ///
    /// - Parameters:
    ///   - week: The week the run is on, as the lifter numbers it.
    ///   - day: The day's position in the week, counting from one.
    /// - Returns: The line.
    static func programWeekAndDay(week: Int, day: Int) -> LocalizedStringResource {
        resource("logging.train.program.week-day \(week) \(day)")
    }

    /// `NFR-15.3`'s first tap: into the program's next day.
    static let programStartAction = resource("logging.train.program.start")

    /// Moves the run past a day without logging anything (`FR-16.8.4`).
    static let programSkipAction = resource("logging.train.program.skip")

    /// The heading when the day's routine has been archived (`FR-15.2.5`).
    static let programArchivedHeadline = resource("logging.train.program.archived.headline")

    /// What to do about it — the two ways past, in one line.
    static let programArchivedMessage = resource("logging.train.program.archived.message")

    /// The heading when the program in force has no days.
    static let programNoDaysHeadline = resource("logging.train.program.no-days.headline")

    /// What to do about it.
    static let programNoDaysMessage = resource("logging.train.program.no-days.message")

    // MARK: - Start next week (FR-16.8.4, FR-16.8.5)

    /// The heading when every day of the week has been trained or skipped.
    ///
    /// - Parameter week: The week that is over.
    /// - Returns: The heading.
    static func programWeekCompleteHeadline(week: Int) -> LocalizedStringResource {
        resource("logging.train.program.week-complete.headline \(week)")
    }

    /// What **Start next week** will do, said before it is tapped: where the loads come from, that
    /// they stay editable, and what happens to the week just finished.
    static let programWeekCompleteMessage = resource("logging.train.program.week-complete.message")

    /// The command itself.
    static let programNextWeekAction = resource("logging.train.program.next-week")

    // MARK: - What went wrong (G-3.4 — copy, the diagnostics stay with the store)

    /// The program in force could not be read.
    static let programErrorMessage = resource("logging.train.program.error.message")

    /// **Skip day** wrote nothing.
    static let programSkipErrorMessage = resource("logging.train.program.skip-error.message")

    /// **Start next week** wrote nothing, and took back whatever it had written.
    static let programNextWeekErrorMessage = resource("logging.train.program.next-week-error.message")

    /// The workout was finished and stored, and the program's cursor did not move with it.
    static let programAdvanceErrorMessage = resource("logging.train.program.advance-error.message")

    // MARK: - The week and day a session was started under (FR-16.8.3, DOD-16.1)

    /// Which week and day of a program a session belonged to, on its own screens.
    ///
    /// **A second key rather than ``programWeekAndDay(week:day:)``**, on this module's own rule for
    /// two screens sharing a sentence: Train's card describes a plan and a session's header
    /// describes a fact about a workout, and the two are free to diverge.
    ///
    /// - Parameters:
    ///   - week: The week the session was started under.
    ///   - day: Its day's position, counting from one.
    /// - Returns: The line.
    static func sessionProgramWeekAndDay(week: Int, day: Int) -> LocalizedStringResource {
        resource("logging.session.program.week-day \(week) \(day)")
    }

    /// What that line is called where it is drawn as a fact beside others.
    static let sessionProgramLabel = resource("logging.session.program.label")

    /// Every string this file declares, for the test that renders them all.
    static var allProgramStrings: [LocalizedStringResource] {
        [
            programSection,
            programWeekAndDay(week: 3, day: 2),
            programStartAction,
            programSkipAction,
            programArchivedHeadline,
            programArchivedMessage,
            programNoDaysHeadline,
            programNoDaysMessage,
            programWeekCompleteHeadline(week: 3),
            programWeekCompleteMessage,
            programNextWeekAction,
            programErrorMessage,
            programSkipErrorMessage,
            programNextWeekErrorMessage,
            programAdvanceErrorMessage,
            sessionProgramWeekAndDay(week: 2, day: 1),
            sessionProgramLabel,
        ]
    }
}
