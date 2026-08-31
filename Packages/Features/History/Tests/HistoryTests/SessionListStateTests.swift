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

    @Test("An exercise removed from a session leaves the row entirely (G-1.3)")
    func softDeletedEntriesAreExcluded() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let session = try await log.session(daysAgo: 0)
        let squats = try await log.entry(squat, in: session, order: 0)
        let benches = try await log.entry(bench, in: session, order: 1)
        try await log.set(in: squats, kilograms: 100, reps: 5)
        try await log.set(in: benches, kilograms: 80, reps: 5)
        try await log.repositories.workouts.deleteExerciseEntry(id: benches.id)

        let state = log.listState()
        await state.load()

        let row = try #require(state.summaries.first)
        // The removed exercise is not named — the half a `sets` read cannot cover, since deleting an
        // entry soft-deletes its sets and they would drop out either way.
        #expect(row.exerciseNames == ["Back Squat"])
        #expect(row.setCount == 1)
        #expect(row.tonnage == Weight(grams: 500_000))
    }

    @Test("A deleted exercise still names itself — history does not lose a row to a deletion")
    func softDeletedExercisesStillName() async throws {
        // `isArchived` and `deletedAt` are different columns and only the second is behind
        // `includingDeleted:`, so the archived case above cannot stand in for this one (`G-1.3`).
        //
        // The catalogue is a double rather than the fake stack, because no local write can produce
        // the row: `save` drops `deletedAt` on the way in and `ExerciseRepository` has no delete.
        // A deleted exercise reaches a store from a sync or a restore (`FR-1.11.3`) — foreign data,
        // which is the same population the duplicate-identifier and overflow guards are for.
        var log = TrainingLog()
        let live = try await log.exercise(named: "Back Squat")
        // Written live — the workout repository refuses an entry naming an exercise that is not
        // there — and then reported as deleted by the catalogue the screen reads. That split is the
        // foreign store: rows the sets reference, under a catalogue that has retired them.
        let stored = try await log.exercise(named: "Smith Machine Squat")
        let gone = TrainingLog.exercise(id: stored.id, named: stored.name, deleted: true)
        let session = try await log.session(daysAgo: 0)
        try await log.entry(live, in: session, order: 0)
        try await log.entry(stored, in: session, order: 1)

        let state = SessionListState(
            workouts: log.repositories.workouts,
            exercises: ForeignCatalogue(holding: [live, gone]),
            settings: log.repositories.settings
        )
        await state.load()

        #expect(
            try #require(state.summaries.first).exerciseNames
                == ["Back Squat", "Smith Machine Squat"])
    }

    @Test("A workout still in progress is a row: FR-1.5.1 is every session, not every finished one")
    func unfinishedSessionsAreListed() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let finished = try await log.session(daysAgo: 1)
        let inProgress = try await log.session(daysAgo: 0, isFinished: false)
        try await log.entry(squat, in: finished)
        let entry = try await log.entry(squat, in: inProgress)
        try await log.set(in: entry, kilograms: 100, reps: 5)

        let state = log.listState()
        await state.load()

        #expect(state.summaries.map(\.id) == [inProgress.id, finished.id])
        // Its numbers are what has been logged so far, not a placeholder for an unfinished one.
        #expect(try #require(state.summaries.first).tonnage == Weight(grams: 500_000))
    }

    @Test("Two catalogue rows under one identifier keep the first, rather than trapping (G-2.5)")
    func duplicateExerciseIdentifiersKeepTheFirst() {
        let id = UUID()
        let names = SessionListState.names(
            in: [
                TrainingLog.exercise(id: id, named: "Back Squat"),
                TrainingLog.exercise(id: id, named: "Front Squat"),
            ], as: .english)
        #expect(names == [id: "Back Squat"])
    }

    @Test("Two sessions under one identifier are one row, not a ForEach keyed on both (G-2.5)")
    func duplicateSessionIdentifiersAreOneRow() {
        let id = UUID()
        let repeated = [
            TrainingLog.session(id: id, daysAgo: 0),
            TrainingLog.session(id: id, daysAgo: 1),
        ]

        let rows = SessionListState.deduplicated(repeated)

        #expect(rows.count == 1)
        // The first is kept, which in a newest-first list is the newer of the pair.
        #expect(rows.first?.date == repeated[0].date)
        #expect(rows.first?.date != repeated[1].date)
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
