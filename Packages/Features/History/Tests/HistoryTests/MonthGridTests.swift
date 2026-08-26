import Foundation
import Testing

@testable import History

/// The month grid's layout (`FR-1.5.3`) — where a month begins in its first week, how many rows it
/// takes, and that padding is never another month's day.
///
/// Every case pins its calendar. The running machine decides the time zone and the first weekday,
/// so a grid asserted against `Calendar.current` asserts whatever that machine happens to be.
@Suite("Month grid")
struct MonthGridTests {
    @Test("The month's own days are exactly the non-padding cells, in order")
    func daysAreTheMonthsOwn() {
        let calendar = TrainingLog.utc
        let grid = MonthGrid(containing: TrainingLog.day(2026, 1, 15), in: calendar)

        let days = grid.weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(days.first == TrainingLog.day(2026, 1, 1))
        #expect(days.last == TrainingLog.day(2026, 1, 31))
        #expect(days == days.sorted())
        // Every cell is a day start, which is what the training-day index is keyed on.
        #expect(days.allSatisfy { $0 == calendar.startOfDay(for: $0) })
    }

    @Test("Every row is seven cells, and the grid is whole weeks")
    func rowsAreWeeks() {
        for month in 1...12 {
            let grid = MonthGrid(containing: TrainingLog.day(2026, month, 1), in: TrainingLog.utc)
            #expect(grid.weeks.allSatisfy { $0.count == 7 }, "month \(month)")
            #expect((4...6).contains(grid.weeks.count), "month \(month)")
        }
    }

    @Test("The first of the month sits under its own weekday column")
    func leadingPaddingPlacesTheFirst() throws {
        // 1 January 2026 is a Thursday: on a Sunday-first week that is the fifth column, so four
        // cells stand before it.
        let grid = MonthGrid(containing: TrainingLog.day(2026, 1, 1), in: TrainingLog.utc)
        let first = try #require(grid.weeks.first)
        #expect(first.prefix(4).allSatisfy { $0 == nil })
        #expect(first[4] == TrainingLog.day(2026, 1, 1))
    }

    @Test("A calendar whose week starts on Monday shifts the same month one column left")
    func firstWeekdayIsTheCalendars() throws {
        var monday = TrainingLog.utc
        monday.firstWeekday = 2
        let grid = MonthGrid(containing: TrainingLog.day(2026, 1, 1), in: monday)

        // Thursday is the fourth column of a Monday-first week rather than the fifth.
        let first = try #require(grid.weeks.first)
        #expect(first.prefix(3).allSatisfy { $0 == nil })
        #expect(first[3] == TrainingLog.day(2026, 1, 1))
    }

    @Test("Padding is never a neighbouring month's day")
    func paddingIsEmptyRatherThanBorrowed() {
        let calendar = TrainingLog.utc
        let grid = MonthGrid(containing: TrainingLog.day(2025, 12, 1), in: calendar)

        for cell in grid.weeks.flatMap({ $0 }) {
            guard let cell else { continue }
            #expect(calendar.component(.month, from: cell) == 12)
            #expect(calendar.component(.year, from: cell) == 2025)
        }
    }

    @Test("Stepping back from January lands on the previous December")
    func steppingCrossesTheYear() {
        let calendar = TrainingLog.utc
        let january = MonthGrid(containing: TrainingLog.day(2026, 1, 20), in: calendar)

        #expect(january.month == TrainingLog.day(2026, 1, 1))
        #expect(january.month(offsetBy: -1, in: calendar) == TrainingLog.day(2025, 12, 1))
        #expect(january.month(offsetBy: 1, in: calendar) == TrainingLog.day(2026, 2, 1))
        #expect(january.month(offsetBy: -13, in: calendar) == TrainingLog.day(2024, 12, 1))
    }

    @Test("A February of twenty-nine days is twenty-nine days")
    func leapYear() {
        let days = MonthGrid(containing: TrainingLog.day(2024, 2, 10), in: TrainingLog.utc)
            .weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 29)
        #expect(days.last == TrainingLog.day(2024, 2, 29))
    }

    @Test("A day that loses an hour is still one cell, and still a day start")
    func daylightSavingDoesNotShiftTheGrid() {
        // Europe/London springs forward at 01:00 on 29 March 2026: that day has 23 hours, so a grid
        // built by adding 86,400 seconds would put 30 March in 29 March's cell from there on.
        var london = TrainingLog.utc
        london.timeZone = TimeZone(identifier: "Europe/London") ?? .gmt
        let grid = MonthGrid(containing: TrainingLog.day(2026, 3, 10, in: london), in: london)

        let days = grid.weeks.flatMap { $0 }.compactMap { $0 }
        #expect(days.count == 31)
        #expect(days.allSatisfy { $0 == london.startOfDay(for: $0) })
        #expect(Set(days.map { london.component(.day, from: $0) }) == Set(1...31))
    }
}
