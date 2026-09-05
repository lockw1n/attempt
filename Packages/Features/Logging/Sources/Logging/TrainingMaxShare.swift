import Foundation
import Localization
import PowerliftingCore

/// A load read as a percentage of the training max in force (`FR-16.7.1`).
///
/// **Display only.** The set editor and the routine editor take kilograms, as before; a percentage
/// *input* is `OUT-16.1` and Phase 2's `FR-2.2.1`. Nothing here is stored, and nothing reads it
/// back.
///
/// **One home for the sentence**, so a target line and a set row cannot round or word it
/// differently — which on a screen that draws both, one above the other, is the failure worth
/// preventing.
enum TrainingMaxShare {
    /// The annotation, or `nil` where there is none to draw.
    ///
    /// **`nil` covers three cases and the caller draws none of them**: the exercise has no training
    /// max, the number in force is unusable, or the load is one no percentage can be stated for.
    /// What they have in common is that there is nothing true to say — and `FR-16.7.1`'s absence is
    /// no zero and no dash. See ``PowerliftingCore/Weight/percentOfTrainingMax(_:)``.
    ///
    /// - Parameters:
    ///   - load: The weight being annotated.
    ///   - trainingMax: The number in force on the session's training day, or `nil`.
    ///   - locale: The locale the percentage is rendered for (`G-3.4`).
    /// - Returns: The annotation, or `nil`.
    static func annotation(
        for load: Weight, against trainingMax: Weight?, locale: Locale
    ) -> LocalizedStringResource? {
        guard let percent = percent(for: load, against: trainingMax) else { return nil }
        return annotation(percent, locale: locale)
    }

    /// The share as a number, for a caller comparing two of them rather than drawing one.
    ///
    /// - Parameters:
    ///   - load: The weight.
    ///   - trainingMax: The number in force, or `nil`.
    /// - Returns: The whole percent, or `nil` where there is none to state.
    static func percent(for load: Weight, against trainingMax: Weight?) -> Int? {
        guard let trainingMax else { return nil }
        return load.percentOfTrainingMax(trainingMax)
    }

    /// One share, in words.
    ///
    /// - Parameters:
    ///   - percent: The whole percent.
    ///   - locale: The locale it is rendered for (`G-3.4`).
    /// - Returns: The annotation.
    static func annotation(_ percent: Int, locale: Locale) -> LocalizedStringResource {
        // A proportion rather than a percentage, which is what `AppFormat.percentage` takes — the
        // rounding has already happened in whole percents, so the style's one decimal place never
        // shows and the symbol lands where the locale puts it.
        LoggingStrings.setTrainingMaxShare(
            (Double(percent) / 100).formatted(AppFormat.percentage(locale: locale)))
    }
}
