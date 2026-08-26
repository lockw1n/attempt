import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

/// The search mode's reads (`FR-1.5.4`) — what a query returns out of a real store, which rows it
/// must not return, and the four states the screen draws.
@MainActor
@Suite("History search")
struct SessionSearchStateTests {
    @Test("An exercise name returns every session it was performed in, and only those")
    func exerciseNameReturnsEverySession() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        // Squats on four days; benching on exactly one of them plus one of its own.
        let squatDays = [0, 2, 5, 9]
        for day in squatDays {
            let session = try await log.session(daysAgo: day)
            try await log.entry(squat, in: session, order: 0)
            if day == 2 { try await log.entry(bench, in: session, order: 1) }
        }
        let benchOnly = try await log.session(daysAgo: 12)
        try await log.entry(bench, in: benchOnly, order: 0)

        let state = log.searchState()
        state.query = "squat"
        await state.load()

        // Four sessions for the exercise trained on four days, newest first.
        #expect(state.results.count == 4)
        #expect(state.results.map(\.summary.date) == state.results.map(\.summary.date).sorted(by: >))
        #expect(state.results.allSatisfy { $0.match.fields == .exerciseName })

        // …and exactly one for the exercise trained on two, minus the day it shared with squats.
        state.query = "bench"
        #expect(state.results.count == 2)
        state.query = "Bench Press"
        #expect(state.results.count == 2)
    }

    @Test("A session-level note and a per-set note both match, and each says which it was")
    func noteTextMatches() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")

        let noteDay = try await log.session(daysAgo: 0, notes: "Knee felt off today.")
        try await log.entry(squat, in: noteDay)

        let setNoteDay = try await log.session(daysAgo: 1)
        let entry = try await log.entry(squat, in: setNoteDay)
        try await log.set(in: entry, order: 0, kilograms: 100, reps: 5, notes: "Knee wrap on.")

        let state = log.searchState()
        state.query = "knee"
        await state.load()

        #expect(state.results.count == 2)
        let byDay = Dictionary(uniqueKeysWithValues: state.results.map { ($0.id, $0.match) })
        #expect(byDay[noteDay.id]?.fields == .sessionNote)
        #expect(byDay[noteDay.id]?.setNote == nil)
        #expect(byDay[setNoteDay.id]?.fields == .setNote)
        // The row shows nothing else the query is in, so the note itself has to reach it.
        #expect(byDay[setNoteDay.id]?.setNote == "Knee wrap on.")
    }

    @Test("A warmup's note is searchable — the tonnage partition is not the note partition")
    func warmupNotesAreSearchable() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(daysAgo: 0)
        let entry = try await log.entry(squat, in: session)
        try await log.set(
            in: entry, order: 0, kilograms: 60, reps: 5, isWarmup: true, notes: "Hips tight.")
        try await log.set(in: entry, order: 1, kilograms: 100, reps: 5)

        let state = log.searchState()
        state.query = "hips"
        await state.load()

        #expect(state.results.count == 1)
        #expect(state.results.first?.match.setNote == "Hips tight.")
        // The row's own numbers are still the working sets' — the note changed nothing about them.
        #expect(state.results.first?.summary.setCount == 1)
    }

    @Test("A soft-deleted session is not a result, and neither is a soft-deleted set's note")
    func softDeletedRowsAreExcluded() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")

        let kept = try await log.session(daysAgo: 0)
        let keptEntry = try await log.entry(squat, in: kept)
        try await log.set(in: keptEntry, order: 0, kilograms: 100, reps: 5, notes: "Belt on.")
        let removedSet = try await log.set(
            in: keptEntry, order: 1, kilograms: 105, reps: 3, notes: "Straps on.")

        let discarded = try await log.session(daysAgo: 1, notes: "Belt on.")
        try await log.entry(squat, in: discarded)

        try await log.repositories.workouts.deleteSet(id: removedSet.id)
        try await log.repositories.workouts.deleteSession(id: discarded.id)

        let state = log.searchState()
        state.query = "belt"
        await state.load()

        // Only the live session, matched on its live set's note.
        #expect(state.results.map(\.id) == [kept.id])

        // The deleted set's note is gone from the index entirely (`G-1.3`).
        state.query = "straps"
        #expect(state.results.isEmpty)
    }

    @Test("A retired exercise is still findable — archiving hides a picker row, not history")
    func archivedExercisesAreSearchable() async throws {
        var log = TrainingLog()
        let retired = try await log.exercise(named: "Smith Machine Squat", archived: true)
        let session = try await log.session(daysAgo: 0)
        try await log.entry(retired, in: session)

        let state = log.searchState()
        state.query = "smith"
        await state.load()

        #expect(state.results.map(\.id) == [session.id])
    }

    @Test("Two sessions sharing an identifier produce one row, as the list's rule requires")
    func duplicateIdentifiersAreDeduplicated() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let shared = UUID()
        // A store this app did not write: `G-2.5` forbids unique constraints, so a sync or a
        // restore can put two rows on one identifier. A `ForEach` over the results renders neither
        // of the pair correctly, which is why search deduplicates on the same rule the list does.
        let newer = TrainingLog.session(id: shared, daysAgo: 0, notes: "Squat day.")
        let older = TrainingLog.session(id: shared, daysAgo: 4, notes: "Squat day.")
        try await log.repositories.workouts.save(newer)
        try await log.entry(squat, in: newer)

        let state = log.searchState(
            workouts: ForeignWorkoutLog(
                holding: [newer, older], over: log.repositories.workouts))
        state.query = "squat"
        await state.load()

        // One row, and it is the newer of the pair — the first the repository handed over.
        #expect(state.results.count == 1)
        #expect(state.results.first?.summary.date == newer.date)
    }

    @Test("Whitespace alone is not a search, and nothing is read for it")
    func whitespaceIsNoSearch() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let state = log.searchState()
        state.query = "   "
        #expect(!state.isSearching)

        await state.loadIfSearching()
        #expect(state.phase == .idle)
        #expect(state.results.isEmpty)
    }

    @Test("Surrounding whitespace does not stop a query from matching")
    func queriesAreTrimmed() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let state = log.searchState()
        state.query = "  squat  "
        #expect(state.isSearching)
        await state.load()

        #expect(state.results.count == 1)
    }

    @Test("A query that matched nothing is its own state, not the list's empty one")
    func nothingMatched() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let state = log.searchState()
        state.query = "deadlift"
        await state.load()

        #expect(state.results.isEmpty)
        #expect(
            SessionSearchScreenState.current(state.phase, hasResults: false) == .empty)
    }

    @Test("A refused read is the failed state, and running again is the retry")
    func failedRead() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let state = log.searchState(workouts: FailingWorkoutRepository())
        state.query = "squat"
        await state.load()

        #expect(SessionSearchScreenState.current(state.phase, hasResults: false) == .failed)
        #expect(state.results.isEmpty)

        // The retry is the same call against a store that answers.
        let working = log.searchState()
        working.query = "squat"
        await working.load()
        #expect(working.results.count == 1)
    }

    @Test("Before the walk answers, the screen is loading rather than empty")
    func loadingBeforeTheWalkAnswers() {
        #expect(SessionSearchScreenState.current(.idle, hasResults: false) == .loading)
        #expect(SessionSearchScreenState.current(.indexing, hasResults: false) == .loading)
        #expect(SessionSearchScreenState.current(.indexed([]), hasResults: true) == .ready)
    }

    @Test("The unit a result's tonnage reads in is the stored one (`G-3.1`)")
    func displayUnitIsRead() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))
        try await log.setDisplayUnit(.pounds)

        let state = log.searchState()
        #expect(state.displayUnit == .kilograms)

        state.query = "squat"
        await state.load()
        #expect(state.displayUnit == .pounds)
    }

    @Test("A search is re-read rather than cached, so training logged in between is findable")
    func theIndexIsRebuilt() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 1))

        let state = log.searchState()
        state.query = "squat"
        await state.load()
        #expect(state.results.count == 1)

        try await log.entry(squat, in: try await log.session(daysAgo: 0))
        await state.load()
        #expect(state.results.count == 2)
    }
}
