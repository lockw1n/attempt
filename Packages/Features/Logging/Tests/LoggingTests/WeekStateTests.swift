import DesignSystem
import Foundation
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Train's root, which is the week (`FR-17.8.1`, `FR-17.8.2`, `D-17.5`).
///
/// **Over a real read rather than a decision function**, unlike the root this replaces: a day's
/// state is a join of four tables, and the thing worth pinning is that the join reads the *sessions*
/// rather than the run's cursor.
@MainActor
@Suite("The week")
struct WeekStateTests {
    @Test("A day nothing has been logged into has not started")
    func aDayWithNoSessionHasNotStarted() async throws {
        let fixture = try await WeekFixture(days: 3)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        #expect(WeekFixture.days(of: state).map(\.progress) == [.notStarted, .notStarted, .notStarted])
    }

    @Test("A day part-answered is in progress, and says how far")
    func aPartAnsweredDayIsInProgress() async throws {
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 4)
        try await fixture.log(day: 1, done: 2)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        #expect(WeekFixture.days(of: state)[1].progress == .inProgress(done: 2, of: 4))
    }

    @Test("A day with every exercise answered is done, on the day it was logged for")
    func anAnsweredDayIsDone() async throws {
        let logged = weekFixtureDay + 86_400
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 4)
        try await fixture.log(day: 0, done: 4, on: logged)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        #expect(WeekFixture.days(of: state)[0].progress == .done(on: logged))
    }

    @Test("Day three done with day one not started reads in program order, each right")
    func daysMayBeDoneInAnyOrder() async throws {
        // D-17.10: the whole point of reading the sessions rather than the cursor. A run whose
        // `nextDayIndex` still points at day 0 draws day 2 as done.
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 2)
        try await fixture.log(day: 2, done: 2)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        let days = WeekFixture.days(of: state)
        #expect(days.map(\.dayIndex) == [0, 1, 2])
        #expect(days[0].progress == .notStarted)
        #expect(days[1].progress == .notStarted)
        #expect(days[2].progress == .done(on: weekFixtureDay))
    }

    @Test("A cursor pointing elsewhere changes nothing")
    func theCursorIsNotRead() async throws {
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 2)
        try await fixture.log(day: 0, done: 2)
        let run = try #require(try await fixture.stack.programs.currentRun())
        // `nextDayIndex` says the week is over; the sessions say one day of three is done. The
        // sessions win — the column is written no more (`TR-17.4`).
        try await fixture.stack.programs.save(run.movedTo(nextDayIndex: 9))
        let state = fixture.weekState()

        await state.load(openSession: nil)

        let days = WeekFixture.days(of: state)
        #expect(days.count == 3)
        #expect(days[0].progress == .done(on: weekFixtureDay))
        #expect(days[1].progress == .notStarted)
    }

    @Test("A session stamped with another week is not this week's")
    func aForeignWeekIsNotRead() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 2)
        try await fixture.log(day: 0, done: 2, week: WeekFixture.week + 1)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        #expect(WeekFixture.days(of: state)[0].progress == .notStarted)
    }

    @Test("Each card carries the day's exercises with their plan")
    func aCardCarriesThePlan() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 3)
        let state = fixture.weekState()

        await state.load(openSession: nil)

        let day = WeekFixture.days(of: state)[0]
        #expect(day.name == "Day 1")
        #expect(day.plan.map { $0.exercise?.name } == ["Lift 1-1", "Lift 1-2", "Lift 1-3"])
        #expect(day.plan[0].targets.map(\.reps) == [5])
        #expect(day.plan[0].targets.map(\.sets) == [3])
        #expect(day.plan[0].targets.first?.weight?.grams == 100_000)
    }

    @Test("An in-progress free workout is a card of its own; a finished one is not")
    func onlyAnOpenFreeWorkoutGetsACard() async throws {
        let fixture = try await WeekFixture(days: 2)
        let state = fixture.weekState()

        await state.load(openSession: freeWorkoutSession())
        #expect(state.freeWorkout == FreeWorkoutCard(date: weekFixtureDay))

        await state.load(openSession: freeWorkoutSession(endedAt: weekFixtureDay))
        #expect(state.freeWorkout == nil)
    }

    @Test("A planned day being logged is not a free workout")
    func aProgramSessionIsNotAFreeWorkout() async throws {
        let fixture = try await WeekFixture(days: 2, exercisesPerDay: 1)
        let sessionID = try await fixture.log(day: 0, done: 0)
        let session = try #require(
            try await fixture.stack.workouts.session(id: sessionID, includingDeleted: false))
        let state = fixture.weekState()

        await state.load(openSession: session)

        #expect(state.freeWorkout == nil)
    }

    @Test("No run at all is the empty week")
    func noRunIsEmpty() async throws {
        let stack = InMemoryRepositoryStack()
        let state = WeekState(
            programs: stack.programs,
            routines: stack.routines,
            workouts: stack.workouts,
            exercises: stack.exercises)

        await state.load(openSession: nil)

        #expect(state.reading == .empty)
        #expect(state.phase == .ready)
    }

    @Test("A read that failed carries the diagnostic and draws no week")
    func aFailedReadDrawsNoWeek() async throws {
        let stack = InMemoryRepositoryStack()
        let state = WeekState(
            programs: UnreadablePrograms(),
            routines: stack.routines,
            workouts: stack.workouts,
            exercises: stack.exercises)

        await state.load(openSession: nil)

        #expect(state.reading == .empty)
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed read")
            return
        }
        #expect(!diagnostic.isEmpty)
    }

    @Test("A day whose routine has been archived is kept, nameless and planless")
    func anArchivedRoutineLeavesTheCard() async throws {
        // T-16.15's rule, one screen over: sweeping the day would silently shorten the week.
        let fixture = try await WeekFixture(days: 3)
        try await fixture.stack.routines.deleteRoutine(id: fixture.routineIDs[1])
        let state = fixture.weekState()

        await state.load(openSession: nil)

        let days = WeekFixture.days(of: state)
        #expect(days.count == 3)
        #expect(days[1].name.isEmpty)
        #expect(days[1].plan.isEmpty)
        #expect(days[1].progress == .notStarted)
    }

    // MARK: - NFR-17.4

    @Test("The week's read walks no set history, however long the week")
    func theWeekReadNeverWalksSets() async throws {
        let fixture = try await WeekFixture(days: 6, exercisesPerDay: 4)
        for day in 0..<3 { try await fixture.log(day: day, done: 4) }
        let counting = SetWalkCounter(wrapped: fixture.stack.workouts)
        let state = fixture.weekState(workouts: counting)

        await state.load(openSession: nil)

        #expect(WeekFixture.days(of: state).count == 6)
        #expect(await counting.setWalks == 0)
    }

    // MARK: - DOD-17.12

    @Test("A six-day program draws six cards and a two-day one draws two")
    func theWeekIsAsLongAsTheProgram() async throws {
        let six = try await WeekFixture(days: 6, exercisesPerDay: 4)
        for day in [0, 2, 4] { try await six.log(day: day, done: 4) }
        let sixState = six.weekState()
        await sixState.load(openSession: nil)

        let two = try await WeekFixture(days: 2, exercisesPerDay: 4)
        let twoState = two.weekState()
        await twoState.load(openSession: nil)

        let days = WeekFixture.days(of: sixState)
        #expect(days.count == 6)
        #expect(days.filter { $0.progress == .done(on: weekFixtureDay) }.count == 3)
        #expect(WeekFixture.days(of: twoState).count == 2)
    }

    // MARK: - FR-16.6.4

    @Test("The week spends its one accent on the day in progress")
    func theAccentGoesToTheDayInProgress() async throws {
        let days = [
            card(0, .notStarted), card(1, .inProgress(done: 1, of: 3)), card(2, .notStarted),
        ]

        #expect(StateActionEmphasis.weekCommand(on: days[0], among: days) == .secondary)
        #expect(StateActionEmphasis.weekCommand(on: days[1], among: days) == .primary)
        #expect(StateActionEmphasis.weekCommand(on: days[2], among: days) == .secondary)
    }

    @Test("With nothing in progress it goes to the first day not started")
    func theAccentGoesToTheFirstNotStartedDay() async throws {
        let days = [card(0, .done(on: weekFixtureDay)), card(1, .notStarted), card(2, .notStarted)]

        #expect(StateActionEmphasis.weekCommand(on: days[0], among: days) == .secondary)
        #expect(StateActionEmphasis.weekCommand(on: days[1], among: days) == .primary)
        #expect(StateActionEmphasis.weekCommand(on: days[2], among: days) == .secondary)
    }

    @Test("A week with every day done spends no accent at all")
    func aFinishedWeekSpendsNoAccent() async throws {
        let days = [card(0, .done(on: weekFixtureDay)), card(1, .done(on: weekFixtureDay))]

        #expect(StateActionEmphasis.weekCommand(on: days[0], among: days) == .secondary)
        #expect(StateActionEmphasis.weekCommand(on: days[1], among: days) == .secondary)
    }

    @Test("A day in progress outranks an earlier day not started")
    func theDayInProgressOutranksAnEarlierUntouchedOne() async throws {
        let days = [card(0, .notStarted), card(1, .inProgress(done: 2, of: 4))]

        #expect(StateActionEmphasis.weekCommand(on: days[1], among: days) == .primary)
        #expect(StateActionEmphasis.weekCommand(on: days[0], among: days) == .secondary)
    }

    /// One card, for the rule that reads only its index and its state.
    private func card(_ index: Int, _ progress: WeekDayProgress) -> WeekDayCard {
        WeekDayCard(dayIndex: index, name: "Day \(index + 1)", plan: [], progress: progress)
    }
}

/// A workout store that counts the cross-exercise set walk (`NFR-17.4`).
///
/// **An actor** (`G-6.4`): `WorkoutRepository` refines `Sendable`, so a class with a mutable counter
/// could conform only through `@unchecked Sendable`.
actor SetWalkCounter: WorkoutRepository {
    /// What answers everything.
    let wrapped: any WorkoutRepository

    /// How many times the year of training behind an exercise has been walked.
    private(set) var setWalks = 0

    /// Wraps the store that answers.
    ///
    /// - Parameter wrapped: The real repository.
    init(wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(
            forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        setWalks += 1
        return try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}
