import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.5`'s week and `FR-1.13.2`'s first launch — the one read that answers both.
///
/// **Every total here is worked out by hand and written as a literal**, rather than compared against
/// a second computation: a test asserting `state.summary?.tonnage == Tonnage.of(sets)` passes for
/// any arithmetic both sides share, including none.
@MainActor
@Suite("Week summary")
struct WeekSummaryStateTests {
    /// A calendar pinned to GMT, so a week's boundaries do not move with the machine running this.
    ///
    /// `fixtureNow` is a Tuesday; this calendar's week runs from the Sunday two days before it to
    /// the Sunday five days after.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// A state over `fixture`, told that "now" is ``fixtureNow``.
    static func state(_ fixture: DashboardFixture) -> WeekSummaryState {
        WeekSummaryState(
            workouts: fixture.repositories.workouts, calendar: calendar, now: { fixtureNow })
    }

    @Test("An install with nothing in it is FR-1.13.2's first launch")
    func firstLaunch() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "Back Squat")
        let state = Self.state(fixture)

        await state.load()

        // A seeded catalogue is not history: the question is whether a session was ever logged.
        #expect(state.hasEverTrained == false)
        #expect(state.hasLoaded)
        #expect(state.failure == nil)
        #expect(state.summary == WeekSummary(workoutCount: 0, tonnage: .zero))
        #expect(DashboardScreenState.current(state) == .firstLaunch)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
    }

    @Test("A hand-computed week: 5×100 + 3×120 is 860 kg over one workout")
    func handComputed() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // 500 + 360. Two different loads at two different rep counts, so a transposed multiply does
        // not land on the same total.
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5), LoggedSet(grams: 120_000, reps: 3)])
            ])
        let state = Self.state(fixture)

        await state.load()

        #expect(state.summary == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 860_000)))
        #expect(state.hasEverTrained)
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(
            WeekSummaryScreenState.current(state)
                == .ready(WeekSummary(workoutCount: 1, tonnage: Weight(grams: 860_000))))
    }

    @Test("Last week's training is history but not this week's volume")
    func lastWeekIsExcluded() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        // The two halves of the one read disagreeing is the whole point of folding them together:
        // there IS history, and this week holds none of it.
        #expect(state.hasEverTrained)
        #expect(state.summary == WeekSummary(workoutCount: 0, tonnage: .zero))
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
    }

    @Test("A backdated session is weighed into the week it was trained, not the week it was entered")
    func backdatingDecidesTheWeek() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // `FR-1.2.1`'s backdate: trained last week, typed in today. This is the only fixture shape
        // that can tell `session.date` from `session.createdAt` — every other session here writes
        // one value into both, so a read of the wrong column passes them all.
        try await fixture.session(
            on: weeksAgo(1),
            enteredOn: fixtureNow,
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        // Trained this week, and the only thing that may be counted. Present so the assertion is a
        // real total rather than a zero every broken reading also produces.
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 120_000, reps: 3)])])
        let state = Self.state(fixture)

        await state.load()

        // 360, not 860: reading `createdAt` would pull last week's 500 into this week's volume.
        #expect(state.summary == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 360_000)))
    }

    @Test("Two sessions this week are two workouts, summed")
    func twoSessions() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: fixtureNow.addingTimeInterval(-2 * 86_400),
            exercises: [(squat, [LoggedSet(grams: 80_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        // 500 + 400.
        #expect(state.summary == WeekSummary(workoutCount: 2, tonnage: Weight(grams: 900_000)))
    }

    @Test("A workout still in progress counts as this week's")
    func openSessionCounts() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow,
            isFinished: false,
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        #expect(state.summary == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
    }

    @Test("A session with only warmups and failures is not a workout")
    func nothingPerformed() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (
                    squat,
                    [
                        LoggedSet(grams: 60_000, reps: 5, isWarmup: true),
                        LoggedSet(grams: 100_000, reps: 8, isCompleted: false),
                    ]
                )
            ])
        let state = Self.state(fixture)

        await state.load()

        // A session opened and not trained in raises neither number — the count is drawn from the
        // same population as the volume.
        #expect(state.summary == WeekSummary(workoutCount: 0, tonnage: .zero))
        #expect(state.hasEverTrained)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
    }

    @Test("A week of bodyweight work is a workout with no volume, not a zero")
    func unweighable() async throws {
        let fixture = DashboardFixture()
        let pullUp = try await fixture.exercise(named: "Pull-Up")
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (
                    pullUp,
                    [LoggedSet(grams: 0, reps: 10), LoggedSet(grams: -20_000, reps: 8)]
                )
            ])
        let state = Self.state(fixture)

        await state.load()

        // FR-1.13.3: the workout happened and its volume is not zero, it is unweighable. The two
        // read differently and the screen says so.
        #expect(state.summary == WeekSummary(workoutCount: 1, tonnage: .zero))
        #expect(WeekSummaryScreenState.current(state) == .unweighed(workouts: 1))
    }

    @Test("A read that fails says so, and is not read as a first launch")
    func failedRead() async {
        let state = WeekSummaryState(
            workouts: FailingWorkoutRepository(), calendar: Self.calendar, now: { fixtureNow })

        await state.load()

        #expect(state.failure != nil)
        #expect(state.hasLoaded)
        #expect(state.summary == nil)
        // The failure says nothing about whether anything was ever logged, so the sections draw and
        // each reports its own — a screen that read this as an empty install would replace four
        // readable cards with a welcome message.
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(WeekSummaryScreenState.current(state) == .failed)
    }

    @Test("Before the read answers, the sections draw and the summary is loading")
    func beforeLoading() {
        let state = Self.state(DashboardFixture())

        #expect(state.hasLoaded == false)
        #expect(WeekSummaryScreenState.current(state) == .loading)
        // Not `.firstLaunch`: nothing has been read, so nothing is known about the install yet, and
        // a welcome message shown while the store is still answering would flash on every launch.
        #expect(DashboardScreenState.current(state) == .sections)
    }

    @Test("A failure outranks the week already on screen")
    func failureOutranksStaleSummary() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let switchable = SwitchableWorkouts(wrapping: fixture.repositories.workouts)
        let state = WeekSummaryState(
            workouts: switchable, calendar: Self.calendar, now: { fixtureNow })
        await state.load()
        #expect(state.summary == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))

        await switchable.refuse()
        await state.load()

        #expect(state.summary != nil, "the previous answer is still held")
        #expect(WeekSummaryScreenState.current(state) == .failed)
    }
}

/// Sessions that answer until told to stop, for the stale-summary case.
///
/// An actor wrapping the fakes rather than a fake with a flag, on `SwitchableCache`'s rule: the
/// fakes in `RepositoryFakes` are the *contract*, and a switch that made one fail would make every
/// test that shares them able to.
private actor SwitchableWorkouts: WorkoutRepository {
    /// Where a read that is not refusing is answered from.
    private let wrapped: any WorkoutRepository

    /// Whether every later call throws.
    private var isRefusing = false

    /// What a refusal throws. The case does not matter — the state under test reports *that* a read
    /// failed, never which error it was.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// Makes every later call throw.
    func refuse() {
        isRefusing = true
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        guard !isRefusing else { throw failure }
        return try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(session)
    }

    func deleteSession(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteSession(id: id)
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        guard !isRefusing else { throw failure }
        return try await wrapped.entries(
            forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        guard !isRefusing else { throw failure }
        return try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(entry)
    }

    func deleteExerciseEntry(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteExerciseEntry(id: id)
    }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func save(_ set: SetEntry) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(set)
    }

    func deleteSet(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteSet(id: id)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sets(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}
