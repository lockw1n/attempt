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
        let press = try await log.exercise(named: "Overhead Press")
        // The two multiplicities the claim is about: squats on four days, benching on exactly one
        // of them. The press has a day to itself so that "and only those" has a session to leave
        // out rather than only the ones it shares.
        let squatDays = [0, 2, 5, 9]
        for day in squatDays {
            let session = try await log.session(daysAgo: day)
            try await log.entry(squat, in: session, order: 0)
            if day == 2 { try await log.entry(bench, in: session, order: 1) }
        }
        try await log.entry(press, in: try await log.session(daysAgo: 12), order: 0)

        let state = log.searchState()
        state.query = "squat"
        await state.load()

        // Four sessions for the exercise trained on four days, newest first.
        #expect(state.results.count == 4)
        #expect(state.results.map(\.summary.date) == state.results.map(\.summary.date).sorted(by: >))
        #expect(state.results.allSatisfy { $0.match.fields == .exerciseName })

        // …and exactly one for the exercise trained on exactly one day, which is the day it shared
        // with a squat rather than one of its own: a count keyed on the exercise, not on the row.
        state.query = "bench"
        #expect(state.results.count == 1)
        state.query = "Bench Press"
        #expect(state.results.count == 1)
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

    @Test("A superseded walk neither wedges the next search nor publishes over its answer")
    func supersededWalkDoesNotPublish() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        // Held with the walk suspended inside the read, and refusing once released — which is what
        // a store that reports a cancellation as an error looks like from up here.
        let gate = GatedWorkoutRepository(
            wrapping: log.repositories.workouts, holdingRead: 1, failsHeldRead: true)
        let state = log.searchState(workouts: gate)
        state.query = "squat"

        // The keystroke that starts a search, the field emptied — which cancels that walk without
        // waiting for it to unwind — and the keystroke that starts the next one, all while the
        // first is still standing in a read it will return from eventually.
        let abandoned = Task { await state.load() }
        await gate.arrival()
        abandoned.cancel()
        await state.load()

        // The second walk answered. A refusal to start one while another is in flight would have
        // left this on a spinner that no later keystroke could clear.
        #expect(state.results.count == 1)

        await gate.release()
        await abandoned.value

        // And the first reports its refusal to nobody.
        #expect(state.results.count == 1)
        #expect(
            SessionSearchScreenState.current(state.phase, hasResults: !state.results.isEmpty)
                == .ready)
    }

    @Test("A cancelled walk publishes nothing, not even the index it had finished building")
    func cancelledWalkPublishesNothing() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in [0, 1] {
            try await log.entry(squat, in: try await log.session(daysAgo: day))
        }

        // Held on the *last* session's read, so the walk has a complete index in hand by the time
        // it is let go: what refuses it is the check before the publish, the one in the loop having
        // no iteration left to run.
        let gate = GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: 2)
        let state = log.searchState(workouts: gate)
        state.query = "squat"

        let cancelled = Task { await state.load() }
        await gate.arrival()
        cancelled.cancel()
        await gate.release()
        await cancelled.value

        #expect(state.phase == .indexing)
        #expect(state.results.isEmpty)

        // Nor does what it left behind stop the next search: a walk supersedes, it is not refused.
        await state.load()
        #expect(state.results.count == 2)
    }

    @Test("A walk another overtook publishes nothing, though nothing cancelled it")
    func overtakenWalkDoesNotPublish() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let gate = GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: 1)
        let state = log.searchState(workouts: gate)
        state.query = "squat"

        // Held after its session read, so this walk's answer is the one-session history.
        let overtaken = Task { await state.load() }
        await gate.arrival()

        // A workout is logged and a second walk picks it up. Nothing cancelled the first — the
        // retry on the failed state runs in a task of its own, which the screen's trigger does not
        // reach — so being stale is the only thing that can stop it publishing.
        try await log.entry(squat, in: try await log.session(daysAgo: 1))
        await state.load()
        #expect(state.results.count == 2)

        await gate.release()
        await overtaken.value

        // The older answer does not come back and take the newer session off the screen.
        #expect(state.results.count == 2)
    }

    @Test("A walk the field emptied under publishes nothing, though nothing cancelled it")
    func walkEmptiedUnderDoesNotPublish() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let gate = GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: 1)
        let state = log.searchState(workouts: gate)
        state.query = "squat"

        let abandoned = Task { await state.load() }
        await gate.arrival()

        // The user gives up on the search. This walk is not the screen's, so nothing cancels it.
        state.clear()
        await state.loadIfSearching()

        await gate.release()
        await abandoned.value

        // The index it built does not arrive after the screen stopped asking for one.
        #expect(state.phase == .idle)
        #expect(state.results.isEmpty)
    }

    @Test("A cancelled walk stops reading rather than finishing a history nobody is waiting for")
    func cancelledWalkStopsReading() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in [0, 1, 2] {
            try await log.entry(squat, in: try await log.session(daysAgo: day))
        }

        let gate = GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: 1)
        let state = log.searchState(workouts: gate)
        state.query = "squat"

        let cancelled = Task { await state.load() }
        await gate.arrival()
        cancelled.cancel()
        await gate.release()
        await cancelled.value

        // Work not done is the only thing that can assert an early exit — the refusal to publish
        // looks the same whether the walk stopped at the first session or ran through all three,
        // and at `NFR-1.5`'s 15,000 sets the difference is the whole point of checking.
        #expect(await gate.entryReads == 1)
    }

    @Test("Emptying the field drops the index rather than leaving the history in memory")
    func emptyingTheFieldDropsTheIndex() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.entry(squat, in: try await log.session(daysAgo: 0))

        let state = log.searchState()
        state.query = "squat"
        await state.load()
        #expect(state.results.count == 1)

        // `clear()` and the search field's own button are the same thing from here: both empty the
        // query, and the screen's trigger fires on that rather than on either button.
        state.clear()
        await state.loadIfSearching()

        #expect(!state.isSearching)
        #expect(state.phase == .idle)
        #expect(state.results.isEmpty)
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
