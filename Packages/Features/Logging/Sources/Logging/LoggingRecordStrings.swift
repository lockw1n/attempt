import Foundation

/// ``LoggingStrings``' sixth file — `FR-1.6.3`'s personal-record badge.
///
/// **The same type in a sixth file, on `LoggingPastSessionStrings.swift`'s argument**: one enum is
/// what keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// A file of two strings, because the seam is the requirement rather than the size: a personal
/// record is `FR-1.6`'s, not `FR-1.2`'s, and it reaches this module only because the badge is drawn
/// on a set row.
extension LoggingStrings {
    // MARK: - The personal-record badge (FR-1.6.3)

    /// The badge, as it is drawn on the row.
    ///
    /// **Two characters, and the row's width is the whole reason.** What the badge means in full is
    /// ``setPersonalRecordLabel(_:)``, which VoiceOver reads and the line does not have to hold.
    static let setPersonalRecord = resource("logging.session.set.record")

    /// The same badge as VoiceOver reads it (`G-4.2`), naming the rep counts it stands at.
    ///
    /// **The counts arrive already rendered and joined**, on ``setRPE(_:)``' rule: they are numerals,
    /// and a list of them assembled by string interpolation would be the one place on this row a
    /// number is not formatted for the locale (`G-3.4`).
    ///
    /// - Parameter rendered: The rep counts, formatted and joined for the locale.
    /// - Returns: The label.
    static func setPersonalRecordLabel(_ rendered: String) -> LocalizedStringResource {
        resource("logging.session.set.record.label \(rendered)")
    }

    /// This file's strings, for ``LoggingStrings/all``.
    static var allRecordStrings: [LocalizedStringResource] {
        [setPersonalRecord, setPersonalRecordLabel("5")]
    }
}
