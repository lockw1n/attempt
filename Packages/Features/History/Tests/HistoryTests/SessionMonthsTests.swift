import Foundation
import PowerliftingCore
import Testing

@testable import History

/// `FR-16.6.3`'s month headings: which rows fall under which one, and in what order.
@Suite("Session list month sections")
struct SessionMonthsTests {
    @Test("Two months are two sections, newest first, each keeping its own rows in order")
    func twoMonths() {
        let sections = SessionMonths.sections(
            [
                summary(0, "2026-09-14"),
                summary(1, "2026-09-02"),
                summary(2, "2026-08-30"),
            ],
            calendar: Self.calendar
        )
        #expect(sections.count == 2)
        #expect(sections.first?.summaries.map(\.id) == [Self.identifier(0), Self.identifier(1)])
        #expect(sections.last?.summaries.map(\.id) == [Self.identifier(2)])
        #expect(sections.first?.start == Self.instant("2026-09-01"))
        #expect(sections.last?.start == Self.instant("2026-08-01"))
    }

    @Test("A log inside one month is one section, not one per row")
    func oneMonth() {
        let sections = SessionMonths.sections(
            [summary(0, "2026-09-14"), summary(1, "2026-09-02")], calendar: Self.calendar)
        #expect(sections.count == 1)
        #expect(sections.first?.summaries.count == 2)
    }

    @Test("No rows are no sections — not one empty one")
    func noRows() {
        // The empty state is the screen's (`FR-1.13.2`), and a heading over nothing would be a month
        // the user is told they trained in.
        #expect(SessionMonths.sections([], calendar: Self.calendar).isEmpty)
    }

    @Test("The last row's month is not dropped")
    func lastMonthIsFlushed() {
        // The loop closes a section when the month changes, so the final one is closed by the code
        // after it and by nothing else. Perturbing that line has to fail something.
        let sections = SessionMonths.sections([summary(0, "2026-09-14")], calendar: Self.calendar)
        #expect(sections.count == 1)
        #expect(sections.first?.summaries.count == 1)
    }

    @Test("A month reached twice is two sections, rather than the list being reordered around it")
    func aRepeatedMonthIsNotMerged() {
        // Runs, not a dictionary. The rows arrive newest first, so this shape cannot occur — and if
        // it ever does, two headings in the wrong place is a visible fault, where merging them would
        // silently move a row out of the order the list was paged in.
        let sections = SessionMonths.sections(
            [summary(0, "2026-09-14"), summary(1, "2026-08-30"), summary(2, "2026-09-02")],
            calendar: Self.calendar
        )
        #expect(sections.count == 3)
        // And three sections a `ForEach` can tell apart. Keying identity on the month would give
        // the two September runs the same one, which is not "two headings in the wrong place" —
        // it is a `ForEach` told one row is in two places, which draws undefined results.
        #expect(Set(sections.map(\.id)).count == 3)
    }

    @Test("The month boundary is the caller's calendar, not the machine's")
    func theCalendarDecidesTheBoundary() {
        // The first instant of September in Kyiv is still August in UTC, which is the whole reason
        // `SessionMonths` takes a calendar rather than reading `Calendar.current`: a section cut in
        // one and a heading drawn in another disagree by a month, not by a formatting nicety.
        let row = [dated(Self.instant("2026-09-01", zone: "Europe/Kyiv"))]
        let utc = SessionMonths.sections(row, calendar: Self.calendar)
        let kyiv = SessionMonths.sections(row, calendar: Self.calendar(in: "Europe/Kyiv"))

        #expect(utc.first?.start == Self.instant("2026-08-01"))
        #expect(kyiv.first?.start == Self.instant("2026-09-01", zone: "Europe/Kyiv"))
        #expect(utc.first?.start != kyiv.first?.start)
    }

    /// One row at an exact instant, for the boundary case above.
    ///
    /// - Parameter instant: The training day.
    /// - Returns: The row.
    private func dated(_ instant: Date) -> SessionSummary {
        SessionSummary(
            id: Self.identifier(0),
            date: instant,
            exerciseNames: [],
            setCount: 0,
            tonnage: .zero,
            notes: ""
        )
    }

    /// One row, dated on `day`.
    ///
    /// - Parameters:
    ///   - index: Which row — its identity, so an assertion can name it.
    ///   - day: The training day, `yyyy-MM-dd` in UTC.
    /// - Returns: The row.
    private func summary(_ index: Int, _ day: String) -> SessionSummary {
        SessionSummary(
            id: Self.identifier(index),
            date: Self.instant(day),
            exerciseNames: ["Back Squat"],
            setCount: 3,
            tonnage: Weight(grams: 300_000),
            notes: ""
        )
    }

    /// The calendar every case above is cut in unless it says otherwise.
    private static let calendar = calendar(in: "UTC")

    /// A Gregorian calendar in one zone.
    ///
    /// - Parameter zone: The time zone identifier.
    /// - Returns: The calendar.
    private static func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// Midnight on a day, in a zone.
    ///
    /// - Parameters:
    ///   - day: `yyyy-MM-dd`.
    ///   - zone: The time zone identifier.
    /// - Returns: The instant.
    private static func instant(_ day: String, zone: String = "UTC") -> Date {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return DateComponents(
            calendar: calendar(in: zone),
            timeZone: TimeZone(identifier: zone) ?? .gmt,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ).date ?? .distantPast
    }

    /// A stable identifier for a row.
    ///
    /// - Parameter index: Which row.
    /// - Returns: The identifier.
    private static func identifier(_ index: Int) -> UUID {
        UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index))") ?? UUID()
    }
}
