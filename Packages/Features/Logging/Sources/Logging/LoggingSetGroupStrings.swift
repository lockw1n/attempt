import Foundation

/// ``LoggingStrings``' ninth file — `FR-16.1.1`'s set groups.
///
/// **The same type in a ninth file, on `LoggingRecordStrings.swift`'s argument**: one enum is what
/// keeps a module's copy in one place, and `file_length` is what keeps that one place readable.
///
/// The seam is the requirement: a group is `FR-16.1`'s reading of sets that `FR-1.2` already
/// stores, and every string here exists because a run of them is drawn as one line.
extension LoggingStrings {
    // MARK: - Set groups (FR-16.1.1, FR-16.1.3)

    /// The badge a group of sets leads with — `FR-16.1.1`'s `1–4`.
    ///
    /// **A format string rather than a dash between two numerals** (`G-3.4`): the range separator is
    /// punctuation this catalogue owns, and both numbers arrive already rendered so that the badge
    /// on a group and the badge on a row beside it go through the same style.
    ///
    /// A warmup group's badge is this, wrapped in ``setWarmupNumber(_:)`` — `W1–4`.
    ///
    /// - Parameters:
    ///   - first: The group's first set's number, already rendered.
    ///   - last: Its last set's number, likewise.
    /// - Returns: The badge.
    static func setNumberRange(first: String, last: String) -> LocalizedStringResource {
        resource("logging.session.set.number-range \(first) \(last)")
    }

    /// The same range as VoiceOver reads that badge (`G-4.2`).
    ///
    /// - Parameters:
    ///   - first: The group's first set's number.
    ///   - last: Its last set's number.
    /// - Returns: The sentence.
    static func setPositionRange(first: Int, last: Int) -> LocalizedStringResource {
        resource("logging.session.set.position-range \(first) \(last)")
    }

    /// A warmup group's range, likewise (`FR-1.2.14`).
    ///
    /// - Parameters:
    ///   - first: The group's first warmup's number.
    ///   - last: Its last warmup's number.
    /// - Returns: The sentence.
    static func setWarmupPositionRange(first: Int, last: Int) -> LocalizedStringResource {
        resource("logging.session.set.warmup.position-range \(first) \(last)")
    }

    /// How many sets a group holds, as VoiceOver's label for the numeral after the second
    /// multiplication sign — which is decorative and hidden, as the first one is.
    ///
    /// **A plural rather than a numeral beside a word**, unlike ``setReps(_:)``: this is the last
    /// thing read in "100 kilograms, 6 reps, 4 sets", and a group never holds one set, so the
    /// English rule is not the reason — Ukrainian's four categories are.
    ///
    /// - Parameter count: How many sets.
    /// - Returns: The phrase.
    static func setGroupCount(_ count: Int) -> LocalizedStringResource {
        resource("logging.session.set.group.count \(count)")
    }

    /// What tapping a group does (`FR-16.1.3`), as VoiceOver's hint on it.
    static let setGroupExpandHint = resource("logging.session.set.group.hint")

    /// One group on `FR-1.2.10`'s strip — a load, a repetition count and how many sets, already
    /// rendered (`FR-16.1.1`).
    ///
    /// **A third argument rather than a repetition of ``sessionPreviousSet(weight:reps:)``**: four
    /// identical sets read as one line and not as a list of four, which is the whole of what the
    /// grouping buys this strip.
    ///
    /// - Parameters:
    ///   - weight: The load, rendered.
    ///   - reps: The repetitions, rendered.
    ///   - sets: How many sets, rendered.
    /// - Returns: The line.
    static func sessionPreviousGroup(
        weight: String, reps: String, sets: String
    ) -> LocalizedStringResource {
        resource("logging.session.previous.group \(weight) \(reps) \(sets)")
    }

    /// Every string this file declares, for the test that renders them all.
    static var allSetGroupStrings: [LocalizedStringResource] {
        [
            setNumberRange(first: "1", last: "4"),
            setPositionRange(first: 1, last: 4),
            setWarmupPositionRange(first: 1, last: 4),
            setGroupCount(4),
            setGroupExpandHint,
            sessionPreviousGroup(weight: "", reps: "", sets: ""),
        ]
    }
}
