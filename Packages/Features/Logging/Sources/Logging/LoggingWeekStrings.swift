import Foundation

/// ``LoggingStrings``' eleventh file — `FR-17.8`'s week on Train, and the day it opens.
///
/// The same type in an eleventh file, on `LoggingProgramStrings.swift`'s argument. The seam is the
/// requirement: every string here exists because the tab's root is *this week* rather than a
/// session (`D-17.5`).
extension LoggingStrings {
    // MARK: - The week (FR-17.8.1)

    /// Which week of the run this is, under the program's own name.
    ///
    /// - Parameter week: The week the run is on, as the lifter numbers it.
    /// - Returns: The line.
    static func weekHeading(week: Int) -> LocalizedStringResource {
        resource("logging.week.heading \(week)")
    }

    /// What the root's toolbar menu is called.
    ///
    /// **Named for the menu, not for either item in it** (`G-4.2`): it holds Edit week and the
    /// library, so borrowing one of their labels would tell VoiceOver the other is not there.
    static let weekMenuAction = resource("logging.week.menu.action")

    /// The way into the week's plan (`FR-17.8.3`, `FR-17.10`).
    static let weekEditAction = resource("logging.week.edit.action")

    /// The way into the exercise catalogue, now that the root's card has gone (`Q-17.7`).
    static let weekLibraryAction = resource("logging.week.library.action")

    /// A workout no program planned (`FR-17.8.3`).
    static let weekFreeWorkoutAction = resource("logging.week.free-workout.action")

    /// What that workout's own card is called while it is open.
    static let weekFreeWorkoutTitle = resource("logging.week.free-workout.title")

    // MARK: - One day's card (FR-17.8.1, FR-17.8.2)

    /// Where a day sits in the week, counted from one — drawn on every card, and the whole of what
    /// a card whose routine has been archived can say about itself.
    ///
    /// - Parameter day: The day's position, counting from one.
    /// - Returns: The caption.
    static func weekDay(_ day: Int) -> LocalizedStringResource {
        resource("logging.week.day \(day)")
    }

    /// The command on a day nothing has been logged into.
    static let weekDayStartAction = resource("logging.week.day.start")

    /// The command on a day part-answered (`FR-1.2.11`).
    static let weekDayContinueAction = resource("logging.week.day.continue")

    /// How far through a started day the lifter is.
    ///
    /// - Parameters:
    ///   - done: Exercises answered.
    ///   - total: Exercises in the day.
    /// - Returns: The line.
    static func weekDayProgress(done: Int, of total: Int) -> LocalizedStringResource {
        resource("logging.week.day.progress \(done) \(total)")
    }

    /// A finished day, collapsed to its header line.
    ///
    /// **The date arrives rendered**, on ``sessionPlanTarget(weight:reps:)``' split: `AppFormat`
    /// decides how a day reads in a locale and a catalogue cannot.
    ///
    /// - Parameter day: The training day, rendered.
    /// - Returns: The line.
    static func weekDayDone(on day: String) -> LocalizedStringResource {
        resource("logging.week.day.done \(day)")
    }

    // MARK: - The plan on a card (FR-17.8.1)

    /// One exercise and what the routine prescribes for it — `Squat · 140 kg × 5 × 5`.
    ///
    /// **A format string rather than two labels**, `G-3.4`: the separator is punctuation this
    /// catalogue owns, and a translation is free to reorder the halves.
    ///
    /// - Parameters:
    ///   - exercise: The lift's name, as the lifter's locale spells it.
    ///   - plan: Its targets, already joined.
    /// - Returns: The line.
    static func weekPlanLine(exercise: String, plan: String) -> LocalizedStringResource {
        resource("logging.week.plan.line \(exercise) \(plan)")
    }

    /// One target group — load, reps, sets.
    ///
    /// - Parameters:
    ///   - weight: The prescribed load, rendered.
    ///   - reps: Reps per set.
    ///   - sets: Sets prescribed.
    /// - Returns: The target.
    static func weekPlanTarget(weight: String, reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.week.plan.target \(weight) \(reps) \(sets)")
    }

    /// The same target where the plan named no load (`FR-15.2.2`).
    ///
    /// - Parameters:
    ///   - reps: Reps per set.
    ///   - sets: Sets prescribed.
    /// - Returns: The target.
    static func weekPlanTargetOpenLoad(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.week.plan.target-open \(reps) \(sets)")
    }

    /// What separates one target group from the next on a plan line.
    static let weekPlanTargetSeparator = resource("logging.week.plan.target.separator")

    // MARK: - The week's own states (FR-1.13.1, FR-17.8.5)

    /// The heading when the lifter is running no program (`FR-1.13.2`).
    static let weekEmptyHeadline = resource("logging.week.empty.headline")

    /// What to do about it.
    static let weekEmptyMessage = resource("logging.week.empty.message")

    /// The command that gets there (`FR-17.8.5`).
    static let weekPlanAction = resource("logging.week.plan.action")

    /// The heading when the week could not be read.
    static let weekErrorHeadline = resource("logging.week.error.headline")

    /// What the lifter can understand about that failure — never the diagnostic.
    static let weekErrorMessage = resource("logging.week.error.message")

    // MARK: - One day, read only (TR-17.6)

    /// The heading over what the day prescribes.
    static let dayPlanHeading = resource("logging.day.plan.heading")

    /// What a row that has been answered says (`FR-15.3.4`).
    static let dayRowDone = resource("logging.day.row.done")

    /// The heading when the day has nothing in it.
    static let dayEmptyHeadline = resource("logging.day.empty.headline")

    /// What to do about it. **Not only the archived routine** (`FR-15.2.5`): this state is also
    /// a day whose routine prescribes nothing, and a stamp naming a week that is no longer the
    /// one in force.
    static let dayEmptyMessage = resource("logging.day.empty.message")

    /// The heading when the day could not be read.
    static let dayErrorHeadline = resource("logging.day.error.headline")

    /// What the lifter can understand about that failure.
    static let dayErrorMessage = resource("logging.day.error.message")

    /// Every string this file declares, for the test that renders them all.
    static var allWeekStrings: [LocalizedStringResource] {
        [
            weekHeading(week: 3),
            weekMenuAction,
            weekEditAction,
            weekLibraryAction,
            weekFreeWorkoutAction,
            weekFreeWorkoutTitle,
            weekDay(2),
            weekDayStartAction,
            weekDayContinueAction,
            weekDayProgress(done: 2, of: 4),
            weekDayDone(on: "Mon 7 Sep"),
            weekPlanLine(exercise: "Squat", plan: "140 kg × 5 × 5"),
            weekPlanTarget(weight: "140 kg", reps: 5, sets: 5),
            weekPlanTargetOpenLoad(reps: 5, sets: 5),
            weekPlanTargetSeparator,
            weekEmptyHeadline,
            weekEmptyMessage,
            weekPlanAction,
            weekErrorHeadline,
            weekErrorMessage,
            dayPlanHeading,
            dayRowDone,
            dayEmptyHeadline,
            dayEmptyMessage,
            dayErrorHeadline,
            dayErrorMessage,
        ]
    }
}
