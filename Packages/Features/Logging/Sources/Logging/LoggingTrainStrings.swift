import Foundation
import PowerliftingCore
import RepositoryInterface

/// The Train tab's root: where a workout is started, resumed, or shown as the one in progress.
///
/// **An extension in a fourth file rather than more of ``LoggingStrings``**, on
/// `LoggingModifierStrings.swift`'s argument: the catalogue grows once per screen, `file_length` is
/// what keeps one place readable, and ``LoggingStrings/all`` still sees one list.
extension LoggingStrings {
    // MARK: - Train root (FR-1.2.1, FR-1.2.11, FR-1.13.2)

    /// The heading when nothing is in progress and nothing has been logged into today yet.
    static let trainEmptyHeadline = resource("logging.train.empty.headline")

    /// What to do about it — `FR-1.13.2`'s guidance towards a first workout.
    static let trainEmptyMessage = resource("logging.train.empty.message")

    /// The command that starts a workout (`FR-1.2.1`).
    static let trainStartAction = resource("logging.train.start.action")

    /// The heading over the date control.
    static let trainDateSection = resource("logging.train.date.section")

    /// The date picker's own label — the backdating half of `FR-1.2.1`.
    static let trainDatePicker = resource("logging.train.date.picker")

    /// What the date control is for, where the label alone does not say it.
    static let trainDateHint = resource("logging.train.date.hint")

    /// The heading when a workout is in progress.
    static let trainInProgressSection = resource("logging.train.in-progress.section")

    /// The same card's heading for a workout whose training day has not arrived (`FR-16.6.5`,
    /// `FR-16.4.3`).
    ///
    /// **A word of its own rather than "In progress" over a day in the future**, which is the same
    /// correction the history row carries: a session dated ahead of today has been written and not
    /// performed, and a card claiming it is in progress says the lifter is mid-workout.
    static let trainPlannedSection = resource("logging.train.planned.section")

    /// What Train's card calls the workout it is holding.
    ///
    /// **A finished session reads as in progress, and that is not a case this screen has.**
    /// `ActiveSessionStore` holds only an open workout, so the third state cannot reach here; it is
    /// answered rather than trapped because a heading is not the place to discover it.
    ///
    /// - Parameter lifecycle: Which kind of workout the card is holding.
    /// - Returns: The heading.
    static func trainSessionSection(_ lifecycle: SessionLifecycle) -> LocalizedStringResource {
        switch lifecycle {
        case .planned: trainPlannedSection
        case .inProgress, .finished: trainInProgressSection
        }
    }

    /// The training day the workout in progress belongs to.
    static let trainInProgressDay = resource("logging.train.in-progress.day")

    /// When the workout in progress was started.
    static let trainInProgressStarted = resource("logging.train.in-progress.started")

    /// The way back into the workout in progress (`FR-1.2.11`).
    static let trainInProgressResume = resource("logging.train.in-progress.resume")

    /// The way into the exercise library from the session surface.
    static let trainLibraryAction = resource("logging.train.library.action")

    /// The way into the routines (`FR-15.2.1`), beside the library's.
    static let trainRoutinesAction = resource("logging.train.routines.action")

    /// The heading when the workouts could not be read.
    static let trainErrorHeadline = resource("logging.train.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let trainErrorMessage = resource("logging.train.error.message")

    /// A start that could not be written — a failed *write*, beside the command that issued it.
    static let trainStartErrorMessage = resource("logging.train.start-error.message")
}
