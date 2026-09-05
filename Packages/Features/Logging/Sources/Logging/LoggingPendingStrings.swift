import Foundation

/// `FR-16.4`'s copy: what a set nobody attempted is called, and the one question Finish asks about
/// them.
///
/// **A file of its own rather than more of `LoggingStrings.swift`**, which had reached SwiftLint's
/// file ceiling. It is the same type, and `LoggingStrings.all` names these keys — see that file for
/// what the list is for.
extension LoggingStrings {
    /// `FR-16.4.4`'s alert title — how many sets nobody attempted.
    ///
    /// **The count is in the sentence rather than beside it**, unlike every other count in this
    /// catalogue: the verb agrees with it, so a numeral next to a fixed noun would read "1 sets
    /// were not logged". That is what the plural table is for.
    ///
    /// - Parameter count: The pending sets.
    /// - Returns: The title.
    static func sessionFinishPendingTitle(_ count: Int) -> LocalizedStringResource {
        resource("logging.session.finish.pending.title \(count)")
    }

    /// What those sets are, and the question the two answers below settle.
    static let sessionFinishPendingMessage = resource("logging.session.finish.pending.message")

    /// The answer that deletes them (`G-1.3`, so they are soft-deleted).
    static let sessionFinishPendingRemove = resource("logging.session.finish.pending.remove")

    /// The answer that keeps them, which ending the session makes failed.
    static let sessionFinishPendingKeep = resource("logging.session.finish.pending.keep")

    /// The way out, naming what it keeps rather than saying "cancel".
    static let sessionFinishPendingCancel = resource("logging.session.finish.pending.cancel")

    /// The command that discards it (`FR-1.2.12`).
}
