import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Editing and deleting a set that is already logged (`FR-1.2.7`, `G-1.3`, `G-2.4`, `NFR-1.8`).
///
/// A suite of its own beside the marking one, for that suite's reason: a different requirement, and
/// the two together would outgrow `type_body_length`.
@Suite("Session set editing")
struct SessionSetEditingTests {
    @Test("Editing rewrites the five fields the editor collects, and writes them through")
    func editingRewritesTheEditableFields() async throws {
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))

        await workout.store.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 3, rpe: 9, isWarmup: true, notes: "belt on")
        )

        let held = try #require(workout.store.exercises.first?.sets.first)
        #expect(held.weight == Weight(grams: 102_500))
        #expect(held.reps == 3)
        #expect(held.rpe == 9)
        #expect(held.isWarmup == true)
        #expect(held.notes == "belt on")
        #expect(workout.store.exercisesWriteFailure == nil)
        // NFR-1.8: in the store, not only in the list on screen.
        let stored = try #require(await workout.storedSets(inEntryID: logged.entryID).first)
        #expect(stored.weight == Weight(grams: 102_500))
        #expect(stored.reps == 3)
        #expect(stored.notes == "belt on")
    }

    @Test("Editing changes nothing else about the set")
    func editingCarriesEveryOtherFieldAcross() async throws {
        let workout = try await Workout.started()
        let first = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true, notes: ""))
        let before = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: 8, isWarmup: false, notes: ""))

        await workout.store.editSet(
            id: before.id,
            inEntryID: before.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 105_000), reps: 4, rpe: nil, isWarmup: false, notes: "")
        )

        let after = try #require(workout.store.exercises.first?.sets.last)
        #expect(after.id == before.id)
        #expect(after.entryID == before.entryID)
        #expect(after.createdAt == before.createdAt)
        // The position stays: the card decides where a set sits, and the form does not offer it.
        #expect(after.order == before.order)
        #expect(after.order != first.order)
        // FR-1.2.5's outcome has its own control, and `completedAt` records that the set was
        // tracked live — which editing it afterwards does not undo.
        #expect(after.isCompleted == before.isCompleted)
        #expect(after.completedAt == before.completedAt)
        // OUT-1.1: nothing in Phase 1 fills either target column, and an edit must not start.
        #expect(after.targetWeight == nil)
        #expect(after.targetReps == nil)
        #expect(after.rir == before.rir)
        #expect(after.modifiers == before.modifiers)
        #expect(after.deletedAt == nil)
    }

    @Test("Confirming an edit that changes nothing writes nothing — G-2.4's conflict key")
    func editingToTheSameValuesIsANoOp() async throws {
        let workout = try await Workout.started()
        let values = SetEntryValues(
            weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false, notes: "belt on")
        let before = try await workout.logSet(values)

        await workout.store.editSet(id: before.id, inEntryID: before.entryID, to: values)

        // Every save restamps `updatedAt`, which is G-2.4's conflict key — so a write that changed
        // nothing would let a no-op local edit outrank a real remote one. Opening the editor and
        // confirming it untouched is the ordinary way to reach this.
        let unchanged = try #require(workout.store.exercises.first?.sets.first)
        #expect(unchanged.updatedAt == before.updatedAt)

        // The other half of the same claim: a real edit *does* move the timestamp, so the assertion
        // above is reading the write rather than a clock too coarse to tell two saves apart.
        await workout.store.editSet(
            id: before.id,
            inEntryID: before.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 105_000), reps: 5, rpe: 8, isWarmup: false, notes: "belt on")
        )
        let edited = try #require(workout.store.exercises.first?.sets.first)
        #expect(edited.updatedAt > before.updatedAt)
    }

    @Test("A failed set takes the reps actually achieved — FR-1.2.5's other half")
    func failedSetTakesTheAchievedReps() async throws {
        // The correction T-1.24 could not build: `reps` is already the achieved count, typed as the
        // set is logged, but a lifter who went for five, got three and marked the set failed had no
        // way to bring the number down. Two edits, deliberately — the outcome and the count are
        // separate facts and separate controls.
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 140_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        await workout.store.markSet(id: logged.id, inEntryID: logged.entryID, isCompleted: false)

        await workout.store.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 140_000), reps: 3, rpe: nil, isWarmup: false, notes: "")
        )

        let corrected = try #require(workout.store.exercises.first?.sets.first)
        #expect(corrected.reps == 3)
        // Still failed: correcting the count is not un-failing the set.
        #expect(corrected.isCompleted == false)
        // And still no target to have fallen short of — FR-1.6.1 reads `reps`, never `targetReps`.
        #expect(corrected.targetReps == nil)
    }

    @Test("Editing a set that is no longer there reports nothing and sweeps the row")
    func editingAMissingSetIsSilentlyNothing() async throws {
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        // Deleted underneath the card — which is what a second device, or a second tap, does.
        try await workout.repositories.workouts.deleteSet(id: logged.id)

        await workout.store.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 105_000), reps: 5, rpe: nil, isWarmup: false, notes: "")
        )

        // No diagnostic: a failure reported against a set the user can no longer see says nothing
        // they can act on. The re-read is what takes the row off the card, and it runs whether or
        // not anything was written.
        #expect(workout.store.exercisesWriteFailure == nil)
        #expect(workout.store.exercises.first?.sets.isEmpty == true)
    }

    @Test("Deleting a set is soft — the row survives and stops being read")
    func deletingIsSoft() async throws {
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))

        await workout.store.deleteSet(id: logged.id, inEntryID: logged.entryID)

        #expect(workout.store.exercises.first?.sets.isEmpty == true)
        #expect(workout.store.exercisesWriteFailure == nil)
        #expect(await workout.storedSets(inEntryID: logged.entryID).isEmpty)
        // G-1.3: soft, so the row is still there for anything that asks for it — and only an
        // explicit purge removes it.
        let all = try await workout.repositories.workouts.sets(
            forEntryID: logged.entryID, includingDeleted: true)
        #expect(all.map(\.id) == [logged.id])
        #expect(all.first?.deletedAt != nil)
    }

    @Test("Deleting a set that is already gone reports nothing")
    func deletingAMissingSetIsSilentlyNothing() async throws {
        // The repository raises `recordNotFound` for a row that is not live, and a screen whose only
        // remaining move is to re-read has nothing to do with that. Two thumbs on one confirmation
        // is the ordinary way here.
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        try await workout.repositories.workouts.deleteSet(id: logged.id)

        await workout.store.deleteSet(id: logged.id, inEntryID: logged.entryID)

        #expect(workout.store.exercisesWriteFailure == nil)
        #expect(workout.store.exercises.first?.sets.isEmpty == true)
    }

    @Test("Neither command writes with no workout in progress")
    func noWorkoutNoEditingAndNoDeleting() async throws {
        // The set has to be a real stored row and the store has to have let go of the workout it
        // belongs to — a store that never held one reads nothing back either way, which would make
        // the guard unfalsifiable. Same shape, and same measured reason, as the marking suite's.
        let workout = try await Workout.started()
        let logged = try await workout.logSet(
            SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        await workout.store.finish()
        #expect(workout.store.session == nil)

        await workout.store.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 200_000), reps: 1, rpe: nil, isWarmup: true, notes: "no")
        )
        await workout.store.deleteSet(id: logged.id, inEntryID: logged.entryID)

        // The row is untouched — finishing keeps it — and nothing is reported.
        let stored = try #require(await workout.storedSets(inEntryID: logged.entryID).first)
        #expect(stored == logged)
        #expect(workout.store.exercisesWriteFailure == nil)
    }

    @Test("The sets left after a deletion renumber, because the number was never stored")
    func deletingRenumbersWhatIsLeft() async throws {
        let workout = try await Workout.started()
        var logged: [SetEntry] = []
        for reps in [5, 4, 3] {
            let values = SetEntryValues(
                weight: Weight(grams: 100_000), reps: reps, rpe: nil, isWarmup: false, notes: "")
            logged.append(try await workout.logSet(values))
        }

        await workout.store.deleteSet(id: logged[0].id, inEntryID: logged[0].entryID)

        // `order` keeps the gap the soft delete left — 1 and 2, never renumbered — and the numbers
        // on the card do not, because they are derived (`G-1.4`).
        let remaining = try #require(workout.store.exercises.first?.sets)
        #expect(remaining.map(\.order) == [1, 2])
        #expect(SetNumbering.numbered(remaining).map(\.number) == [1, 2])
    }
}

/// `FR-1.2.7`'s other half: a set logged in a workout that finished weeks ago.
///
/// **These go through ``LoggedSetWriter`` and not through the store**, which is the point of the
/// type existing: `ActiveSessionStore` is the workout in progress and every command on it is gated
/// on holding one, where a past session is reached from History with no workout in progress at all.
@Suite("Editing a past session's sets")
struct PastSessionSetEditingTests {
    @Test("A set three sessions ago is edited, and no other session moves")
    func editingAPastSetLeavesEverySessionAlone() async throws {
        let history = try await TrainingHistory.threeSessions()
        let target = try #require(history.sets(inSession: 0).first)
        let untouched = try await history.everySet(exceptInSession: 0)

        let wrote = try await history.writer.edit(
            id: target.id,
            inEntryID: target.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 150_000), reps: 2, rpe: 9.5, isWarmup: false, notes: "PR")
        )

        #expect(wrote)
        let edited = try #require(await history.stored(id: target.id, inEntryID: target.entryID))
        #expect(edited.weight == Weight(grams: 150_000))
        #expect(edited.reps == 2)
        #expect(edited.rpe == 9.5)
        #expect(edited.notes == "PR")
        // FR-1.6.4's scope, in the negative: an edit reaches one row. Compared whole, so a moved
        // `updatedAt` on a neighbouring session — which would outrank a real remote edit by G-2.4 —
        // fails this too.
        #expect(try await history.everySet(exceptInSession: 0) == untouched)
    }

    @Test("The set beside it in the same session does not move either")
    func editingAPastSetLeavesItsNeighbourAlone() async throws {
        let history = try await TrainingHistory.threeSessions()
        let sets = history.sets(inSession: 1)
        let target = try #require(sets.first)
        let neighbour = try #require(sets.last)

        try await history.writer.edit(
            id: target.id,
            inEntryID: target.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 90_000), reps: 8, rpe: nil, isWarmup: false, notes: "")
        )

        #expect(try await history.stored(id: neighbour.id, inEntryID: neighbour.entryID) == neighbour)
    }

    @Test("Deleting a past session's set soft-deletes exactly that row")
    func deletingAPastSetIsSoftAndLocal() async throws {
        let history = try await TrainingHistory.threeSessions()
        let target = try #require(history.sets(inSession: 2).first)
        let untouched = try await history.everySet(exceptInSession: 2)

        let deleted = try await history.writer.delete(id: target.id, inEntryID: target.entryID)

        #expect(deleted)
        #expect(try await history.stored(id: target.id, inEntryID: target.entryID) == nil)
        #expect(try await history.everySet(exceptInSession: 2) == untouched)
        // G-1.3, and the read path's own default: nothing is removed, and the call site has to say
        // it wants the deleted rows to see this one.
        let all = try await history.repositories.workouts.sets(
            forEntryID: target.entryID, includingDeleted: true)
        #expect(all.first(where: { $0.id == target.id })?.deletedAt != nil)
    }

    @Test("Neither call reports a set it cannot find")
    func aMissingSetIsNotWritten() async throws {
        let history = try await TrainingHistory.threeSessions()
        let entry = try #require(history.sets(inSession: 0).first).entryID

        let edited = try await history.writer.edit(
            id: UUID(),
            inEntryID: entry,
            to: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: "")
        )
        let deleted = try await history.writer.delete(id: UUID(), inEntryID: entry)

        #expect(!edited)
        #expect(!deleted)
    }
}

// MARK: - Fixtures

extension Workout {
    /// Adds an exercise if there is none, logs `values` against it and returns the stored row.
    ///
    /// - Parameter values: What the set records.
    /// - Returns: The set as it was written.
    fileprivate func logSet(_ values: SetEntryValues) async throws -> SetEntry {
        if store.exercises.isEmpty {
            await store.addExercise(id: squat.id)
        }
        let entry = try #require(store.exercises.first)
        await store.addSet(toEntryID: entry.id, values: values)
        return try #require(store.exercises.first?.sets.last)
    }

    /// The entry's live sets, as the store reads them.
    ///
    /// - Parameter entryID: The exercise entry.
    /// - Returns: Its sets, soft-deleted ones excluded.
    fileprivate func storedSets(inEntryID entryID: UUID) async -> [SetEntry] {
        (try? await repositories.workouts.sets(forEntryID: entryID, includingDeleted: false)) ?? []
    }
}

/// Three finished workouts and the sets logged in them — a history with no workout in progress.
private struct TrainingHistory {
    /// The store the sets live in.
    let repositories: InMemoryRepositoryStack

    /// What performs the edit and the deletion.
    let writer: LoggedSetWriter

    /// One exercise entry per workout, newest first — the order the repository answers sessions in.
    let entries: [ExerciseEntry]

    /// That entry's sets, in the same order.
    let sets: [[SetEntry]]

    /// Three workouts a week apart, each finished, each with two sets logged against one exercise.
    ///
    /// - Returns: The history.
    static func threeSessions() async throws -> TrainingHistory {
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await Workout.seed(into: repositories)
        var entries: [ExerciseEntry] = []
        var sets: [[SetEntry]] = []
        for week in 0..<3 {
            let entry = try await workout(
                weeksAgo: week, exerciseID: catalogue[week].id, in: repositories)
            entries.append(entry)
            sets.append(
                try await repositories.workouts.sets(forEntryID: entry.id, includingDeleted: false))
        }
        return TrainingHistory(
            repositories: repositories,
            writer: LoggedSetWriter(repository: repositories.workouts),
            entries: entries,
            sets: sets
        )
    }

    /// One finished workout, with one exercise in it and two sets logged against that.
    ///
    /// - Parameters:
    ///   - week: How many weeks ago it was trained.
    ///   - exerciseID: The catalogue row the entry names.
    ///   - repositories: Where it is written.
    /// - Returns: The exercise entry, which is what the sets are read by.
    private static func workout(
        weeksAgo week: Int, exerciseID: UUID, in repositories: InMemoryRepositoryStack
    ) async throws -> ExerciseEntry {
        let day = Date(timeIntervalSince1970: 1_700_000_000 - Double(week) * 604_800)
        let session = WorkoutSession(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            date: day,
            startedAt: day,
            // Finished, which is what makes each of these a *past* session: nothing in the app
            // would resume one, and no store holds it.
            endedAt: day.addingTimeInterval(3600),
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exerciseID,
            order: 0,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        for position in 0..<2 {
            try await repositories.workouts.save(
                SetEntry(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    entryID: entry.id,
                    order: position,
                    weight: Weight(grams: 100_000 + week * 2_500),
                    reps: 5,
                    rpe: 8,
                    rir: nil,
                    isWarmup: false,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: day
                ))
        }
        return entry
    }

    /// The sets logged in one of the three workouts, as they were written.
    ///
    /// - Parameter index: `0` is the oldest — three sessions ago.
    /// - Returns: Its sets.
    func sets(inSession index: Int) -> [SetEntry] {
        sets[index]
    }

    /// One set as it is stored now, or `nil` if it is no longer live.
    ///
    /// - Parameters:
    ///   - id: The set.
    ///   - entryID: The entry it belongs to.
    /// - Returns: The stored row.
    func stored(id: UUID, inEntryID entryID: UUID) async throws -> SetEntry? {
        try await repositories.workouts
            .sets(forEntryID: entryID, includingDeleted: false)
            .first { $0.id == id }
    }

    /// Every live set in the other two workouts, whole rather than by field.
    ///
    /// - Parameter index: The workout to leave out.
    /// - Returns: Their sets.
    func everySet(exceptInSession index: Int) async throws -> [SetEntry] {
        var others: [SetEntry] = []
        for (position, entry) in entries.enumerated() where position != index {
            others += try await repositories.workouts.sets(
                forEntryID: entry.id, includingDeleted: false)
        }
        return others
    }
}
