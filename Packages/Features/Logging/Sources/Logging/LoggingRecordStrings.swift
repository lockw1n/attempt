import Foundation

/// ``LoggingStrings``' sixth file — `FR-1.6.3`'s personal-record badge, `FR-16.2.4`'s wording.
///
/// **The same type in a sixth file, on `LoggingPastSessionStrings.swift`'s argument**: one enum is
/// what keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// A file of four strings, because the seam is the requirement rather than the size: a personal
/// record is `FR-1.6`'s, not `FR-1.2`'s, and it reaches this module only because the badge is drawn
/// on a set row.
///
/// **The badge names one scheme, and there are two spellings of one.** The one-set column is
/// `FR-1.6.1`'s rep max and a lifter writes it `8RM`; every other cell is a scheme and they write it
/// `5×5`. Two strings rather than one with a `× 1` in it: nobody calls their heaviest single a
/// "1 × 1", and a badge that did would be the app's notation rather than theirs.
extension LoggingStrings {
    // MARK: - The personal-record badge (FR-1.6.3, FR-16.2.4)

    /// The badge over a run, as it is drawn on the line — `PR 5×5`.
    ///
    /// **Short, and the row's width is the whole reason.** What it means in full is
    /// ``setPersonalRecordSchemeLabel(reps:sets:)``, which VoiceOver reads and the line does not have
    /// to hold.
    ///
    /// - Parameters:
    ///   - reps: The maximal scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The badge.
    static func setPersonalRecordScheme(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.scheme \(reps) \(sets)")
    }

    /// The badge over a single set — `PR 8RM`, the one-set column's own spelling.
    ///
    /// - Parameter reps: The N the record stands at.
    /// - Returns: The badge.
    static func setPersonalRecordRepMax(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.rep-max \(reps)")
    }

    /// The scheme badge as VoiceOver reads it (`G-4.2`) — "personal record, 5 by 5".
    ///
    /// **"by" rather than the multiplication sign**, which VoiceOver announces as punctuation or not
    /// at all depending on the reader's verbosity — the same reason ``DesignSystem/DeltaIndicator``
    /// forces punctuation on rather than trusting it.
    ///
    /// - Parameters:
    ///   - reps: The maximal scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The label.
    static func setPersonalRecordSchemeLabel(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.scheme.label \(reps) \(sets)")
    }

    /// The rep-max badge as VoiceOver reads it.
    ///
    /// **One string with a numeral in it and no plural rule**, on this module's: the noun is "max"
    /// and the numeral sits inside the compound before it, which reads the same at every count — the
    /// pair of forms this replaced existed only because the old label put the numeral beside "rep".
    ///
    /// - Parameter reps: The N.
    /// - Returns: The label.
    static func setPersonalRecordRepMaxLabel(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.rep-max.label \(reps)")
    }

    /// This file's strings, for ``LoggingStrings/all``.
    static var allRecordStrings: [LocalizedStringResource] {
        [
            setPersonalRecordScheme(reps: 5, sets: 5),
            setPersonalRecordRepMax(8),
            setPersonalRecordSchemeLabel(reps: 5, sets: 5),
            setPersonalRecordRepMaxLabel(8),
        ]
    }
}
