import Foundation

/// This module's copy (`G-3.4`), and the only place a history string literal is written.
///
/// Each entry names a key in `Resources/en.lproj/Localizable.strings` — or, for the one that
/// pluralises, in `Localizable.stringsdict` — and binds it to this module's own bundle. The key
/// convention is documented once, in `Localization`.
enum HistoryStrings {
    /// What there is none of, on a first launch (`FR-1.13.2`).
    static let emptyHeadline = resource("history.list.empty.headline")

    /// Where sessions come from, once there are any.
    static let emptyMessage = resource("history.list.empty.message")

    /// The way to make the first one — a tab away, so it is a button rather than a sentence.
    static let emptyAction = resource("history.list.empty.action")

    /// A failed read of the list.
    static let errorHeadline = resource("history.list.error.headline")

    /// What to do about it.
    static let errorMessage = resource("history.list.error.message")

    /// A failed read of the next page, reported under the rows that did load.
    static let moreErrorMessage = resource("history.list.more.error")

    /// A session that was finished with nothing logged into it.
    static let noExercises = resource("history.list.exercises.none")

    /// The row's two numbers as one line — "8 working sets, 7,240 kg".
    ///
    /// **The line is the copy and the accessibility label both.** A pair of labelled metric tiles
    /// reads out to VoiceOver as bare numerals and wraps its numeral across three lines at the
    /// largest Dynamic Type size; one sentence does neither. It says *working* because warmups are
    /// not in the count, and a label that did not say so would be wrong rather than terse.
    ///
    /// - Parameters:
    ///   - sets: How many working sets were performed. The plural agrees with this.
    ///   - volume: The tonnage, already rendered — how a weight reads is `AppFormat`'s, and a
    ///     catalogue cannot decide it.
    /// - Returns: The sentence.
    static func metricsSummary(sets: Int, volume: String) -> LocalizedStringResource {
        resource("history.list.metrics.summary \(sets) \(volume)")
    }

    /// Every key this module can show, for the resolution test.
    ///
    /// The plural is included at one arbitrary count: what the test asks is whether the key resolves
    /// to copy, and a format that resolves at one count resolves at all of them.
    static var all: [LocalizedStringResource] {
        [
            emptyHeadline, emptyMessage, emptyAction,
            errorHeadline, errorMessage, moreErrorMessage,
            noExercises,
            metricsSummary(sets: 1, volume: ""),
        ]
    }

    /// Binds a key to this module's catalogue.
    private static func resource(_ key: String.LocalizationValue) -> LocalizedStringResource {
        LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
    }
}
