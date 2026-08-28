import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.8.3`'s rolling average, and the gap rule this task had to decide: the window is seven
/// **days** and the average is over the readings that fall in it, however few or many those are.
@Suite("Bodyweight rolling average")
struct BodyweightAverageTests {
    /// A log with deliberately irregular spacing — 1 Feb, 3 Feb, 4 Feb, 9 Feb, 14 Feb — so no
    /// window holds seven readings and two windows hold different counts.
    private static let log = [
        entry(day: 1, kilos: 80),
        entry(day: 3, kilos: 81),
        entry(day: 4, kilos: 82),
        entry(day: 9, kilos: 84),
        entry(day: 14, kilos: 86),
    ]

    @Test("The window averages the readings there are, not seven days' worth")
    func averageOverAvailableReadings() {
        // 4 Feb's window is 29 Jan…4 Feb, holding 1, 3 and 4 Feb: (80 + 81 + 82) / 3 = 81 kg.
        let average = BodyweightAverage.rolling(
            endingOn: day(4), over: Self.log, calendar: .gmt)

        #expect(average == Weight(grams: 81_000))
    }

    @Test("A window that reaches back past a gap picks up only what is inside it")
    func averageExcludesReadingsOutsideTheWindow() {
        // 9 Feb's window is 3 Feb…9 Feb: 81, 82 and 84 — 1 Feb is a day too early.
        // (81 + 82 + 84) / 3 = 82.333… kg, which rounds to 82 333 g.
        let average = BodyweightAverage.rolling(
            endingOn: day(9), over: Self.log, calendar: .gmt)

        #expect(average == Weight(grams: 82_333))
    }

    @Test("The seventh day back is inside the window and the eighth is not")
    func windowBoundaryIsSevenDaysInclusive() {
        let pair = [entry(day: 1, kilos: 80), entry(day: 7, kilos: 90)]
        let justOutside = [entry(day: 1, kilos: 80), entry(day: 8, kilos: 90)]

        #expect(
            BodyweightAverage.rolling(endingOn: day(7), over: pair, calendar: .gmt)
                == Weight(grams: 85_000))
        // One day further out, the older reading falls outside: the window then holds a single
        // reading and is refused rather than averaged — where a window one day wider would have
        // answered 85 kg.
        #expect(
            BodyweightAverage.rolling(endingOn: day(8), over: justOutside, calendar: .gmt) == nil)
    }

    @Test("One reading in the window is refused rather than averaged with itself")
    func singleReadingIsInsufficient() {
        // 1 Feb is the first reading there is, so its own window holds nothing else.
        #expect(BodyweightAverage.rolling(endingOn: day(1), over: Self.log, calendar: .gmt) == nil)
        #expect(
            BodyweightAverage.rolling(
                endingOn: day(9), over: [entry(day: 9, kilos: 84)], calendar: .gmt) == nil)
    }

    @Test("An empty window is refused, not zero")
    func emptyWindowIsRefused() {
        #expect(BodyweightAverage.rolling(endingOn: day(30), over: Self.log, calendar: .gmt) == nil)
    }

    @Test("Two readings on one day both count — the window is days, the average is readings")
    func sameDayReadingsBothCount() {
        let twice = [
            entry(day: 5, kilos: 80, hour: 7),
            entry(day: 5, kilos: 82, hour: 20),
        ]

        #expect(
            BodyweightAverage.rolling(endingOn: day(5), over: twice, calendar: .gmt)
                == Weight(grams: 81_000))
    }

    @Test("A reading later in its closing day is still inside the window")
    func closingDayIncludesTheWholeDay() {
        let pair = [entry(day: 1, kilos: 80), entry(day: 4, kilos: 84, hour: 23)]

        #expect(
            BodyweightAverage.rolling(endingOn: day(4), over: pair, calendar: .gmt)
                == Weight(grams: 82_000))
    }

    @Test("Rows come back newest first, each carrying its own window")
    func readingsAreReverseChronological() {
        let readings = BodyweightAverage.readings(from: Self.log, calendar: .gmt)

        #expect(readings.map(\.date) == [day(14), day(9), day(4), day(3), day(1)])
        #expect(readings.map(\.weight.grams) == [86_000, 84_000, 82_000, 81_000, 80_000])
        // Each row's own window, and the oldest has none: nothing was weighed before it. 14 Feb
        // reaches back to the 9th and averages the two; the 9th reaches past the gap to the 3rd.
        #expect(
            readings.map(\.average) == [
                Weight(grams: 85_000),
                Weight(grams: 82_333),
                Weight(grams: 81_000),
                Weight(grams: 80_500),
                nil,
            ])
    }

    @Test("Rows keep their own windows when one day holds more than one reading")
    func readingsWithSameDayEntries() {
        // The walk that builds these rows carries one pair of indices across the log, and a second
        // reading on a row's own day sits *after* it — so this is the case where the window's far
        // end has to reach forward rather than only back.
        let log = [
            entry(day: 1, kilos: 80),
            entry(day: 4, kilos: 82, hour: 7),
            entry(day: 4, kilos: 84, hour: 20),
            entry(day: 12, kilos: 90),
        ]

        let readings = BodyweightAverage.readings(from: log, calendar: .gmt)

        #expect(readings.map(\.weight.grams) == [90_000, 84_000, 82_000, 80_000])
        // Both 4 Feb rows see one window — 29 Jan…4 Feb, holding all three earlier readings,
        // the morning row included by the evening one: (80 + 82 + 84) / 3 = 82 kg. 12 Feb reaches
        // back only to the 6th and finds nothing but itself.
        #expect(
            readings.map(\.average) == [nil, Weight(grams: 82_000), Weight(grams: 82_000), nil])
    }

    @Test("Two readings stamped at the same instant come back in a stable order")
    func identicalInstantsAreOrderedOnTheIdentifier() {
        // Handed over in the order the tie-break has to *undo* — the larger identifier first — so
        // a sort that only compared dates would leave them where they came in and be caught here.
        let pair = [
            entry(day: 4, kilos: 84, slot: 2),
            entry(day: 4, kilos: 82, slot: 1),
        ]

        let readings = BodyweightAverage.readings(from: pair, calendar: .gmt)

        #expect(readings.map(\.id) == [pair[0].id, pair[1].id])
        #expect(readings.map(\.weight.grams) == [84_000, 82_000])
    }

    @Test("An empty log has no rows and no average")
    func emptyLog() {
        #expect(BodyweightAverage.readings(from: [BodyweightEntry](), calendar: .gmt).isEmpty)
        #expect(
            BodyweightAverage.rolling(endingOn: day(1), over: [BodyweightEntry](), calendar: .gmt)
                == nil)
    }

    @Test("A mean that cannot be summed is refused rather than computed from what fitted")
    func overflowRefuses() {
        let absurd = [
            entry(day: 1, grams: Int.max),
            entry(day: 2, grams: Int.max),
        ]

        #expect(BodyweightAverage.rolling(endingOn: day(2), over: absurd, calendar: .gmt) == nil)
    }

    @Test("A half gram rounds away from zero rather than toward it")
    func meanRoundsHalvesAwayFromZero() {
        let pair = [entry(day: 1, grams: 80_000), entry(day: 2, grams: 80_001)]

        #expect(
            BodyweightAverage.rolling(endingOn: day(2), over: pair, calendar: .gmt)
                == Weight(grams: 80_001))
    }
}

/// A reading dated `day` February 2024 in GMT, at `hour`.
///
/// - Parameter slot: Separates two readings stamped at the same instant, which differ only by
///   identifier — the one thing the row order falls back on.
private func entry(day: Int, kilos: Double, hour: Int = 8, slot: Int = 0) -> BodyweightEntry {
    entry(day: day, grams: Int(kilos * 1000), hour: hour, slot: slot)
}

/// The same, in grams.
private func entry(day: Int, grams: Int, hour: Int = 8, slot: Int = 0) -> BodyweightEntry {
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    return BodyweightEntry(
        // The hour and the slot are in the identifier as well as the day: two readings on one day
        // are ordinary, and rows are ordered on the identifier where their dates tie.
        id: UUID(
            uuidString: "B0DE0000-0000-4000-8000-000000"
                + String(format: "%02d%02d%02d", day, hour, slot))
            ?? UUID(),
        createdAt: stamp,
        updatedAt: stamp,
        deletedAt: nil,
        date: date(day: day, hour: hour),
        weight: Weight(grams: grams),
        source: .manual
    )
}

/// Midnight-based instants in a fixed month, so no test depends on the day it runs.
private func day(_ day: Int) -> Date { date(day: day, hour: 8) }

private func date(day: Int, hour: Int) -> Date {
    var components = DateComponents()
    components.year = 2024
    components.month = 2
    components.day = day
    components.hour = hour
    return Calendar.gmt.date(from: components) ?? .distantPast
}

extension Calendar {
    /// A calendar with no time zone of its own to drift with — every date in these tests is GMT.
    static var gmt: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
