import Foundation
import PowerliftingCore
import Testing

@testable import Localization

/// `G-3.4`: every style renders for the locale it was handed, and for no other.
@Suite("Locale-explicit formatting")
struct AppFormatTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    /// The picker that offers a step has to draw the step itself, and it is a quantity of the
    /// display unit rather than a stored mass — 0.5 lb is not a whole number of grams.
    @Test("A display step renders as the mass it is, in the locale's own digits")
    func stepRendersAsAMass() {
        #expect(AppFormat.weightStep(.half, in: .kilograms, locale: english) == "0.5 kg")
        #expect(AppFormat.weightStep(.half, in: .pounds, locale: english) == "0.5 lb")
        #expect(AppFormat.weightStep(.quarter, in: .kilograms, locale: english) == "0.25 kg")
        #expect(AppFormat.weightStep(.whole, in: .kilograms, locale: english) == "1 kg")
        #expect(AppFormat.weightStep(.half, in: .kilograms, locale: german) == "0,5 kg")
    }

    /// The pairing renders the same as its two halves passed separately — one style, two ways in.
    @Test("A weight display is the unit and the step it carries")
    func displayPairingRendersLikeItsHalves() {
        let weight = Weight(grams: 102_500)
        #expect(
            weight.formatted(
                AppFormat.weight(
                    WeightDisplay(unit: .kilograms, precision: .quarter), locale: english))
                == weight.formatted(
                    AppFormat.weight(in: .kilograms, precision: .quarter, locale: english)))
        #expect(
            weight.formatted(
                AppFormat.weight(WeightDisplay(unit: .pounds, resolving: nil), locale: english))
                == weight.formatted(AppFormat.weight(in: .pounds, locale: english)))
    }

    @Test("A weight carries the locale's decimal separator")
    func weightSeparatorFollowsLocale() {
        let weight = Weight(grams: 102_500)
        #expect(weight.formatted(AppFormat.weight(in: .kilograms, locale: english)) == "102.5 kg")
        #expect(weight.formatted(AppFormat.weight(in: .kilograms, locale: german)) == "102,5 kg")
    }

    @Test("The unit symbol is the abbreviated one, in both units")
    func unitSymbolIsAbbreviated() {
        let weight = Weight(grams: 102_058)
        #expect(weight.formatted(AppFormat.weight(in: .pounds, locale: english)) == "225 lb")
        #expect(weight.formatted(AppFormat.weight(in: .kilograms, locale: english)) == "102.0 kg")
    }

    @Test("The fraction width comes from the step, not from the value")
    func fractionWidthFollowsPrecision() {
        let weight = Weight(grams: 100_000)
        #expect(
            weight.formatted(AppFormat.weight(in: .kilograms, precision: .whole, locale: english))
                == "100 kg")
        #expect(
            weight.formatted(AppFormat.weight(in: .kilograms, precision: .half, locale: english))
                == "100.0 kg")
        #expect(
            weight.formatted(AppFormat.weight(in: .kilograms, precision: .quarter, locale: english))
                == "100.00 kg")
    }

    @Test("A negative mass — assisted work — keeps its sign")
    func negativeMassRenders() {
        let assisted = Weight(grams: -20_000)
        #expect(assisted.formatted(AppFormat.weight(in: .kilograms, locale: english)) == "-20.0 kg")
    }

    @Test("The rendered digits are the domain's own, never re-rounded here")
    func digitsAgreeWithTheDomain() {
        // The pound path is the one that can disagree: it rounds grams to milli-pounds and then to
        // the step, so a style rounding the converted Double instead would drift at the ties.
        for grams in stride(from: -5_000, through: 205_000, by: 227) {
            let weight = Weight(grams: grams)
            for unit in MassUnit.allCases {
                let precision = DisplayPrecision.default(for: unit)
                let rendered = weight.formatted(
                    AppFormat.weight(in: unit, precision: precision, locale: english))
                let domain = weight.formatted(in: unit, precision: precision)
                #expect(rendered.hasPrefix(domain + " "), "\(grams) g in \(unit)")
            }
        }
    }

    @Test("A percentage shows at most one decimal and drops a trailing zero")
    func percentageDropsTrailingZero() {
        #expect((0.875).formatted(AppFormat.percentage(locale: english)) == "87.5%")
        #expect((0.9).formatted(AppFormat.percentage(locale: english)) == "90%")
        // A no-break space, which is what de_DE puts in front of the sign — not a plain space.
        #expect((0.875).formatted(AppFormat.percentage(locale: german)) == "87,5\u{00A0}%")
    }

    @Test("A count is grouped the way the locale groups")
    func countFollowsLocale() {
        #expect((1_250).formatted(AppFormat.count(locale: english)) == "1,250")
        #expect((1_250).formatted(AppFormat.count(locale: german)) == "1.250")
    }

    @Test("A date is ordered the way the locale orders it")
    func dateFollowsLocale() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let calendar = TimeZone(identifier: "UTC") ?? .gmt
        var englishStyle = AppFormat.date(locale: english)
        englishStyle.timeZone = calendar
        var germanStyle = AppFormat.date(locale: german)
        germanStyle.timeZone = calendar
        #expect(moment.formatted(englishStyle) == "Nov 14, 2023")
        #expect(moment.formatted(germanStyle) == "14. Nov. 2023")
    }

    @Test("The time-of-day style adds a time and keeps the date")
    func dateAndTimeAddsTheTime() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var style = AppFormat.dateAndTime(locale: english)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        // A narrow no-break space before the day period, again ICU's rather than a space.
        #expect(moment.formatted(style) == "Nov 14, 2023 at 10:13\u{202F}PM")
    }

    @Test("The calendar's heading names the month in full, in the locale's own order")
    func monthIsSpelledOut() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var englishStyle = AppFormat.month(locale: english)
        englishStyle.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var germanStyle = AppFormat.month(locale: german)
        germanStyle.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        // Spelled out rather than abbreviated: it is a heading with a line to itself.
        #expect(moment.formatted(englishStyle) == "November 2023")
        #expect(moment.formatted(germanStyle) == "November 2023")
        #expect(moment.formatted(englishStyle) != moment.formatted(AppFormat.date(locale: english)))
    }

    @Test("A grid cell is the day's number alone, and the digits are the locale's")
    func dayOfMonthIsTheNumberAlone() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var style = AppFormat.dayOfMonth(locale: english)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        #expect(moment.formatted(style) == "14")
        // The reason this is a style rather than `String(day)`: a locale with its own numerals
        // writes them, and an interpolated `Int` never would.
        var arabic = AppFormat.dayOfMonth(locale: Locale(identifier: "ar_EG"))
        arabic.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        #expect(moment.formatted(arabic) == "\u{0661}\u{0664}")
    }

    @Test("The spoken form of a date names its weekday, which the cell cannot show")
    func fullDateNamesTheWeekday() {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        var style = AppFormat.fullDate(locale: english)
        style.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        #expect(moment.formatted(style) == "Tuesday, November 14, 2023")
    }

    @Test("Weekday headings start on the calendar's own first weekday")
    func weekdayInitialsFollowTheCalendar() {
        var sundayFirst = Calendar(identifier: .gregorian)
        sundayFirst.firstWeekday = 1
        var mondayFirst = sundayFirst
        mondayFirst.firstWeekday = 2

        // The rotation is what this exists for: the same seven symbols, in two different orders.
        #expect(
            AppFormat.weekdayInitials(in: sundayFirst, locale: english)
                == ["S", "M", "T", "W", "T", "F", "S"])
        #expect(
            AppFormat.weekdayInitials(in: mondayFirst, locale: english)
                == ["M", "T", "W", "T", "F", "S", "S"])
    }

    @Test("Weekday headings are the locale's letters, not the calendar's own locale")
    func weekdayInitialsFollowTheLocale() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        // Deliberately disagreeing with the locale passed in: the view's locale wins, because the
        // calendar's is the running machine's.
        calendar.locale = english

        #expect(AppFormat.weekdayInitials(in: calendar, locale: german) == ["M", "D", "M", "D", "F", "S", "S"])
        #expect(AppFormat.weekdayInitials(in: calendar, locale: english).count == 7)
    }

    @Test("A style bound to a calendar renders in that calendar's time zone, not the device's")
    func resolvedBindsTheTimeZone() {
        // Midnight UTC on New Year's Day 2026. One hour west it is still New Year's Eve — a
        // different day, month and year, which is the whole of why this exists.
        let midnight = Date(timeIntervalSince1970: 1_767_225_600)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var west = utc
        west.timeZone = TimeZone(secondsFromGMT: -3_600) ?? .gmt

        let style = AppFormat.dayOfMonth(locale: english)
        #expect(midnight.formatted(AppFormat.resolved(style, in: utc)) == "1")
        #expect(midnight.formatted(AppFormat.resolved(style, in: west)) == "31")
        #expect(
            midnight.formatted(AppFormat.resolved(AppFormat.month(locale: english), in: west))
                == "December 2025")
    }

    @Test("A list of names is joined the way the locale joins one")
    func listJoinsWithTheLocalesConjunction() {
        // The reason this exists rather than `joined(separator: ", ")`: the conjunction and the
        // separators are the locale's, and a literal writes English into every language.
        #expect(
            AppFormat.list(["Squat", "Bench Press", "Deadlift"], locale: english)
                == "Squat, Bench Press, and Deadlift")
        #expect(AppFormat.list(["Squat", "Bench Press"], locale: english) == "Squat and Bench Press")
    }

    @Test("A list rebound to another locale uses that locale's conjunction")
    func listFollowsTheLocale() {
        let names = ["Squat", "Bench Press"]
        #expect(AppFormat.list(names, locale: german) == "Squat und Bench Press")
        #expect(AppFormat.list(names, locale: english) != AppFormat.list(names, locale: german))
    }

    @Test("Nothing renders as nothing, which is what a caller branches on")
    func listOfNothingIsEmpty() {
        // `SessionSummaryCard` shows its own copy instead of an empty phrase, so this is a contract
        // rather than an incidental.
        #expect(AppFormat.list([], locale: english).isEmpty)
        #expect(AppFormat.list(["Squat"], locale: english) == "Squat")
    }

    @Test("A style rebound to another locale renders as that one")
    func styleRebinds() {
        let weight = Weight(grams: 102_500)
        let rebound = AppFormat.weight(in: .kilograms, locale: english).locale(german)
        #expect(weight.formatted(rebound) == "102,5 kg")
    }
}
