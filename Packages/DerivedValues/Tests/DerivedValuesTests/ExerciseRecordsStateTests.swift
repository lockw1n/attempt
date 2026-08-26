import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// The `@Observable` half (`TR-1.5`, `TR-1.2`): what a screen sees, and when.
@Suite("Exercise records state")
@MainActor
struct ExerciseRecordsStateTests {
    /// Waits for `condition`, or gives up — so a failure is an assertion rather than a hung suite.
    ///
    /// **Polling rather than a second stream.** The state is what is under test, and subscribing to
    /// the same announcements it does would assert that the announcement arrived, not that the state
    /// acted on it. The interval is short and the ceiling generous: on a green run this returns on
    /// the first or second pass.
    private func settle(
        until condition: @MainActor () -> Bool,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Waits until `recomputer` has `count` subscribers.
    ///
    /// `observeChanges()` subscribes inside a detached task, so a publish issued straight after
    /// starting one can reach an empty subscriber list. Every test below that publishes to a state
    /// goes through here first.
    private func awaitSubscriber(
        on recomputer: PersonalRecordRecomputer,
        count: Int = 1,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if await recomputer.subscriberCount >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A loaded state reports the exercise's rep maxes")
    func aLoadReportsTheRecords() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords)
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.failure == nil)
        #expect(state.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
    }

    /// **An exercise with no records and one nothing has looked at are both an empty list**, and a
    /// screen says opposite things about them — `FR-1.13.1`'s empty state versus its loading one.
    @Test("An exercise with no records loads empty rather than unloaded")
    func nothingLoggedIsLoadedAndEmpty() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords)
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        #expect(!state.hasLoaded)
        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.repMaxes.isEmpty)
    }

    /// `T-1.40`'s first *done when*: a completed set that sets a new 5RM reaches the cache and a
    /// subscribed state, with no rendering involved.
    @Test("A set that beats the 5RM reaches the cache and a subscribed state")
    func aNewRecordReachesASubscriber() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords)
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)
        await state.loadRecords()
        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)

        // The set is logged the way the app logs one — through the repository — and then announced,
        // which is exactly what `LoggedSetWriter` and `ActiveSessionStore` do around their writes.
        try await log.repositories.workouts.save(
            log.setEntry(entryID: entryID, order: 1, on: weeksAgo(2), working(120_000, 5)))
        await recomputer.setDidChange(inEntryID: entryID)

        await settle { state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000) }

        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000))
        let cached = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(cached.first { $0.repCount == 5 }?.weight == Weight(grams: 120_000))
    }

    /// `FR-1.6.4`'s scope on the read side: every logged set announces, and a screen that reloaded
    /// on all of them would walk this exercise's history because a different one was trained.
    @Test("A change to another exercise leaves this state alone")
    func anotherExerciseDoesNotReload() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        try await log.session(of: squat, on: weeksAgo(2), sets: [working(100_000, 5)])
        let benchEntry = try await log.session(
            of: bench, on: weeksAgo(2), sets: [working(70_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: counting, cache: log.repositories.personalRecords)
        let state = ExerciseRecordsState(exerciseID: squat, recomputer: recomputer)
        await state.loadRecords()

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)
        await counting.reset()
        await recomputer.setDidChange(inEntryID: benchEntry)

        // Long enough that a reload would have happened; the assertion is that none did.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counting.walkedExercises == [bench])
    }

    /// A rep max reads no setting at all, so nothing a formula picker does can move one — reloading
    /// the list on a formula change would be a walk for an answer that cannot have changed.
    @Test("A formula change reloads the estimate and not the records")
    func aFormulaChangeReloadsOnlyTheEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            formula: .epley)
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)
        await state.load()
        let recordsBefore = state.repMaxes
        let estimateBefore = try #require(state.estimatedMax)

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)
        await recomputer.formulaDidChange(to: .brzycki)

        await settle { state.estimatedMax != estimateBefore }

        #expect(state.estimatedMax != estimateBefore)
        #expect(state.repMaxes == recordsBefore)
    }

    @Test("A read that fails is reported as a diagnostic and does not claim records")
    func aFailedReadIsReported() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let recomputer = PersonalRecordRecomputer(
            workouts: RefusingWorkouts(failure: failure),
            cache: InMemoryRepositoryStack().personalRecords)
        let state = ExerciseRecordsState(exerciseID: UUID(), recomputer: recomputer)

        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.repMaxes.isEmpty)
        #expect(state.failure == String(describing: failure))
    }
}

/// A repository that refuses every read, for the diagnostic path.
struct RefusingWorkouts: WorkoutRepository {
    let failure: RepositoryError

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw failure }
    func save(_ entry: ExerciseEntry) async throws { throw failure }
    func deleteExerciseEntry(id: UUID) async throws { throw failure }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
    func save(_ set: SetEntry) async throws { throw failure }
    func deleteSet(id: UUID) async throws { throw failure }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
}
