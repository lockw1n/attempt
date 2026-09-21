import Foundation

/// ``LoggingStrings``' fifth file — a session that is over (`FR-1.2.7`, `FR-1.2.9`).
///
/// **The same type in a fifth file, on `LoggingModifierStrings.swift`'s argument**: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// The middle segment is `past-session` rather than `session`, which is the workout in progress:
/// the two screens are free to diverge, and a shared key is what would stop them.
extension LoggingStrings {
    // MARK: - A past session (FR-1.2.7, FR-1.2.9)

    /// The screen's name before the session it is about has been read.
    ///
    /// **A fallback rather than the title**, unlike the workout in progress': a past session is
    /// identified by its day, so the title is the date once there is one.
    static let pastSessionTitle = resource("logging.past-session.title")

    /// The heading when the session could not be read.
    static let pastSessionErrorHeadline = resource("logging.past-session.error.headline")

    /// What the user can understand about that failure — never the diagnostic.
    static let pastSessionErrorMessage = resource("logging.past-session.error.message")

    /// The heading when the identifier resolves to no session at all.
    static let pastSessionMissingHeadline = resource("logging.past-session.missing.headline")

    /// Why it is not there — deleted, or never on this device.
    static let pastSessionMissingMessage = resource("logging.past-session.missing.message")

    /// The heading when the session exists and has nothing in it.
    static let pastSessionEmptyHeadline = resource("logging.past-session.empty.headline")

    /// What that means — a workout that was started and never logged into.
    static let pastSessionEmptyMessage = resource("logging.past-session.empty.message")

    /// What a failed correction says. The rows are unchanged, so the retry is the same edit again.
    static let pastSessionWriteErrorMessage = resource("logging.past-session.write-error.message")

    /// The button that names the exit (`FR-18.4.3`). It writes nothing — see ``SessionExit``.
    static let pastSessionDoneAction = resource("logging.past-session.done.action")

    // MARK: - The past session's own menu (FR-18.7.3, FR-18.7.5)

    /// The menu's destructive command on a session that is over.
    ///
    /// **Neither *Reset day* nor *Discard* — a third word for a third place** (`FR-18.7.5`). A week
    /// already over has no *upcoming* for a planned day to return to, so the word that is true of
    /// both drawings is the one that names what goes: the workout.
    static let pastSessionDeleteAction = resource("logging.past-session.delete.action")

    /// The confirmation's question, naming the day it is about (`FR-18.7.5`).
    ///
    /// **The day arrives already rendered**, on ``sessionTitleDay(_:)``'s rule: the style is
    /// `AppFormat.date`, bound to the view's locale, and a date formatted here would be the one
    /// date in this module not going through it.
    ///
    /// - Parameter day: The session's training day, already rendered.
    /// - Returns: The question.
    static func pastSessionDeleteConfirmTitle(day: String) -> LocalizedStringResource {
        resource("logging.past-session.delete.confirm.title \(day)")
    }

    /// What goes with it, and that nothing brings it back (`OUT-18.12`).
    ///
    /// - Parameter count: How many logged sets the session holds — warm-ups included, on
    ///   ``dayRowResetConfirmTitle(count:)``'s rule.
    /// - Returns: The message.
    static func pastSessionDeleteConfirmMessage(count: Int) -> LocalizedStringResource {
        resource("logging.past-session.delete.confirm.message \(count)")
    }

    /// Going ahead with it.
    static let pastSessionDeleteConfirmAction = resource("logging.past-session.delete.confirm.action")

    /// Backing out, spelled out rather than a bare *Cancel* — ``dayRemainingConfirmCancel``'s rule,
    /// and on iOS 26 a confirmation rendered as a popover drops an unspelled one outright.
    static let pastSessionDeleteConfirmCancel = resource("logging.past-session.delete.confirm.cancel")

    /// This file's strings, for ``LoggingStrings/all``.
    static var allPastSessionStrings: [LocalizedStringResource] {
        [
            pastSessionTitle, pastSessionErrorHeadline, pastSessionErrorMessage,
            pastSessionMissingHeadline, pastSessionMissingMessage, pastSessionEmptyHeadline,
            pastSessionEmptyMessage, pastSessionWriteErrorMessage, pastSessionDoneAction,
            pastSessionDeleteAction, pastSessionDeleteConfirmTitle(day: "18 September 2026"),
            pastSessionDeleteConfirmMessage(count: 6), pastSessionDeleteConfirmAction,
            pastSessionDeleteConfirmCancel,
        ]
    }
}
