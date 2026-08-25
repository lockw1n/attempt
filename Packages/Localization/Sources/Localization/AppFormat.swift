import Foundation
import PowerliftingCore

/// The kinds of value this app renders, each bound to an explicit locale (`G-3.4`).
///
/// **No style here defaults its locale**, which is the point: a default is how a screen ends up
/// rendering against `Locale.autoupdatingCurrent` in a preview and against the environment in the
/// app, and how a test ends up asserting whatever the running machine happens to be set to. In a
/// view the argument is `@Environment(\.locale)`.
///
/// Interpolating a number into a string is the failure these replace — `"\(reps) × \(kg)"` writes
/// `102.5` in a locale that writes `102,5`, and no test on this machine can see it.
public enum AppFormat {
    /// A mass in `unit`, rounded to `precision` (`G-3.1`, `G-3.3`).
    ///
    /// - Parameters:
    ///   - unit: The display unit.
    ///   - precision: The step to round the displayed number to.
    ///   - locale: The locale to render for.
    /// - Returns: The style.
    public static func weight(
        in unit: MassUnit, precision: DisplayPrecision, locale: Locale
    ) -> WeightStyle {
        WeightStyle(unit: unit, precision: precision, locale: locale)
    }

    /// A mass in `unit` at `G-3.3`'s default step for that unit — 0.5 kg, or 1 lb.
    ///
    /// - Parameters:
    ///   - unit: The display unit.
    ///   - locale: The locale to render for.
    /// - Returns: The style.
    public static func weight(in unit: MassUnit, locale: Locale) -> WeightStyle {
        WeightStyle(unit: unit, precision: .default(for: unit), locale: locale)
    }

    /// A count — reps, sets, a plate multiplier.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func count(locale: Locale) -> IntegerFormatStyle<Int> {
        .number.locale(locale)
    }

    /// A proportion as a percentage, at most one decimal: `0.875` renders as `87.5%`, `0.9` as
    /// `90%`.
    ///
    /// The input is a proportion rather than a percentage — a training percentage of 87.5% is
    /// `0.875`, matching the domain, which carries it that way.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func percentage(locale: Locale) -> FloatingPointFormatStyle<Double>.Percent {
        .percent.precision(.fractionLength(0...1)).locale(locale)
    }

    /// A calendar date, without a time — the day a session happened.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func date(locale: Locale) -> Date.FormatStyle {
        .dateTime.year().month(.abbreviated).day().locale(locale)
    }

    /// A date with the time of day — when a set was logged.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func dateAndTime(locale: Locale) -> Date.FormatStyle {
        .dateTime.year().month(.abbreviated).day().hour().minute().locale(locale)
    }

    /// Names run together as one phrase — "Squat, Bench Press and Deadlift".
    ///
    /// **A rendered string rather than a style**, unlike everything above it: the conjunction and
    /// the separators are the locale's, and a screen joining names with a literal `", "` writes an
    /// English list into every language. It is the one case where the value being formatted is
    /// already text, so there is no `formatted(_:)` call site to hand a style to.
    ///
    /// - Parameters:
    ///   - names: The items, in the order they should read.
    ///   - locale: The locale to render for.
    /// - Returns: The joined phrase, empty when `names` is.
    public static func list(_ names: [String], locale: Locale) -> String {
        names.formatted(.list(type: .and).locale(locale))
    }
}
