import Foundation

/// `FR-1.5.2`'s history row: what one logged set says, and what `FR-16.1.1` adds when several read
/// as one.
///
/// A file of its own rather than more of ``ExerciseLibraryStrings``, which had reached SwiftLint's
/// length ceiling — `ExerciseLibraryE1RMStrings.swift`'s argument, at the seam one row makes. Same
/// type, same catalogue, same key convention.
extension ExerciseLibraryStrings {
    /// `G-1.8`'s warmup flag, as a history row says it.
    ///
    /// A word rather than the live row's `W1` badge: there is no number to prefix here — a past
    /// session's set is read in place, not counted off during a workout — and `G-4.5` will not let
    /// the dimmer type carry the distinction alone.
    static let historyWarmup = resource("exerciselibrary.detail.history.warmup")

    /// `FR-1.2.5`'s failed set, as VoiceOver reads the glyph on that row (`G-4.2`).
    static let historyFailed = resource("exerciselibrary.detail.history.failed")

    /// The repetitions, as VoiceOver reads them — the numeral alone is a number with no unit.
    ///
    /// - Parameter reps: How many were performed.
    /// - Returns: The label.
    static func historyReps(_ reps: Int) -> LocalizedStringResource {
        resource("exerciselibrary.detail.history.reps \(reps)")
    }

    /// How many sets a run holds (`FR-16.1.1`), as VoiceOver reads the numeral after the second
    /// multiplication sign — which is decorative and hidden, as the first one is.
    ///
    /// **A plural rather than a numeral beside a word**, unlike ``historyReps(_:)``: "Sets 4" beside
    /// a row that already numbers nothing reads as *set number four*, which is the one thing this
    /// numeral does not mean.
    ///
    /// - Parameter count: How many sets.
    /// - Returns: The phrase.
    static func historySets(_ count: Int) -> LocalizedStringResource {
        resource("exerciselibrary.detail.history.sets \(count)")
    }

    /// The rating, in `FR-1.5.2`'s `@ RPE` position.
    ///
    /// **The number arrives already rendered**, on `SetRow`'s rule: it is a `Double` with an optional
    /// half step, and interpolating it here would write `8.5` into a locale that writes `8,5`.
    ///
    /// - Parameter rendered: The rating, formatted for the locale.
    /// - Returns: The label.
    static func historyRPE(_ rendered: String) -> LocalizedStringResource {
        resource("exerciselibrary.detail.history.rpe \(rendered)")
    }

    /// Every string this file declares, for the test that renders them all.
    static var allHistoryRowStrings: [LocalizedStringResource] {
        [historyWarmup, historyFailed, historyReps(5), historySets(4), historyRPE("8")]
    }
}
