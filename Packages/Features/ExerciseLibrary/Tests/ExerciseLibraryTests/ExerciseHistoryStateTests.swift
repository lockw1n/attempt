import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.5.2`'s per-exercise history: what is grouped, in what order, and how far the walk goes.
///
/// **The store is written to rather than stubbed**, on `ExerciseDetailLoggedSetsTests`' rule: the
/// grouping is a join across three tables the repository owns the ordering of, and a fake handing
/// back what a test gave it could not fail an assertion about that ordering.
@Suite("Exercise history")
struct ExerciseHistoryStateTests {
    @Test("An exercise nothing has been logged against has no history, not an empty one")
    func neverTrained() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.groups.isEmpty)
        #expect(state.hasMore == false)
        #expect(ExerciseHistoryScreenState.current(state.phase) == .noneYet)
    }

    @Test("Sessions are grouped, newest first")
    func newestFirst() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        try await gym.train(squat, onDay: 1, reps: [5])
        try await gym.train(squat, onDay: 3, reps: [3])
        try await gym.train(squat, onDay: 2, reps: [8])

        let state = gym.history(of: squat)
        await state.load()

        // Anchored to the days themselves rather than to `first`/`last`: a state that returned
        // nothing satisfies "the dates are in descending order".
        #expect(state.groups.map(\.date) == [gym.day(3), gym.day(2), gym.day(1)])
        #expect(state.groups.map { $0.sets.map(\.reps) } == [[3], [8], [5]])
        #expect(ExerciseHistoryScreenState.current(state.phase) == .ready)
    }

    @Test("A session's sets run in (entry order, set order), across both entries where there are two")
    func setsWithinASession() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        // One training day, the exercise performed twice — first as the opener, then again later.
        let day = try await gym.session(onDay: 1)
        try await gym.perform(squat, in: day, order: 0, reps: [5, 4])
        try await gym.perform(squat, in: day, order: 1, reps: [12, 10])

        let state = gym.history(of: squat)
        await state.load()

        // ONE group, not two: FR-1.5.2 groups by session, and two entries on one day are two
        // positions in a workout rather than two days.
        #expect(state.groups.count == 1)
        #expect(state.groups.first?.sets.map(\.reps) == [5, 4, 12, 10])
    }

    @Test("Two workouts on one training day are ordered by when they started")
    func twoWorkoutsInADay() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        // The identifiers are pinned, and they are pinned the wrong way round on purpose: the
        // morning's sorts *after* the evening's, so an ordering that fell back to the identifier
        // would put the morning session first and this test would catch it. Left to chance it is
        // right half the time, which is a test that cannot fail half the time.
        let morning = try await gym.session(
            id: Fixtures.identifier("9"), onDay: 1, startedAt: gym.day(1))
        let evening = try await gym.session(
            id: Fixtures.identifier("1"),
            onDay: 1,
            startedAt: gym.day(1).addingTimeInterval(43_200)
        )
        try await gym.perform(squat, in: morning, order: 0, reps: [5])
        try await gym.perform(squat, in: evening, order: 0, reps: [3])

        let state = gym.history(of: squat)
        await state.load()

        // Both groups carry the same date, so the only thing separating them is `startedAt` — and
        // without it the order falls to a UUID and is right about half the time.
        #expect(state.groups.map(\.id) == [evening.id, morning.id])
    }

    @Test("Another exercise's sets are not this one's, and its sessions do not use up the page")
    func otherExercisesAreSkipped() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        let bench = try await gym.exercise(named: "Bench Press")
        try await gym.train(squat, onDay: 1, reps: [5])
        for day in 2...9 {
            try await gym.train(bench, onDay: day, reps: [8])
        }
        try await gym.train(squat, onDay: 10, reps: [3])

        let state = gym.history(of: squat)
        await state.load()

        // Eight bench sessions sit between the two squat ones. A page counts what the reader sees,
        // so both squat sessions are on the first page rather than one per five sessions scanned.
        #expect(state.groups.map { $0.sets.map(\.reps) } == [[3], [5]])
        #expect(state.hasMore == false)
    }

    @Test("A page is five sessions, and the rest is behind the control")
    func paging() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        for day in 1...6 {
            try await gym.train(squat, onDay: day, reps: [day])
        }

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.groups.count == ExerciseHistoryState.pageSize)
        #expect(state.groups.map(\.date) == [gym.day(6), gym.day(5), gym.day(4), gym.day(3), gym.day(2)])
        #expect(state.hasMore)

        await state.loadMore()

        // Appended, not replaced, and the seam neither repeats day 2 nor skips day 1.
        #expect(
            state.groups.map(\.date)
                == [gym.day(6), gym.day(5), gym.day(4), gym.day(3), gym.day(2), gym.day(1)])
        #expect(state.hasMore == false)
        #expect(state.extendFailure == nil)
    }

    @Test("The walk stops at the oldest set rather than at the end of the history")
    func theWalkStopsEarly() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        let bench = try await gym.exercise(named: "Bench Press")
        for day in 1...20 {
            try await gym.train(bench, onDay: day, reps: [8])
        }
        try await gym.train(squat, onDay: 21, reps: [5])
        let counter = CountingWorkoutRepository(wrapping: gym.workouts)

        let state = ExerciseHistoryState(
            exerciseID: squat.id, workouts: counter, settings: gym.settings)
        await state.load()

        // The first read returns one set, so the walk knows it is looking for one and stops the
        // moment it has it — one session read, not the twenty-one there are.
        #expect(state.groups.count == 1)
        #expect(await counter.sessionsRead == 1)
    }

    @Test("A rating that was not recorded is absent rather than blank")
    func ratingIsOptional() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        let day = try await gym.session(onDay: 1)
        try await gym.perform(squat, in: day, order: 0, reps: [5, 5], rpe: [8.5, nil])

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.groups.first?.sets.map(\.rpe) == [8.5, nil])
    }

    @Test("The unit is the settings row's, and kilograms where it cannot be read")
    func displayUnit() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        try await gym.train(squat, onDay: 1, reps: [5])
        try await gym.useUnit(.pounds)

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.displayUnit == .pounds)

        let unreadable = ExerciseHistoryState(
            exerciseID: squat.id, workouts: gym.workouts, settings: RefusingSettingsRepository())
        await unreadable.load()

        // The schema's own default, and the history is still read: a settings fault costs the rows
        // their unit, not their existence.
        #expect(unreadable.displayUnit == .kilograms)
        #expect(unreadable.groups.count == 1)
    }

    @Test("A read that fails is the section's error state, and takes the page control with it")
    func failedRead() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        // Enough for a second page, so the read that fails is one that had something to lose: a
        // section left offering "show earlier sessions" over a failed read would walk from a cursor
        // pointing into a history it no longer has.
        for day in 1...6 {
            try await gym.train(squat, onDay: day, reps: [day])
        }
        let refusing = FlakyWorkoutRepository(wrapping: gym.workouts)

        let state = ExerciseHistoryState(
            exerciseID: squat.id, workouts: refusing, settings: gym.settings)
        await state.load()
        #expect(state.hasMore)

        await refusing.refuseSets(true)
        await state.load()

        #expect(ExerciseHistoryScreenState.current(state.phase) == .failed)
        #expect(state.hasMore == false)
    }

    @Test("An extension a fresh read overtook does not publish over it")
    func aSlowExtensionYields() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        for day in 1...6 {
            try await gym.train(squat, onDay: day, reps: [day])
        }
        let gate = GatedWorkoutRepository(wrapping: gym.workouts)
        let state = ExerciseHistoryState(
            exerciseID: squat.id, workouts: gate, settings: gym.settings)
        await state.load()

        // The extension is stopped inside the read that would produce day 1's group.
        await gate.gateNextEntriesRead()
        let extending = Task { await state.loadMore() }
        await gate.waitForArrival()

        // A workout is logged while it is stopped, and a fresh read picks it up — both surfaces fire
        // together on a return to this tab, which is what makes this a real sequence rather than a
        // contrived one.
        try await gym.train(squat, onDay: 7, reps: [7])
        await state.load()
        await gate.release()
        await extending.value

        // The newer read's page, intact. Without the guard the extension would splice day 1 onto
        // the rows it started from and publish [6, 5, 4, 3, 2, 1] — dropping day 7, the one session
        // the second read was run to pick up.
        #expect(
            state.groups.map(\.date)
                == [gym.day(7), gym.day(6), gym.day(5), gym.day(4), gym.day(3)])
        #expect(state.extendFailure == nil)
        #expect(state.hasMore)
    }

    @Test("A page that fails keeps the pages already shown")
    func failedExtension() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        for day in 1...6 {
            try await gym.train(squat, onDay: day, reps: [day])
        }
        let flaky = FlakyWorkoutRepository(wrapping: gym.workouts)

        let state = ExerciseHistoryState(
            exerciseID: squat.id, workouts: flaky, settings: gym.settings)
        await state.load()
        #expect(state.groups.count == ExerciseHistoryState.pageSize)

        await flaky.refuseEntries(true)
        await state.loadMore()

        // The five already built are still on screen, the failure is reported beside them, and the
        // control is still offered — the retry is another tap at the same command.
        #expect(state.groups.count == ExerciseHistoryState.pageSize)
        #expect(state.extendFailure != nil)
        #expect(state.hasMore)
        #expect(ExerciseHistoryScreenState.current(state.phase) == .ready)

        await flaky.refuseEntries(false)
        await state.loadMore()

        #expect(state.groups.count == 6)
        #expect(state.extendFailure == nil)
    }

    @Test("A re-read picks up a set logged since, and does not double the first page")
    func reReading() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        try await gym.train(squat, onDay: 1, reps: [5])

        let state = gym.history(of: squat)
        await state.load()
        #expect(state.groups.count == 1)

        try await gym.train(squat, onDay: 2, reps: [3])
        await state.load()

        #expect(state.groups.map(\.date) == [gym.day(2), gym.day(1)])
    }

    @Test("A repeated row is read once")
    func duplicatesAreDropped() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let twice = [
            Builder.session(id: id, date: stamp),
            Builder.session(id: id, date: stamp),
            Builder.session(id: UUID(), date: stamp),
        ]

        // G-2.5 forbids unique constraints, so two rows may carry one id — and this walk keys a
        // dictionary and a ForEach on it.
        #expect(ExerciseHistoryState.deduplicated(twice).count == 2)
    }

    @Test("A session with no start time sorts earliest in its own day")
    func untrackedSessionsSortFirst() {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let tracked = Builder.session(id: UUID(), date: day, startedAt: day)
        let untracked = Builder.session(id: UUID(), date: day, startedAt: nil)

        let ordered = ExerciseHistoryState.chronological([untracked, tracked])

        // Newest first, and nothing about a backdated session claims it happened after one that was
        // actually tracked — so it is last, not first.
        #expect(ordered.map(\.id) == [tracked.id, untracked.id])
    }
}
