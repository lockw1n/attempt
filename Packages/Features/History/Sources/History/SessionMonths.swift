import Foundation

/// One month of the session list, and the rows logged in it (`FR-16.6.3`).
///
/// A value rather than a `Dictionary` grouping inside the view body, on this module's usual rule:
/// which rows fall under which heading is a unit test's question, and what the heading looks like is
/// a snapshot's.
struct SessionMonthSection: Identifiable, Equatable {
    /// The first instant of the month, in the calendar the section was built in — the heading's
    /// subject.
    let start: Date

    /// That month's rows, in the order they arrived: newest first.
    let summaries: [SessionSummary]

    /// The section's identity: its first row's.
    ///
    /// **Not ``start``, and ``SessionMonths/sections(_:calendar:)``'s own argument is why.** That
    /// function cuts *runs* rather than keying on the month, so a month reached twice is two
    /// sections — and two sections sharing an identity is not a `ForEach` drawing two headings, it
    /// is a `ForEach` told the same row is in two places, which draws undefined results and says so
    /// in the console. A session appears in exactly one run, so its identifier separates them.
    let id: UUID

    /// Builds the section, taking its identity from the first row.
    ///
    /// - Parameters:
    ///   - start: The month's first instant.
    ///   - summaries: The month's rows, newest first and never empty — a run exists because a row
    ///     opened it.
    init(start: Date, summaries: [SessionSummary]) {
        self.start = start
        self.summaries = summaries
        self.id = summaries.first?.id ?? UUID()
    }
}

/// How the session list's rows become `FR-16.6.3`'s month sections.
enum SessionMonths {
    /// `summaries`, cut into one section per month.
    ///
    /// **Consecutive runs, not a dictionary keyed on the month.** The rows arrive newest first —
    /// which is what `WorkoutRepository` guarantees and what the paging depends on — so a run of
    /// adjacent rows sharing a month *is* the section, and grouping this way keeps the list's own
    /// order without re-sorting it. It also fails visibly rather than silently if that order is ever
    /// broken: a month reached twice draws two headings, where a dictionary would quietly reorder
    /// the whole list around whichever key sorted first.
    ///
    /// **The calendar is the caller's**, and it has to be the same one the heading is rendered
    /// against — `AppFormat.resolved(_:in:)` says why a month boundary computed in one calendar and
    /// drawn in another is a whole day out rather than a formatting nicety.
    ///
    /// - Parameters:
    ///   - summaries: The rows, newest first.
    ///   - calendar: The calendar the month boundaries are taken in.
    /// - Returns: One section per run of rows sharing a month, in the order they arrived.
    static func sections(
        _ summaries: [SessionSummary], calendar: Calendar
    ) -> [SessionMonthSection] {
        var sections: [SessionMonthSection] = []
        var current: [SessionSummary] = []
        var currentStart: Date?
        for summary in summaries {
            let start = monthStart(of: summary.date, in: calendar)
            if start != currentStart, let currentStart {
                sections.append(SessionMonthSection(start: currentStart, summaries: current))
                current = []
            }
            currentStart = start
            current.append(summary)
        }
        if let currentStart {
            sections.append(SessionMonthSection(start: currentStart, summaries: current))
        }
        return sections
    }

    /// The first instant of `date`'s month.
    ///
    /// **The day is kept where the month cannot be resolved**, rather than dropped: a calendar that
    /// refuses to build the interval would otherwise collapse every such row into one section keyed
    /// on a date nobody logged. There is no such calendar in practice — this is the branch that
    /// stops one being possible.
    ///
    /// - Parameters:
    ///   - date: The training day.
    ///   - calendar: The calendar to take the month in.
    /// - Returns: The month's first instant.
    private static func monthStart(of date: Date, in calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }
}
