import Foundation

/// One month laid out as the rows of a calendar grid (`FR-1.5.3`).
///
/// **A value type over `Calendar`, and every date question is asked of the calendar rather than of
/// arithmetic.** A month is not 30 days, a week does not start on Sunday everywhere, and a day is
/// not 86,400 seconds across a daylight-saving transition — all three are wrong often enough to
/// reach a user, and all three are what `Calendar` is for. Nothing here adds an interval to a date.
///
/// **A cell is a day of this month or it is nothing.** The leading and trailing cells that pad the
/// first and last weeks are `nil` rather than the neighbouring months' days: a marker drawn on a
/// day belonging to another month says a training day is in the month on screen when it is not, and
/// the grid has no way to say otherwise without colour (`G-4.5`).
struct MonthGrid: Equatable, Sendable {
    /// The first instant of the month drawn — a day start, in the calendar this was built with.
    let month: Date

    /// The grid's rows: seven cells each, a day start or padding.
    ///
    /// Four to six rows, which is every shape a month takes. Empty only if the calendar could not
    /// answer how long the month is, which no calendar this app can be handed does.
    let weeks: [[Date?]]

    /// Lays out whichever month contains `date`.
    ///
    /// - Parameters:
    ///   - date: Any instant in the month to draw.
    ///   - calendar: The calendar deciding where the month and the week begin.
    init(containing date: Date, in calendar: Calendar) {
        let start =
            calendar.dateInterval(of: .month, for: date)?.start
            ?? calendar.startOfDay(for: date)
        month = start

        let days = (0..<(calendar.range(of: .day, in: .month, for: start)?.count ?? 0))
            .compactMap { offset in
                // Through the calendar rather than by adding 86,400 seconds — a day that loses or
                // gains an hour is still one day, and `startOfDay` is what turns whatever wall
                // clock the addition lands on back into the day itself.
                calendar.date(byAdding: .day, value: offset, to: start)
                    .map(calendar.startOfDay(for:))
            }

        // `weekday` is 1-based and Sunday-first; `firstWeekday` is in the same space. Their
        // difference is how many cells stand before the first of the month, in the calendar's own
        // week rather than in an assumed one.
        let weekday = calendar.component(.weekday, from: start)
        let leading = ((weekday - calendar.firstWeekday) % 7 + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading) + (days as [Date?])
        if !cells.isEmpty {
            cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        }
        // The slice is clamped rather than trusted to land on a multiple of seven. It always does,
        // the padding above being what makes it so — but the length of a month is a calendar's
        // answer, and a slice that traps is not what should happen if one ever gives an odd one.
        weeks = stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }

    /// The start of the month `months` away from this one.
    ///
    /// - Parameters:
    ///   - months: How far to move. Negative is earlier.
    ///   - calendar: The calendar to move in.
    /// - Returns: That month's first instant, or this one's if the calendar could not answer.
    func month(offsetBy months: Int, in calendar: Calendar) -> Date {
        calendar.date(byAdding: .month, value: months, to: month) ?? month
    }
}
