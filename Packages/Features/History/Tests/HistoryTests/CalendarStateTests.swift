import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

/// The calendar's reads (`FR-1.5.3`) — which days are marked, what selecting one shows, what a tap
/// on an empty day does, and where the two chevrons stop.
@MainActor
@Suite("Calendar")
struct CalendarStateTests {
    @Test("Marked days are exactly the fixture's, across a month and a year boundary")
    func markedDaysMatchTheFixture() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let trained = [
            TrainingLog.day(2025, 12, 30),
            TrainingLog.day(2025, 12, 31),
            TrainingLog.day(2026, 1, 1),
            TrainingLog.day(2026, 1, 15),
        ]
        for date in trained {
            let session = try await log.session(on: date)
            try await log.entry(squat, in: session)
        }
        // FR-1.2.1's backdating: entered in January, trained in December. The marker belongs on the
        // day it was trained, and a screen keying on `createdAt` would put it three weeks late.
        try await log.session(
            on: TrainingLog.day(2025, 12, 2), enteredOn: TrainingLog.day(2026, 1, 20))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()

        #expect(state.trainingDays == Set(trained + [TrainingLog.day(2025, 12, 2)]))
        for date in trained { #expect(state.hasTraining(on: date)) }
        #expect(state.hasTraining(on: TrainingLog.day(2025, 12, 2)))
        // Asked about an instant rather than a day start, which is what a grid cell hands it only
        // by construction — the normalisation has to be in the method, not in the caller.
        #expect(state.hasTraining(on: TrainingLog.day(2026, 1, 15, hour: 16)))
        // The days either side of each boundary, which is where an off-by-one lands.
        #expect(!state.hasTraining(on: TrainingLog.day(2025, 12, 29)))
        #expect(!state.hasTraining(on: TrainingLog.day(2026, 1, 2)))
        #expect(!state.hasTraining(on: TrainingLog.day(2026, 1, 14)))
    }

    @Test("A session logged at any hour of a day marks that day")
    func aDayIsMarkedWhateverTimeItWasTrainedAt() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        // Not a day start: a row that arrived by sync or restore was not written by this app, and
        // this app's own writer is the only thing that normalises.
        try await log.session(on: TrainingLog.day(2026, 1, 9, hour: 23))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()

        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
        #expect(!state.hasTraining(on: TrainingLog.day(2026, 1, 10)))
    }

    @Test("The grid marks the visible month's days and never a neighbour's")
    func theGridMarksOnlyItsOwnMonth() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2025, 12, 31))
        try await log.session(on: TrainingLog.day(2026, 1, 1))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        state.showMonth(offsetBy: -1)

        #expect(state.grid.month == TrainingLog.day(2025, 12, 1))
        let marked = state.grid.weeks.flatMap { $0 }.compactMap { $0 }
            .filter(state.hasTraining(on:))
        // 1 January is a training day and is not a cell of December's grid, so it is not drawn.
        #expect(marked == [TrainingLog.day(2025, 12, 31)])
    }

    @Test("A failed read of one day costs the screen that day and not the grid")
    func aFailedDayReadKeepsTheMarkers() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9))
        try await log.entry(squat, in: session)

        let state = log.calendarState(
            today: TrainingLog.day(2026, 1, 20),
            workouts: FlakyWorkoutRepository(wrapping: log.repositories.workouts, failingAfter: 0)
        )
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))

        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
        #expect(CalendarScreenState.current(state.phase, trainingDays: 1) == .ready)
        guard case .failed = state.day else {
            Issue.record("expected the day to have failed, got \(state.day)")
            return
        }
    }

    @Test("A failed read of the sessions is the screen's error state, with nothing marked")
    func aFailedReadIsTheErrorState() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2026, 1, 9))

        let state = log.calendarState(
            today: TrainingLog.day(2026, 1, 20), workouts: FailingWorkoutRepository())
        await state.load()

        #expect(state.trainingDays.isEmpty)
        #expect(CalendarScreenState.current(state.phase, trainingDays: 0) == .failed)
    }

    @Test("Nothing ever logged is the empty state rather than an empty grid")
    func nothingLoggedIsTheEmptyState() async throws {
        let log = TrainingLog()
        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()

        #expect(CalendarScreenState.current(state.phase, trainingDays: 0) == .empty)
        #expect(!state.canShowEarlierMonth)
        #expect(!state.canShowLaterMonth)
    }

    @Test("The chevrons stop at the oldest training month and at the current one")
    func monthBoundsSpanTheHistoryAndToday() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2025, 10, 4))
        try await log.session(on: TrainingLog.day(2025, 12, 31))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()

        #expect(state.grid.month == TrainingLog.day(2026, 1, 1))
        #expect(!state.canShowLaterMonth)
        #expect(state.canShowEarlierMonth)

        for _ in 1...3 { state.showMonth(offsetBy: -1) }
        #expect(state.grid.month == TrainingLog.day(2025, 10, 1))
        #expect(!state.canShowEarlierMonth)

        // A step past the end changes nothing, rather than being clamped to somewhere else.
        state.showMonth(offsetBy: -1)
        #expect(state.grid.month == TrainingLog.day(2025, 10, 1))

        // The re-read that every return to this screen performs, taken while an earlier month is
        // showing. A range anchored on the *visible* month rather than on the one the screen opened
        // on would be dragged back to it here, and the forward chevron would then stop at December.
        await state.load()
        #expect(state.grid.month == TrainingLog.day(2025, 10, 1))
        #expect(state.canShowLaterMonth)

        for _ in 1...3 { state.showMonth(offsetBy: 1) }
        #expect(state.grid.month == TrainingLog.day(2026, 1, 1))
        #expect(!state.canShowLaterMonth)
    }

    @Test("A session in the future is still reachable")
    func aFutureSessionExtendsTheForwardBound() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        // No screen in this app writes one, but a synced or restored row is not this app's write.
        try await log.session(on: TrainingLog.day(2026, 3, 4))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()

        #expect(state.canShowLaterMonth)
        for _ in 1...2 { state.showMonth(offsetBy: 1) }
        #expect(state.grid.month == TrainingLog.day(2026, 3, 1))
        #expect(!state.canShowLaterMonth)
    }

    @Test("Adopting another time zone moves a day that straddles midnight")
    func adoptingACalendarReindexesTheDays() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        // 00:30 UTC on New Year's Day is 23:30 on New Year's Eve one hour west — a different day,
        // a different month and a different year.
        try await log.session(on: TrainingLog.day(2026, 1, 1, hour: 0))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 1)])

        state.adopt(TrainingLog.oneHourBehind)

        #expect(state.trainingDays == [TrainingLog.day(2025, 12, 31, in: TrainingLog.oneHourBehind)])
        #expect(!state.hasTraining(on: TrainingLog.day(2026, 1, 1, in: TrainingLog.oneHourBehind)))
    }

    @Test("Adopting the calendar already in use changes nothing")
    func adoptingTheSameCalendarIsANoOp() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9))
        try await log.entry(squat, in: session)

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))

        state.adopt(TrainingLog.utc)

        #expect(state.selectedDay == TrainingLog.day(2026, 1, 9))
        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
    }

    @Test("Two sessions on one day are one marker with both rows beneath it")
    func aDayWithTwoSessionsIsStillOneMarker() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2026, 1, 9))
        try await log.session(on: TrainingLog.day(2026, 1, 9))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))

        // One marker for two sessions, and both rows under it: the grid marks days, so a second
        // session on a marked day adds a row rather than a dot.
        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the day's rows, got \(state.day)")
            return
        }
        #expect(rows.count == 2)
    }

    @Test("Two sessions under one identifier are one row, not a ForEach keyed on both (G-2.5)")
    func duplicateSessionIdentifiersAreOneRow() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9))
        try await log.entry(squat, in: session)
        // The pair a local `save` cannot write. The day's section is a `ForEach` keyed on this
        // identifier, which renders neither of a duplicated pair correctly — the same reason the
        // session list deduplicates the same read.
        let foreign = ForeignWorkoutLog(holding: [session, session], over: log.repositories.workouts)

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20), workouts: foreign)
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))

        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the day's rows, got \(state.day)")
            return
        }
        #expect(rows.count == 1)
        #expect(rows.map(\.id) == [session.id])
    }

    @Test("A month the history no longer reaches is clamped to the nearest one that survives")
    func aMonthBelowTheRangeIsClampedToTheOldestThatSurvives() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        let august = try await log.session(on: TrainingLog.day(2025, 8, 10))
        try await log.session(on: TrainingLog.day(2025, 11, 15))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        for _ in 1...5 { state.showMonth(offsetBy: -1) }
        #expect(state.grid.month == TrainingLog.day(2025, 8, 1))

        // The oldest month deleted elsewhere, then the re-read every return to this screen makes.
        // Left on August, the forward chevron would read as enabled and refuse every step.
        try await log.repositories.workouts.deleteSession(id: august.id)
        await state.load()

        // November, the oldest month that survives — not January, which is the far end.
        #expect(state.grid.month == TrainingLog.day(2025, 11, 1))
        #expect(!state.canShowEarlierMonth)
        #expect(state.canShowLaterMonth)
    }

    @Test("A month past the far end is clamped back to it")
    func aMonthAboveTheRangeIsClampedToTheLatestThatSurvives() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2025, 11, 15))
        let march = try await log.session(on: TrainingLog.day(2026, 3, 4))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        for _ in 1...2 { state.showMonth(offsetBy: 1) }
        #expect(state.grid.month == TrainingLog.day(2026, 3, 1))

        try await log.repositories.workouts.deleteSession(id: march.id)
        await state.load()

        #expect(state.grid.month == TrainingLog.day(2026, 1, 1))
        #expect(!state.canShowLaterMonth)
        #expect(state.canShowEarlierMonth)
    }

    @Test("Before the first read the screen is loading, not empty")
    func idleIsLoading() {
        let state = TrainingLog().calendarState(today: TrainingLog.day(2026, 1, 20))
        #expect(CalendarScreenState.current(state.phase, trainingDays: 0) == .loading)
    }

    @Test("A read arriving while one is in flight is refused rather than run twice")
    func aConcurrentReadIsRefused() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2026, 1, 9))

        let counter = CountingWorkoutRepository(wrapping: log.repositories.workouts)
        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20), workouts: counter)

        // The direct call runs first and suspends inside the settings read; the task then finds the
        // screen already loading. Both have returned before anything is asserted.
        let second = Task { await state.load() }
        await state.load()
        await second.value

        #expect(await counter.sessionReads == 1)
        #expect(state.trainingDays == [TrainingLog.day(2026, 1, 9)])
    }

    @Test("The unit is the settings row's, read on every appearance")
    func theUnitFollowsTheSetting() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2026, 1, 9))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        #expect(state.displayUnit == .kilograms)

        try await log.setDisplayUnit(.pounds)
        await state.load()

        #expect(state.displayUnit == .pounds)
    }
}
