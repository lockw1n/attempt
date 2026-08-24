import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Marking a set completed or failed, and what the store writes when it does (`FR-1.2.5`, `G-1.8`,
/// `G-2.4`, `NFR-1.8`).
///
/// A suite of its own beside `SessionSetMarkingTests`, for that suite's reason: a different
/// requirement, and the two together outgrow `type_body_length`.
@Suite("Session set outcome")
struct SessionSetOutcomeTests {
    @Test("Marking a logged set failed is written through")
    func failingIsWrittenThrough() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 3, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)
        #expect(logged.isCompleted == true)

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isCompleted: false)

        #expect(workout.store.exercises.first?.sets.first?.isCompleted == false)
        #expect(workout.store.exercisesWriteFailure == nil)
        // NFR-1.8: in the store, not only in the list on screen.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isCompleted) == [false])
    }

    @Test("Marking goes back the other way too — a failed set becomes completed")
    func outcomeIsSymmetrical() async throws {
        // The glyph is a toggle, so both directions are one control. A write that only ever cleared
        // the flag would pass every test above and strand a set failed for good — and a failed set
        // is invisible to FR-1.6's calculator, so the correction is the one that matters most.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 3, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)
        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isCompleted: false)

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isCompleted: true)

        #expect(workout.store.exercises.first?.sets.first?.isCompleted == true)
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isCompleted) == [true])
    }

    @Test("A failed set keeps the reps actually achieved, and prescribes nothing")
    func failingKeepsTheAchievedReps() async throws {
        // FR-1.2.5's second half, and the field FR-1.6.1's N-rep max detection reads later: `reps`
        // is what was done, and `targetReps` — which would be what was asked for — stays nil,
        // Phase 1 prescribing nothing (OUT-1.1). A write that moved the achieved count into the
        // target column would leave T-1.40 reading an empty one.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 3, rpe: 9.5, isWarmup: false, notes: "belt"))
        let before = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: before.id, inEntryID: entry.id, isCompleted: false)

        let after = try #require(workout.store.exercises.first?.sets.first)
        #expect(after.reps == 3)
        #expect(after.targetReps == nil)
        #expect(after.targetWeight == nil)
        #expect(after.id == before.id)
        #expect(after.order == before.order)
        #expect(after.weight == Weight(grams: 102_500))
        #expect(after.rpe == 9.5)
        #expect(after.notes == "belt")
        #expect(after.isWarmup == false)
        // The set was still tracked live: `completedAt` says when it happened, not that it went
        // well, and clearing it would destroy the only record of the distinction.
        #expect(after.completedAt == before.completedAt)
        #expect(after.completedAt != nil)
    }

    @Test("A failed working set leaves its exercise unfinished")
    func failingUnfinishesTheExercise() async throws {
        // FR-1.2.13 folds a card whose working sets are all completed, so the outcome flag is what
        // that rule reads. A card left folded over a set the user has just marked failed would say
        // the exercise was finished.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        #expect(workout.store.exercises.first?.isComplete == true)

        await workout.store.markSet(
            id: try #require(workout.store.exercises.first?.sets.first).id,
            inEntryID: entry.id,
            isCompleted: false)

        #expect(workout.store.exercises.first?.isComplete == false)
        // And the numbering is untouched: a failed set was still performed.
        let numbered = SetNumbering.numbered(try #require(workout.store.exercises.first?.sets))
        #expect(numbered.map(\.number) == [1])
    }

    @Test("Marking a set the outcome it already has writes nothing — G-2.4's conflict key")
    func markingIsANoOpWhenNothingChanges() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let before = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: before.id, inEntryID: entry.id, isCompleted: true)

        // Every save restamps `updatedAt`, which is G-2.4's conflict key — so a write that changed
        // nothing would let a no-op local edit outrank a real remote one.
        let after = try #require(workout.store.exercises.first?.sets.first)
        #expect(after.updatedAt == before.updatedAt)
        #expect(after.isCompleted == true)
    }

    @Test("Marking a set the read cannot find writes nothing and reports nothing")
    func markingAnAbsentSet() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))

        await workout.store.markSet(id: UUID(), inEntryID: entry.id, isCompleted: false)

        // The row was deleted underneath the card. A diagnostic here would report a failure against
        // a set that is no longer on screen.
        #expect(workout.store.exercisesWriteFailure == nil)
        #expect(workout.store.exercises.first?.sets.map(\.isCompleted) == [true])
    }

    @Test("A set marked with no workout in progress is not written")
    func noWorkoutNoMarking() async throws {
        // The set has to be a real stored row, and the store has to have let go of the workout it
        // belongs to — see the same test in `SessionSetMarkingTests` for why a store that never
        // held one cannot falsify this guard.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)
        await workout.store.finish()
        #expect(workout.store.session == nil)

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isCompleted: false)

        // The row is still there — finishing keeps it — and it is still completed.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isCompleted) == [true])
        #expect(workout.store.exercisesWriteFailure == nil)
    }

    @Test("An outcome and a kind marked together are both applied")
    func outcomeSharesTheWriteChain() async throws {
        // Both commands re-read the entry's sets when they run and both rebuild the whole record
        // from what they find. Unchained, the second to finish writes a record built before the
        // first landed, and one of the two flags is silently reverted.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)

        async let outcome: Void = workout.store.markSet(
            id: logged.id, inEntryID: entry.id, isCompleted: false)
        async let kind: Void = workout.store.markSet(
            id: logged.id, inEntryID: entry.id, isWarmup: true)
        _ = await (outcome, kind)

        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isCompleted) == [false])
        #expect(stored.map(\.isWarmup) == [true])
    }
}
