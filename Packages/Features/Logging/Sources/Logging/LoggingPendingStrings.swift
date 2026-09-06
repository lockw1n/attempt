import Foundation

/// `FR-16.4`'s copy: what a set's outcome is called now that there are three of them, and the one
/// question Finish asks about the sets nobody attempted.
///
/// **A file of its own rather than more of `LoggingStrings.swift`**, which had reached SwiftLint's
/// file ceiling. It is the same type, and `LoggingStrings.all` names these keys — see that file for
/// what the list is for.
extension LoggingStrings {
    /// What a set's outcome is (`FR-1.2.5`, `FR-16.4.1`), as VoiceOver's label for the glyph that
    /// says it.
    ///
    /// **The word the glyph stands for**, which is what keeps the outcome off the tint alone
    /// (`G-4.5`): the row draws a check, a cross or a hollow circle, and this is the same fact in a
    /// sentence. A pending set says *pending* rather than *failed* — the whole of `FR-16.4.1`.
    ///
    /// - Parameter outcome: Which of the three the set is.
    /// - Returns: The outcome, as a word.
    static func setOutcome(_ outcome: SetOutcome) -> LocalizedStringResource {
        switch outcome {
        case .completed: resource("logging.session.set.outcome.completed")
        case .failed: resource("logging.session.set.outcome.failed")
        case .pending: resource("logging.session.set.outcome.pending")
        }
    }

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
}
