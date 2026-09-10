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

    /// This file's strings, for ``LoggingStrings/all``.
    static var allPastSessionStrings: [LocalizedStringResource] {
        [
            pastSessionTitle, pastSessionErrorHeadline, pastSessionErrorMessage,
            pastSessionMissingHeadline, pastSessionMissingMessage, pastSessionEmptyHeadline,
            pastSessionEmptyMessage, pastSessionWriteErrorMessage,
        ]
    }
}
