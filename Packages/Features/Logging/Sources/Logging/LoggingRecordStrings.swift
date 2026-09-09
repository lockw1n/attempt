import Foundation

/// ``LoggingStrings``' sixth file — `FR-1.6.3`'s personal-record badge, `FR-17.2.3`'s wording.
///
/// **The same type in a sixth file, on `LoggingPastSessionStrings.swift`'s argument**: one enum is
/// what keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// A file of eight strings, because the seam is the requirement rather than the size: a personal
/// record is `FR-1.6`'s, not `FR-1.2`'s, and it reaches this module only because the badge is drawn
/// on a set row.
///
/// **Two spellings by two states, which is why there are four badges and four labels.** A cell at
/// one set is written `8 reps` and every other cell `5×5` — never `8RM`, which claims the *at least
/// N* reading `D-17.2` withdrew, and never `× 1`, which nobody writes. Crossing that with
/// `FR-17.2.2`'s record and first-performance states gives the four, and they are four strings
/// rather than a word interpolated into a form: a translator needs the whole phrase to inflect.
///
/// **The four rep-counted keys are in the module's `.stringsdict`, the four scheme ones beside
/// them in the `.strings`.** `%lld reps` counts a noun and is drawn at one on every 1RM; `5×5` and
/// `5 by 5` count nothing.
extension LoggingStrings {
    // MARK: - The personal-record badge (FR-1.6.3, FR-17.2.2, FR-17.2.3)

    /// The record badge over a run, as it is drawn on the line — `PR · 5×5`.
    ///
    /// **Short, and the row's width is the whole reason.** What it means in full is
    /// ``setPersonalRecordSchemeLabel(reps:sets:)``, which VoiceOver reads and the line does not have
    /// to hold.
    ///
    /// - Parameters:
    ///   - reps: The scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The badge.
    static func setPersonalRecordScheme(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.scheme \(reps) \(sets)")
    }

    /// The record badge over a single set — `PR · 8 reps`.
    ///
    /// - Parameter reps: The N the record stands at.
    /// - Returns: The badge.
    static func setPersonalRecordReps(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.reps \(reps)")
    }

    /// The first-performance badge over a run — `First · 5×5` (`FR-17.2.2`, `Q-17.1`).
    ///
    /// **The word the feed already uses**, so the two surfaces agree by sharing it — see
    /// `dashboard.recent-records.baseline`, which is where *First* was first written.
    ///
    /// - Parameters:
    ///   - reps: The scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The badge.
    static func setFirstPerformanceScheme(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.first.scheme \(reps) \(sets)")
    }

    /// The first-performance badge over a single set — `First · 8 reps`.
    ///
    /// - Parameter reps: The N.
    /// - Returns: The badge.
    static func setFirstPerformanceReps(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.first.reps \(reps)")
    }

    /// The record scheme badge as VoiceOver reads it (`G-4.2`) — "personal record, 5 by 5".
    ///
    /// **"by" rather than the multiplication sign**, which VoiceOver announces as punctuation or not
    /// at all depending on the reader's verbosity — the same reason ``DesignSystem/DeltaIndicator``
    /// forces punctuation on rather than trusting it.
    ///
    /// - Parameters:
    ///   - reps: The scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The label.
    static func setPersonalRecordSchemeLabel(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.scheme.label \(reps) \(sets)")
    }

    /// The record single-set badge as VoiceOver reads it — "personal record, 8 reps".
    ///
    /// **One string with a numeral in it and no plural rule**, on this module's: English reads
    /// "1 reps" only in the one case a record at a single rep is drawn, which is the same compromise
    /// every count in this module already makes, and Ukrainian's own forms are the translator's.
    ///
    /// - Parameter reps: The N.
    /// - Returns: The label.
    static func setPersonalRecordRepsLabel(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.record.reps.label \(reps)")
    }

    /// The first-performance scheme badge as VoiceOver reads it — "first time, 5 by 5".
    ///
    /// - Parameters:
    ///   - reps: The scheme's repetitions.
    ///   - sets: How many consecutive sets it stands at.
    /// - Returns: The label.
    static func setFirstPerformanceSchemeLabel(reps: Int, sets: Int) -> LocalizedStringResource {
        resource("logging.session.set.first.scheme.label \(reps) \(sets)")
    }

    /// The first-performance single-set badge as VoiceOver reads it — "first time, 8 reps".
    ///
    /// - Parameter reps: The N.
    /// - Returns: The label.
    static func setFirstPerformanceRepsLabel(_ reps: Int) -> LocalizedStringResource {
        resource("logging.session.set.first.reps.label \(reps)")
    }

    /// This file's strings, for ``LoggingStrings/all``.
    static var allRecordStrings: [LocalizedStringResource] {
        [
            setPersonalRecordScheme(reps: 5, sets: 5),
            setPersonalRecordReps(8),
            setFirstPerformanceScheme(reps: 5, sets: 5),
            setFirstPerformanceReps(8),
            setPersonalRecordSchemeLabel(reps: 5, sets: 5),
            setPersonalRecordRepsLabel(8),
            setFirstPerformanceSchemeLabel(reps: 5, sets: 5),
            setFirstPerformanceRepsLabel(8),
        ]
    }
}
