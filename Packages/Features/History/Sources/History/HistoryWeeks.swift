import Foundation

/// One calendar week of the history, and the sessions logged in it (`FR-17.11.1`).
///
/// A value rather than a `Dictionary` grouping inside the view body, on this module's usual rule:
/// which rows fall under which heading is a unit test's question, and what the heading looks like is
/// a snapshot's.
///
/// **A calendar week, never a program week** (`FR-17.11.3`). A program week has no dates and, with
/// days in any order, can straddle two calendar weeks — it then appears in both, and each row says
/// its own position. There is one notion of week on this tab and the program's is a label on a row.
struct HistoryWeekSection: Identifiable, Equatable {
    /// The first instant of the week, in the calendar the section was built in — the heading's
    /// subject, and where the locale's own first weekday lands.
    let start: Date

    /// The week's last day, as a day start: the other end of the heading's range.
    let end: Date

    /// That week's rows, in the order they arrived: newest first.
    ///
    /// **One row per session rather than per day**, which is the honest reading of `FR-17.11.1`'s
    /// "one row per day trained": a day can hold two workouts (the grid's own doc comment says so),
    /// each with its own position and its own tonnage, and a row's tap opens
    /// ``AppNavigation/HistoryRoute/session(sessionID:)`` — which a merged row could not name.
    let summaries: [SessionSummary]

    /// The section's identity: its first row's.
    ///
    /// **Not ``start``, for ``SessionMonths/sections(_:calendar:)``'s reason** — this cuts *runs*
    /// rather than keying on the week, so a week reached twice is two sections, and two sections
    /// sharing an identity is a `ForEach` told the same row is in two places.
    let id: UUID

    /// Builds the section, taking its identity from the first row.
    ///
    /// - Parameters:
    ///   - start: The week's first instant.
    ///   - end: Its last day, as a day start.
    ///   - summaries: The week's rows, newest first and never empty — a run exists because a row
    ///     opened it, which is also what makes `FR-17.11.1`'s "a week with nothing logged is not
    ///     drawn" true without a filter anywhere.
    init(start: Date, end: Date, summaries: [SessionSummary]) {
        self.start = start
        self.end = end
        self.summaries = summaries
        self.id = summaries.first?.id ?? UUID()
    }
}

/// How the history's rows become `FR-17.11.1`'s calendar weeks.
enum HistoryWeeks {
    /// `summaries`, cut into one section per calendar week.
    ///
    /// **Consecutive runs, not a dictionary keyed on the week**, for ``SessionMonths``' reasons: the
    /// rows arrive newest first, a run of adjacent rows sharing a week *is* the section, and a week
    /// reached twice draws two headings rather than silently reordering the list.
    ///
    /// - Parameters:
    ///   - summaries: The rows, newest first.
    ///   - calendar: The calendar the week boundaries are taken in — **and the one the heading has
    ///     to be rendered against**, `AppFormat.resolved(_:in:)` saying why a boundary computed in
    ///     one calendar and drawn in another is a whole day out.
    /// - Returns: One section per run of rows sharing a week, in the order they arrived.
    static func sections(
        _ summaries: [SessionSummary], calendar: Calendar
    ) -> [HistoryWeekSection] {
        var sections: [HistoryWeekSection] = []
        var current: [SessionSummary] = []
        var currentStart: Date?
        for summary in summaries {
            let start = weekStart(of: summary.date, in: calendar)
            if start != currentStart, let currentStart {
                sections.append(section(from: currentStart, current, in: calendar))
                current = []
            }
            currentStart = start
            current.append(summary)
        }
        if let currentStart {
            sections.append(section(from: currentStart, current, in: calendar))
        }
        return sections
    }

    /// The first instant of `date`'s week, where the locale's own first weekday puts it.
    ///
    /// **The calendar's answer rather than arithmetic on a weekday number.** A week does not start
    /// on Sunday everywhere, and `dateInterval(of:for:)` is the one thing that knows where it does
    /// start — the same question ``MonthGrid`` asks of `firstWeekday` when it pads a first row.
    ///
    /// **The day is kept where the week cannot be resolved**, rather than dropped: a calendar that
    /// refused would otherwise collapse every such row into one section keyed on a date nobody
    /// logged. There is no such calendar in practice; this is the branch that stops one being
    /// possible.
    ///
    /// - Parameters:
    ///   - date: The training day.
    ///   - calendar: The calendar to take the week in.
    /// - Returns: The week's first instant.
    static func weekStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The last day of the week beginning at `start`, as a day start.
    ///
    /// Through the calendar rather than by adding six times 86,400 seconds — a week containing a
    /// daylight-saving transition is still seven days, and `startOfDay` is what turns whatever wall
    /// clock the addition lands on back into the day itself.
    ///
    /// - Parameters:
    ///   - start: The week's first instant.
    ///   - calendar: The calendar to move in.
    /// - Returns: The week's last day, or `start` if the calendar could not answer.
    static func weekEnd(of start: Date, in calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 6, to: start).map(calendar.startOfDay(for:)) ?? start
    }

    /// One section, with its far end resolved.
    private static func section(
        from start: Date, _ summaries: [SessionSummary], in calendar: Calendar
    ) -> HistoryWeekSection {
        HistoryWeekSection(
            start: start, end: weekEnd(of: start, in: calendar), summaries: summaries)
    }
}
