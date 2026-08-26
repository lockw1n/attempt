import Foundation
import PowerliftingCore
import Testing

@testable import Localization

/// `G-3.4`: every style renders for the locale it was handed, and for no other.
@Suite("Locale-explicit formatting")
struct AppFormatTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

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
