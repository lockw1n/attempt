import Foundation

/// ``LoggingStrings``' ninth file — `FR-17.9`'s day checklist, and the overflow menu the free
/// workout shares with it.
///
/// The same type in another file, on `LoggingModifierStrings.swift`'s argument: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
extension LoggingStrings {
    // MARK: - The day's rows (FR-17.9.1, FR-17.9.3)

    /// How far through the day the lifter is, over the rows.
    ///
    /// - Parameters:
    ///   - done: How many rows are answered.
    ///   - total: How many there are.
    /// - Returns: The heading.
    static func dayProgress(done: Int, of total: Int) -> LocalizedStringResource {
        resource("logging.day.progress \(done) \(total)")
    }

    /// What a row the lifter decided against says (`FR-17.9.6`).
    static let dayRowSkipped = resource("logging.day.row.skipped")

    /// A row logged exactly as the plan prescribed it — one line rather than two.
    ///
    /// - Parameter performed: What was done, rendered.
    /// - Returns: The line.
    static func dayRowAsPlanned(performed: String) -> LocalizedStringResource {
        resource("logging.day.row.as-planned \(performed)")
    }

    /// The first of the two lines a row that deviated from the plan draws.
    ///
    /// - Parameter plan: What was prescribed, rendered.
    /// - Returns: The line.
    static func dayRowPlanned(plan: String) -> LocalizedStringResource {
        resource("logging.day.row.planned \(plan)")
    }

    /// The second of them.
    ///
    /// - Parameter performed: What was done, rendered.
    /// - Returns: The line.
    static func dayRowDid(performed: String) -> LocalizedStringResource {
        resource("logging.day.row.did \(performed)")
    }

    // MARK: - The row's own commands (FR-17.9.2, FR-17.9.6)

    /// The circle, named for what it does rather than for its shape (`G-4.2`, `NFR-1.10`).
    static let dayCircleAction = resource("logging.day.circle.action")

    /// The way into the set editor for a row the circle cannot answer (`FR-17.9.3`).
    static let dayLogAction = resource("logging.day.log.action")

    /// Recording that the lifter is not doing this exercise today (`FR-17.9.6`).
    static let daySkipAction = resource("logging.day.skip.action")

    // MARK: - The whole-day commands (FR-17.9.9, FR-17.8.8)

    /// Logging everything that is left exactly as planned.
    static let dayLogRemainingAction = resource("logging.day.log-remaining.action")

    /// Deciding against everything that is left.
    static let daySkipRemainingAction = resource("logging.day.skip-remaining.action")

    /// The confirmation the first of those asks for, naming the count.
    ///
    /// - Parameter count: How many rows would be logged.
    /// - Returns: The question.
    static func dayLogRemainingConfirmTitle(count: Int) -> LocalizedStringResource {
        resource("logging.day.log-remaining.confirm.title \(count)")
    }

    /// The confirmation the second asks for, naming the count.
    ///
    /// - Parameter count: How many rows would be skipped.
    /// - Returns: The question.
    static func daySkipRemainingConfirmTitle(count: Int) -> LocalizedStringResource {
        resource("logging.day.skip-remaining.confirm.title \(count)")
    }

    /// Going ahead with the first.
    static let dayLogRemainingConfirmAction = resource("logging.day.log-remaining.confirm.action")

    /// Going ahead with the second.
    static let daySkipRemainingConfirmAction = resource("logging.day.skip-remaining.confirm.action")

    /// Backing out of either.
    ///
    /// **Spelled out rather than a bare *Cancel***, on the discard dialog's rule: a
    /// `confirmationDialog` renders as a popover on iOS 26 and drops its cancel button, so the
    /// destructive one has to be the thing that is hard to hit by accident.
    static let dayRemainingConfirmCancel = resource("logging.day.remaining.confirm.cancel")

    /// What **Log remaining as planned** reports about the rows it could not answer
    /// (`FR-15.2.2`).
    ///
    /// - Parameter exercises: Their names, joined.
    /// - Returns: The sentence.
    static func dayUnanswerable(exercises: String) -> LocalizedStringResource {
        resource("logging.day.unanswerable \(exercises)")
    }

    /// What joins those names.
    static let dayUnanswerableSeparator = resource("logging.day.unanswerable.separator")

    // MARK: - The overflow menu (FR-17.9.7)

    /// The menu itself, named for the menu rather than for either item in it (`G-4.2`).
    static let dayMenuAction = resource("logging.day.menu.action")

    /// `FR-1.2.1`'s backdating, from the menu.
    static let dayChangeDateAction = resource("logging.day.change-date.action")

    /// Closing the date sheet.
    static let dayChangeDateDone = resource("logging.day.change-date.done")

    // MARK: - The rest of the screen

    /// Adding an exercise the plan did not name (`FR-1.2.2`).
    static let dayAddExerciseAction = resource("logging.day.add-exercise.action")

    /// What a day with a session but no rows in it says.
    static let dayNoRowsHeadline = resource("logging.day.no-rows.headline")

    /// What to do about it.
    static let dayNoRowsMessage = resource("logging.day.no-rows.message")

    /// Every string this file declares, for the test that renders them all.
    static var allDayStrings: [LocalizedStringResource] {
        [
            dayProgress(done: 2, of: 4),
            dayRowSkipped,
            dayRowAsPlanned(performed: "100 kg × 5 × 5"),
            dayRowPlanned(plan: "100 kg × 5 × 5"),
            dayRowDid(performed: "100 kg × 5 × 4"),
            dayCircleAction,
            dayLogAction,
            daySkipAction,
            dayLogRemainingAction,
            daySkipRemainingAction,
            dayLogRemainingConfirmTitle(count: 3),
            daySkipRemainingConfirmTitle(count: 2),
            dayLogRemainingConfirmAction,
            daySkipRemainingConfirmAction,
            dayRemainingConfirmCancel,
            dayUnanswerable(exercises: "Ab Wheel"),
            dayUnanswerableSeparator,
            dayMenuAction,
            dayChangeDateAction,
            dayChangeDateDone,
            dayAddExerciseAction,
            dayNoRowsHeadline,
            dayNoRowsMessage,
        ]
    }
}
