import Foundation

/// This module's copy (`G-3.4`), and the only place a logging string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` and binds it to this module's
/// own bundle. The key convention is documented once, in `Localization`.
///
/// The two middle segments are the two screens this task builds: `train` is the tab's root — where a
/// workout is started, resumed or shown as in progress — and `session` is the workout itself. A
/// string that both would show is still written twice, once per screen, because the two are free to
/// diverge and a shared key is what stops them.
enum LoggingStrings {
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

    /// The training day the workout in progress belongs to.
    static let trainInProgressDay = resource("logging.train.in-progress.day")

    /// When the workout in progress was started.
    static let trainInProgressStarted = resource("logging.train.in-progress.started")

    /// The way back into the workout in progress (`FR-1.2.11`).
    static let trainInProgressResume = resource("logging.train.in-progress.resume")

    /// The way into the exercise library from the session surface.
    static let trainLibraryAction = resource("logging.train.library.action")

    /// The heading over `NFR-1.9`'s toggle.
    static let trainScreenWakeSection = resource("logging.train.screen-wake.section")

    /// The toggle itself (`NFR-1.9`).
    static let trainScreenWakeLabel = resource("logging.train.screen-wake.label")

    /// What the toggle does, in the one sentence the label has no room for.
    static let trainScreenWakeHint = resource("logging.train.screen-wake.hint")

    /// The heading when the workouts could not be read.
    static let trainErrorHeadline = resource("logging.train.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let trainErrorMessage = resource("logging.train.error.message")

    // MARK: - The workout in progress (FR-1.2.11, FR-1.2.12)

    /// The screen's navigation title.
    ///
    /// The screen's rather than the app target's, unlike a tab root's: this one is pushed, so there
    /// is no tab whose name it could contradict.
    static let sessionTitle = resource("logging.session.title")

    /// The heading over the workout's own facts.
    static let sessionSummarySection = resource("logging.session.summary.section")

    /// The training day this workout belongs to.
    static let sessionDay = resource("logging.session.day")

    /// When it was started.
    static let sessionStarted = resource("logging.session.started")

    /// The heading when the workout has no exercises in it yet.
    static let sessionEmptyHeadline = resource("logging.session.empty.headline")

    /// What will fill it.
    static let sessionEmptyMessage = resource("logging.session.empty.message")

    /// The command that finishes the workout (`FR-1.2.11`).
    static let sessionFinishAction = resource("logging.session.finish.action")

    /// The command that discards it (`FR-1.2.12`).
    static let sessionDiscardAction = resource("logging.session.discard.action")

    /// The confirmation's question (`FR-1.2.12`).
    static let sessionDiscardConfirmTitle = resource("logging.session.discard.confirm.title")

    /// What discarding costs, said before it is done.
    static let sessionDiscardConfirmMessage = resource("logging.session.discard.confirm.message")

    /// The confirming button.
    static let sessionDiscardConfirmAction = resource("logging.session.discard.confirm.action")

    /// The way out of the confirmation.
    static let sessionDiscardConfirmCancel = resource("logging.session.discard.confirm.cancel")

    /// The heading when the screen is open on a workout that is no longer in progress.
    static let sessionEndedHeadline = resource("logging.session.ended.headline")

    /// Why it is not there — finished, or discarded.
    static let sessionEndedMessage = resource("logging.session.ended.message")

    /// What the user can understand about a write that failed.
    static let sessionWriteErrorMessage = resource("logging.session.write-error.message")

    /// Every string this module can show, for the test that proves each one resolves.
    static var all: [LocalizedStringResource] {
        [
            trainEmptyHeadline, trainEmptyMessage, trainStartAction, trainDateSection,
            trainDatePicker, trainDateHint, trainInProgressSection, trainInProgressDay,
            trainInProgressStarted, trainInProgressResume, trainLibraryAction,
            trainScreenWakeSection, trainScreenWakeLabel, trainScreenWakeHint, trainErrorHeadline,
            trainErrorMessage, sessionTitle, sessionSummarySection, sessionDay, sessionStarted,
            sessionEmptyHeadline, sessionEmptyMessage, sessionFinishAction, sessionDiscardAction,
            sessionDiscardConfirmTitle, sessionDiscardConfirmMessage, sessionDiscardConfirmAction,
            sessionDiscardConfirmCancel, sessionEndedHeadline, sessionEndedMessage,
            sessionWriteErrorMessage,
        ]
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
