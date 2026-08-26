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

    /// The month and year a calendar grid is showing — "August 2026".
    ///
    /// The month is spelled out rather than abbreviated: it is a screen title with a whole line to
    /// itself, not a cell in a list.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func month(locale: Locale) -> Date.FormatStyle {
        .dateTime.year().month(.wide).locale(locale)
    }

    /// One cell of a calendar grid — the day's number alone, without its month.
    ///
    /// A numeral rather than a `String(day)`, because the digits are the locale's: a calendar shown
    /// in `ar` writes `٢٦` where one shown in `en` writes `26`.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func dayOfMonth(locale: Locale) -> Date.FormatStyle {
        .dateTime.day().locale(locale)
    }

    /// A date named in full, weekday included — what VoiceOver reads for a calendar cell whose
    /// visible content is one or two digits (`G-4.2`).
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: The style.
    public static func fullDate(locale: Locale) -> Date.FormatStyle {
        .dateTime.weekday(.wide).year().month(.wide).day().locale(locale)
    }

    /// `style`, resolved in `calendar` rather than in the device's own.
    ///
    /// **A `Date.FormatStyle` renders against `Calendar.autoupdatingCurrent` and the device's time
    /// zone whatever else is around it**, including a SwiftUI `@Environment(\.calendar)`. Anywhere
    /// the dates being rendered were *computed* in some other calendar, the two disagree — and the
    /// disagreement is a whole day, not a formatting nicety: a grid laid out in UTC, drawn on a
    /// machine an hour west, labels every cell with the previous day and its first cell with the
    /// last day of the month before.
    ///
    /// So a screen that owns a calendar binds its styles to it. A screen that does not — one simply
    /// rendering a stored instant — wants the device's own and should not call this.
    ///
    /// - Parameters:
    ///   - style: The style to bind.
    ///   - calendar: The calendar and time zone to render in.
    /// - Returns: The style, bound.
    public static func resolved(
        _ style: Date.FormatStyle, in calendar: Calendar
    ) -> Date.FormatStyle {
        var bound = style
        bound.calendar = calendar
        bound.timeZone = calendar.timeZone
        return bound
    }

    /// A calendar grid's seven column headings, starting on `calendar`'s own first weekday.
    ///
    /// **Rendered strings rather than a style**, for ``list(_:locale:)``'s reason: there is no value
    /// to hand a style to. Both halves are the locale's and neither is this app's to choose — a
    /// grid that hard-coded a Sunday-first `["S", "M", …]` would be wrong in most of the world twice
    /// over, in its order and in its letters.
    ///
    /// They are **very short** — one or two characters — which makes some of them ambiguous in
    /// English (two `T`s, two `S`s). That is what the column of a calendar grid has room for, and it
    /// is why the headings are decoration a screen hides from VoiceOver rather than labels: a cell
    /// names its own weekday in full through ``fullDate(locale:)``.
    ///
    /// - Parameters:
    ///   - calendar: The calendar whose week order and symbols to use.
    ///   - locale: The locale to render the symbols for. Overrides whatever locale `calendar`
    ///     carries, which is the running machine's rather than the view's.
    /// - Returns: Seven headings, in the order the grid's columns are drawn.
    public static func weekdayInitials(in calendar: Calendar, locale: Locale) -> [String] {
        var localized = calendar
        localized.locale = locale
        let symbols = localized.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        // `firstWeekday` is 1-based over `symbols`, which is Sunday-first: rotating by it is what
        // turns a Sunday-first list into the calendar's own week.
        let offset = localized.firstWeekday - 1
        return (0..<7).map { symbols[(offset + $0) % 7] }
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
