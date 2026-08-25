import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

/// The session list's reads (`FR-1.5.1`, `NFR-1.5`) — order, the summary line, the states, and the
/// paging that keeps the whole history from being summarised at once.
@MainActor
@Suite("Session list")
struct SessionListStateTests {
    @Test("Sessions are newest first, and the list is the repository's order rather than a re-sort")
    func newestFirst() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in [3, 1, 7, 0] {
            let session = try await log.session(daysAgo: day)
            try await log.entry(squat, in: session)
        }

        let state = log.listState()
        await state.load()

        let dates = state.summaries.map(\.date)
        #expect(dates.count == 4)
        #expect(dates == dates.sorted(by: >))
        #expect(dates.first == TrainingLog.epoch)
    }

    @Test("A row carries the day, what was trained, the working sets and what they weighed")
    func summaryLine() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let session = try await log.session(daysAgo: 0, notes: "Felt heavy.")
        let squats = try await log.entry(squat, in: session, order: 0)
        let benches = try await log.entry(bench, in: session, order: 1)
        try await log.set(in: squats, order: 0, kilograms: 60, reps: 5, isWarmup: true)
        try await log.set(in: squats, order: 1, kilograms: 100, reps: 5)
        try await log.set(in: squats, order: 2, kilograms: 100, reps: 5)
        try await log.set(in: benches, order: 0, kilograms: 80, reps: 3)

        let state = log.listState()
        await state.load()

        let row = try #require(state.summaries.first)
        #expect(row.id == session.id)
        #expect(row.date == session.date)
        #expect(row.exerciseNames == ["Back Squat", "Bench Press"])
        // Three working sets: the warmup is in neither number.
        #expect(row.setCount == 3)
        // 500 + 500 + 240, by hand.
        #expect(row.tonnage == Weight(grams: 1_240_000))
        #expect(row.notes == "Felt heavy.")
    }

    @Test("Exercises read in entry order, and one performed twice is named once")
    func exerciseNamesAreOrderedAndDeduplicated() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let session = try await log.session(daysAgo: 0)
        // Squats, then benches, then back-off squats — three entries, two exercises.
        try await log.entry(squat, in: session, order: 0)
        try await log.entry(bench, in: session, order: 1)
        try await log.entry(squat, in: session, order: 2)

        let state = log.listState()
        await state.load()

        #expect(try #require(state.summaries.first).exerciseNames == ["Back Squat", "Bench Press"])
    }

    @Test("A retired exercise still names itself — history does not lose a row to an archive")
    func archivedExercisesStillName() async throws {
        var log = TrainingLog()
        let retired = try await log.exercise(named: "Smith Machine Squat", archived: true)
        let session = try await log.session(daysAgo: 0)
        try await log.entry(retired, in: session)

        let state = log.listState()
        await state.load()

        #expect(try #require(state.summaries.first).exerciseNames == ["Smith Machine Squat"])
    }

    @Test("A session with nothing logged into it is a row, not an omission")
    func emptySessionIsStillARow() async throws {
        let log = TrainingLog()
        try await log.session(daysAgo: 0)

        let state = log.listState()
        await state.load()

        let row = try #require(state.summaries.first)
        #expect(row.exerciseNames.isEmpty)
        #expect(row.setCount == 0)
        #expect(row.tonnage == .zero)
        // A row, so the screen is not empty — `FR-1.13.2`'s guidance would be wrong here.
        #expect(SessionListScreenState.current(state.phase) == .ready)
    }

    @Test("A discarded session is not in the list (G-1.3)")
    func softDeletedSessionsAreExcluded() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let kept = try await log.session(daysAgo: 1)
        let discarded = try await log.session(daysAgo: 0)
        try await log.entry(squat, in: kept)
        try await log.entry(squat, in: discarded)
        try await log.repositories.workouts.deleteSession(id: discarded.id)

        let state = log.listState()
        await state.load()

        #expect(state.summaries.map(\.id) == [kept.id])
    }

    @Test("A deleted set leaves the session but not the tonnage")
    func softDeletedSetsAreExcluded() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(daysAgo: 0)
        let entry = try await log.entry(squat, in: session)
        try await log.set(in: entry, order: 0, kilograms: 100, reps: 5)
        let removed = try await log.set(in: entry, order: 1, kilograms: 100, reps: 5)
        try await log.repositories.workouts.deleteSet(id: removed.id)

        let state = log.listState()
        await state.load()

        let row = try #require(state.summaries.first)
        #expect(row.setCount == 1)
        #expect(row.tonnage == Weight(grams: 500_000))
    }

    @Test("Nothing logged is the empty state, not an empty list of rows")
    func nothingLoggedIsEmpty() async throws {
        let state = TrainingLog().listState()
        await state.load()

        #expect(state.summaries.isEmpty)
        #expect(SessionListScreenState.current(state.phase) == .empty)
        #expect(state.hasMore == false)
    }

    @Test("A read that fails is the error state, and load() from there is the retry")
    func failedReadIsRecoverable() async throws {
        let log = TrainingLog()
        let state = SessionListState(
            workouts: FailingWorkoutRepository(),
            exercises: log.repositories.exercises,
            settings: log.repositories.settings
        )
        await state.load()

        #expect(SessionListScreenState.current(state.phase) == .failed)
        #expect(state.summaries.isEmpty)

        // The retry is the same call, and it still fails — what is being pinned is that the state
        // is re-enterable rather than stuck in `.loading`.
        await state.load()
        #expect(SessionListScreenState.current(state.phase) == .failed)
    }

    @Test("Before the first read the screen is loading, not empty")
    func idleIsLoading() {
        #expect(SessionListScreenState.current(TrainingLog().listState().phase) == .loading)
    }

    @Test("The unit is the settings row's, not a hardcoded default")
    func displayUnitComesFromSettings() async throws {
        let log = TrainingLog()
        let stored = try await log.repositories.settings.settings()
        try await log.repositories.settings.save(
            UserSettings(
                id: stored.id,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                deletedAt: stored.deletedAt,
                userID: stored.userID,
                displayUnit: .pounds,
                e1RMFormula: stored.e1RMFormula,
                theme: stored.theme,
                defaultRoundingIncrement: stored.defaultRoundingIncrement,
                defaultRoundingStrategy: stored.defaultRoundingStrategy
            ))

        let state = log.listState()
        #expect(state.displayUnit == .kilograms)
        await state.load()
        #expect(state.displayUnit == .pounds)
    }
}

/// `NFR-1.5`: the list summarises a page at a time, so nothing about it is quadratic in a history's
/// size before T-1.83 gets to measure it.
@MainActor
@Suite("Session list paging")
struct SessionListPagingTests {
    @Test("The first read summarises one page, not the whole history")
    func firstReadIsOnePage() async throws {
        let log = try await Self.history(sessions: SessionListState.pageSize + 5)

        let state = log.listState()
        await state.load()

        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.hasMore)
        #expect(SessionListScreenState.current(state.phase) == .ready)
    }

    @Test("A history of 20+ sessions loads whole, newest first, one page at a time")
    func extendingReachesTheEnd() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)

        let state = log.listState()
        await state.load()
        await state.loadMore()

        #expect(state.summaries.count == total)
        #expect(state.hasMore == false)
        let dates = state.summaries.map(\.date)
        #expect(dates == dates.sorted(by: >))
        // Every row is distinct: a page built from the wrong offset repeats one.
        #expect(Set(state.summaries.map(\.id)).count == total)
    }

    @Test("loadMore() at the end of the list does nothing rather than re-reading")
    func extendingPastTheEndIsANoOp() async throws {
        let log = try await Self.history(sessions: 3)

        let state = log.listState()
        await state.load()
        let rows = state.summaries
        await state.loadMore()

        #expect(state.summaries == rows)
        #expect(state.extendFailure == nil)
    }

    @Test("A page that fails leaves the rows already on screen, and says so beside them")
    func extendFailureKeepsWhatLoaded() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)
        // Fails only once the first page is built, which is the case the separate property exists
        // for: a screen full of sessions must not be replaced by "History unavailable".
        let flaky = FlakyWorkoutRepository(
            wrapping: log.repositories.workouts, failingAfter: SessionListState.pageSize)
        let state = SessionListState(
            workouts: flaky,
            exercises: log.repositories.exercises,
            settings: log.repositories.settings
        )

        await state.load()
        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.extendFailure == nil)

        await state.loadMore()
        #expect(SessionListScreenState.current(state.phase) == .ready)
        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.extendFailure != nil)
        #expect(state.hasMore)
    }

    /// `count` sessions, one exercise and one working set in each, one day apart.
    ///
    /// - Parameter count: How many to write.
    /// - Returns: The store.
    private static func history(sessions count: Int) async throws -> TrainingLog {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in 0..<count {
            let session = try await log.session(daysAgo: day)
            let entry = try await log.entry(squat, in: session)
            try await log.set(in: entry, kilograms: 100, reps: 5)
        }
        return log
    }
}

/// A workout repository that refuses everything, for the failed-read state.
private struct FailingWorkoutRepository: WorkoutRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
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

/// A repository that answers normally until it has summarised `limit` sessions, then refuses.
///
/// It counts `entries(forSessionID:)`, which is the first call a summary makes, so the cut falls
/// between two rows rather than halfway through one.
private final class FlakyWorkoutRepository: WorkoutRepository, @unchecked Sendable {
    private let wrapped: any WorkoutRepository
    private let limit: Int
    private var summarised = 0

    init(wrapping wrapped: any WorkoutRepository, failingAfter limit: Int) {
        self.wrapped = wrapped
        self.limit = limit
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        guard summarised < limit else { throw RepositoryError.recordNotFound(id: sessionID) }
        summarised += 1
        return try await wrapped.entries(
            forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
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
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}
