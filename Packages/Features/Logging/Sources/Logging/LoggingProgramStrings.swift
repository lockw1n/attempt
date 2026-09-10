import Foundation

/// ``LoggingStrings``' tenth file — `FR-16.8`'s program on Train.
///
/// The same type in a tenth file, on `LoggingSetGroupStrings.swift`'s argument. The seam is the
/// requirement: every string here exists because a workout can now be the next day of a plan rather
/// than a day on its own.
///
/// **`FR-16.8.2`'s Next-up card had nine of these and has none now.** The card and **Skip day**
/// retired with `FR-17.8.7` and `FR-17.8.2`; a string nothing draws is copy the translation gate
/// keeps asking a translator to maintain, so the keys left both catalogues with the views.
extension LoggingStrings {
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

    /// **Start next week** wrote nothing, and took back whatever it had written.
    static let programNextWeekErrorMessage = resource("logging.train.program.next-week-error.message")

    // MARK: - The week and day a session was started under (FR-16.8.3, DOD-16.1)

    /// Which week and day of a program a session belonged to, on its own screens.
    ///
    /// **A key of its own rather than one shared with Train's**, on this module's own rule for two
    /// screens sharing a sentence: a plan and a fact about a workout are free to diverge. Train's
    /// own copy of it retired with `FR-16.8.2`'s card; this one describes a stored session and
    /// stays.
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
            programWeekCompleteHeadline(week: 3),
            programWeekCompleteMessage,
            programNextWeekAction,
            programNextWeekErrorMessage,
            sessionProgramWeekAndDay(week: 2, day: 1),
            sessionProgramLabel,
        ]
    }
}
