import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

// FR-17.11's week view, over the same rows the log reads. EVERY CASE HERE PINS ITS CALENDAR, for
// `CalendarStateTests`' reason one screen along: a calendar decides where a week starts and where a
// day does, so a suite that took `Calendar.current` would assert whatever the running machine is
// set to — and the first weekday is exactly what two of these cases are about.

@Suite("Week history state")
struct WeekHistoryStateTests {
    @Test("A week's sessions are one section, newest first")
    func aWeekGroupsAndOrdersItsSessions() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        // Monday, Wednesday and Friday of the week beginning Sunday 4 January 2026.
        for day in [5, 7, 9] {
            let session = try await log.session(on: TrainingLog.day(2026, 1, day))
            try await log.entry(squat, in: session)
        }

        let state = log.weekState()
        await state.load()

        let weeks = state.weeks
        #expect(weeks.count == 1)
        let week = try #require(weeks.first)
        #expect(week.start == TrainingLog.day(2026, 1, 4))
        #expect(week.end == TrainingLog.day(2026, 1, 10))
        #expect(
            week.summaries.map(\.date) == [
                TrainingLog.day(2026, 1, 9),
                TrainingLog.day(2026, 1, 7),
                TrainingLog.day(2026, 1, 5),
            ])
    }

    @Test("A program week straddling two calendar weeks appears in both, each row with its position")
    func aProgramWeekStraddlingTwoCalendarWeeksAppearsInBoth() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let run = UUID()
        // One program week, three days, run across a Sunday boundary: the Friday and the Saturday
        // fall in the calendar week beginning 28 December, the Monday in the one beginning
        // 4 January.
        for (date, dayIndex) in [
            (TrainingLog.day(2026, 1, 2), 0),
            (TrainingLog.day(2026, 1, 3), 1),
            (TrainingLog.day(2026, 1, 5), 2),
        ] {
            let session = try await log.session(
                on: date, run: run, week: 3, dayIndex: dayIndex)
            try await log.entry(squat, in: session)
        }

        let state = log.weekState()
        await state.load()

        // FR-17.11.3: one notion of week on this tab, and the program's is a label on the row. The
        // same program week is therefore two sections, not one.
        let weeks = state.weeks
        #expect(weeks.count == 2)
        #expect(weeks.map(\.start) == [TrainingLog.day(2026, 1, 4), TrainingLog.day(2025, 12, 28)])
        #expect(weeks[0].summaries.map(\.programPosition) == [ProgramPosition(week: 3, day: 3)])
        #expect(
            weeks[1].summaries.map(\.programPosition) == [
                ProgramPosition(week: 3, day: 2), ProgramPosition(week: 3, day: 1),
            ])
    }

    @Test("A week with nothing logged in it is not a section (FR-17.11.1)")
    func anEmptyWeekIsNotDrawn() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        // Two training weeks with three clear ones between them.
        for date in [TrainingLog.day(2026, 1, 5), TrainingLog.day(2026, 1, 28)] {
            let session = try await log.session(on: date)
            try await log.entry(squat, in: session)
        }

        let state = log.weekState()
        await state.load()

        // Two sections, not five: a section exists because a row opened it, so the weeks off cost
        // nothing at all — which is what makes `FR-17.11.4`'s year back paging rather than a walk.
        #expect(
            state.weeks.map(\.start) == [
                TrainingLog.day(2026, 1, 25), TrainingLog.day(2026, 1, 4),
            ])
    }

    @Test("The week starts where the calendar's first weekday says, Sunday-first")
    func aSundayFirstCalendarCutsTheWeekOnSunday() async throws {
        let state = try await log(trainedOn: [TrainingLog.day(2026, 1, 4)])
            .weekState(calendar: TrainingLog.utc)
        await state.load()

        #expect(state.weeks.map(\.start) == [TrainingLog.day(2026, 1, 4)])
        #expect(state.weeks.map(\.end) == [TrainingLog.day(2026, 1, 10)])
    }

    @Test("The week starts where the calendar's first weekday says, Monday-first")
    func aMondayFirstCalendarCutsTheWeekOnMonday() async throws {
        // The very same Sunday, in a calendar whose week begins on Monday: it is the LAST day of
        // the week before rather than the first of this one, so both ends move.
        let state = try await log(trainedOn: [TrainingLog.day(2026, 1, 4)])
            .weekState(calendar: Self.mondayFirst)
        await state.load()

        #expect(state.weeks.map(\.start) == [TrainingLog.day(2025, 12, 29)])
        #expect(state.weeks.map(\.end) == [TrainingLog.day(2026, 1, 4)])
    }

    @Test("The week read never walks an exercise's set history (NFR-17.5)")
    func theReadNeverWalksASetHistory() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 5))
        let entry = try await log.entry(squat, in: session)
        try await log.set(in: entry, kilograms: 100, reps: 5)

        let counter = CountingWorkoutRepository(wrapping: log.repositories.workouts)
        let state = log.weekState(workouts: counter)
        await state.load()

        // The rows are real — a screen that read nothing would pass a bare count.
        #expect(state.weeks.first?.summaries.first?.setCount == 1)
        #expect(await counter.exerciseSetReads == 0)
        #expect(await counter.sessionReads == 1)
    }

    @Test("A screen opened at a day shows that day's week and everything before it (FR-17.11.2)")
    func anAnchorBoundsTheWeeksToItsOwnAndEarlier() async throws {
        let log = try await log(trainedOn: [
            TrainingLog.day(2026, 1, 5), TrainingLog.day(2026, 1, 28),
        ])

        let state = log.weekState(containing: TrainingLog.day(2026, 1, 7))
        await state.load()

        #expect(state.weeks.map(\.start) == [TrainingLog.day(2026, 1, 4)])
        #expect(state.markedDay == TrainingLog.day(2026, 1, 7))
    }

    @Test("A day twelve months back opens its own week, whatever is logged since (DOD-17.11)")
    func aDayAYearBackOpensItsWeek() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let old = try await log.session(
            on: TrainingLog.day(2025, 1, 8), run: UUID(), week: 2, dayIndex: 1)
        try await log.entry(squat, in: old)
        // A year of training on top of it — more rows than one page holds, so the week a year back
        // is reachable only because the anchor bounds the read rather than because it fits.
        for week in 0..<40 {
            let date = try #require(
                TrainingLog.utc.date(
                    byAdding: .day, value: week * 7, to: TrainingLog.day(2026, 1, 5)))
            try await log.entry(squat, in: try await log.session(on: date))
        }

        let state = log.weekState(containing: TrainingLog.day(2025, 1, 8))
        await state.load()

        let week = try #require(state.weeks.first)
        #expect(week.start == TrainingLog.day(2025, 1, 5))
        #expect(week.summaries.map(\.id) == [old.id])
        #expect(week.summaries.first?.programPosition == ProgramPosition(week: 2, day: 2))
        #expect(state.markedDay == TrainingLog.day(2025, 1, 8))
        #expect(!state.hasMore)
    }

    @Test("The marked day is the anchor's day, whatever time of day the anchor is")
    func theMarkIsNormalisedToItsDay() async throws {
        let log = try await log(trainedOn: [TrainingLog.day(2026, 1, 7)])

        // MID-DAY ON PURPOSE. Every other case here anchors on a day start, which is what the
        // calendar's own cell hands the route — so nothing in this suite could tell the
        // normalisation from its absence, and a probe that dropped it left all of them passing.
        // A restored stack is the case that is not a day start: the instant was resolved in the
        // calendar the grid was drawn in, and a device set to another zone reads it mid-day.
        let midday = try #require(
            TrainingLog.utc.date(byAdding: .hour, value: 15, to: TrainingLog.day(2026, 1, 7)))
        let state = log.weekState(containing: midday)
        await state.load()

        #expect(state.markedDay == TrainingLog.day(2026, 1, 7))
        #expect(state.markedDay != midday)
    }

    @Test("A section's identity is its first row's, and does not move between reads")
    func aSectionKeepsItsIdentityAcrossReads() async throws {
        let log = try await log(trainedOn: [
            TrainingLog.day(2026, 1, 5), TrainingLog.day(2026, 1, 7),
        ])

        let state = log.weekState()
        await state.load()

        // ``weeks`` IS COMPUTED, so a `ForEach` over it re-reads the sections on every body
        // evaluation. An identity taken from anything but the rows would therefore be a fresh one
        // each time — SwiftUI told the same section is a different section — and no assertion on
        // the sections' contents can see that, which is what a probe returning `UUID()` here proved.
        #expect(state.weeks.map(\.id) == state.weeks.map(\.id))
        #expect(state.weeks.map(\.id) == state.weeks.map { $0.summaries[0].id })
    }

    @Test("With no anchor there is no marked day")
    func theTabsOwnModeMarksNothing() async throws {
        let state = try await log(trainedOn: [TrainingLog.day(2026, 1, 5)]).weekState()
        await state.load()

        #expect(state.markedDay == nil)
    }

    @Test("The rows are summarised a page at a time, and the foot asks for the next")
    func theWeeksArePagedFromTheFoot() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for offset in 0..<(SessionListState.pageSize + 5) {
            let date = try #require(
                TrainingLog.utc.date(
                    byAdding: .day, value: -offset, to: TrainingLog.day(2026, 3, 1)))
            try await log.entry(squat, in: try await log.session(on: date))
        }

        let state = log.weekState()
        await state.load()

        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.hasMore)

        await state.loadMore()

        #expect(state.summaries.count == SessionListState.pageSize + 5)
        #expect(!state.hasMore)
    }

    @Test("A failed first read is the screen's error state")
    func aFailedReadIsTheErrorState() async throws {
        let log = try await log(trainedOn: [TrainingLog.day(2026, 1, 5)])

        let state = log.weekState(workouts: FailingWorkoutRepository())
        await state.load()

        #expect(WeekHistoryScreenState.current(state.phase) == .failed)
        #expect(state.weeks.isEmpty)
    }

    @Test("A store with nothing in it is the empty state, not an empty list of weeks")
    func nothingLoggedIsTheEmptyState() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")

        let state = log.weekState()
        await state.load()

        #expect(WeekHistoryScreenState.current(state.phase) == .empty)
    }

    @Test("A failed later page leaves the weeks on screen and reports beside them")
    func aFailedPageKeepsTheWeeksItHas() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for offset in 0..<(SessionListState.pageSize + 5) {
            let date = try #require(
                TrainingLog.utc.date(
                    byAdding: .day, value: -offset, to: TrainingLog.day(2026, 3, 1)))
            try await log.entry(squat, in: try await log.session(on: date))
        }

        let state = log.weekState(
            workouts: FlakyWorkoutRepository(
                wrapping: log.repositories.workouts, failingAfter: SessionListState.pageSize))
        await state.load()
        await state.loadMore()

        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.extendFailure != nil)
        #expect(WeekHistoryScreenState.current(state.phase) == .ready)
    }

    @Test("Two sessions under one identifier are one row, not a ForEach keyed on both (G-2.5)")
    func duplicateSessionIdentifiersAreOneRow() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 5))
        try await log.entry(squat, in: session)
        // The pair a local `save` cannot write. A week's rows are a `ForEach` keyed on this
        // identifier, which renders neither of a duplicated pair correctly.
        let foreign = ForeignWorkoutLog(holding: [session, session], over: log.repositories.workouts)

        let state = log.weekState(workouts: foreign)
        await state.load()

        #expect(state.weeks.first?.summaries.map(\.id) == [session.id])
    }

    @Test("The unit is the settings row's, read on every appearance")
    func theUnitFollowsTheSetting() async throws {
        let log = try await log(trainedOn: [TrainingLog.day(2026, 1, 5)])

        let state = log.weekState()
        await state.load()
        #expect(state.displayUnit == .kilograms)

        try await log.setDisplayUnit(.pounds)
        await state.load()

        #expect(state.displayUnit == .pounds)
    }

    @Test("Adopting another calendar re-cuts the weeks and moves the mark with them")
    func adoptingACalendarRecutsTheWeeks() async throws {
        let log = try await log(trainedOn: [TrainingLog.day(2026, 1, 4)])

        let state = log.weekState(containing: TrainingLog.day(2026, 1, 4))
        await state.load()
        #expect(state.weeks.map(\.start) == [TrainingLog.day(2026, 1, 4)])

        state.adopt(Self.mondayFirst)

        // Nothing is re-read: every week-shaped value is computed from the rows already held.
        #expect(state.weeks.map(\.start) == [TrainingLog.day(2025, 12, 29)])
        #expect(state.markedDay == TrainingLog.day(2026, 1, 4))
    }

    /// A store with one bare session on each of `days`.
    ///
    /// - Parameter days: The training days.
    /// - Returns: The store.
    private func log(trainedOn days: [Date]) async throws -> TrainingLog {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in days {
            try await log.entry(squat, in: try await log.session(on: day))
        }
        return log
    }

    /// ``TrainingLog/utc`` with the week beginning on Monday.
    ///
    /// The one thing this suite varies about a calendar: where a week starts is the locale's
    /// (`FR-17.11.1`), and it is the only such question the grouping asks.
    private static var mondayFirst: Calendar {
        var calendar = TrainingLog.utc
        calendar.firstWeekday = 2
        return calendar
    }
}
