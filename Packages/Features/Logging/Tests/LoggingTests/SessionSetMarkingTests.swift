import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Marking a set as a warmup or as working, and what the store writes when it does (`FR-1.2.4`,
/// `G-1.8`, `G-2.4`, `NFR-1.8`).
///
/// A suite of its own rather than a section of `SessionSetsTests`: it is a different requirement,
/// and the two together outgrew `type_body_length`.
@Suite("Session set marking")
struct SessionSetMarkingTests {
    @Test("A set is logged as whichever kind the editor was on")
    func warmupIsTheCallers() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true, notes: ""))

        let held = try #require(workout.store.exercises.first?.sets.first)
        #expect(held.isWarmup == true)
        // Still performed: a warmup is work that happened, and G-1.8's two flags are independent.
        #expect(held.isCompleted == true)
        // And an exercise with nothing but a warmup in it has not started, so FR-1.2.13 does not
        // fold its card.
        #expect(workout.store.exercises.first?.isComplete == false)
    }

    @Test("Marking a logged set as a warmup is written through")
    func markingIsWrittenThrough() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isWarmup: true)

        #expect(workout.store.exercises.first?.sets.first?.isWarmup == true)
        #expect(workout.store.exercisesWriteFailure == nil)
        // NFR-1.8: in the store, not only in the list on screen.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isWarmup) == [true])
    }

    @Test("Marking goes back the other way too — a warmup becomes working")
    func markingIsSymmetrical() async throws {
        // The badge is a toggle, so both directions are one control. A write that only ever set the
        // flag would pass every test above and strand a mis-marked set as a warmup for good.
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isWarmup: false)

        #expect(workout.store.exercises.first?.sets.first?.isWarmup == false)
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isWarmup) == [false])
    }

    @Test("Marking changes nothing else about the set")
    func markingCarriesEveryOtherField() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 5, rpe: 8, isWarmup: false, notes: "belt"))
        let before = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: before.id, inEntryID: entry.id, isWarmup: true)

        let after = try #require(workout.store.exercises.first?.sets.first)
        #expect(after.id == before.id)
        #expect(after.order == before.order)
        #expect(after.weight == Weight(grams: 102_500))
        #expect(after.reps == 5)
        #expect(after.rpe == 8)
        #expect(after.notes == "belt")
        #expect(after.isCompleted == true)
        #expect(after.completedAt == before.completedAt)
    }

    @Test("Marking a set as the kind it already is writes nothing — G-2.4's conflict key")
    func markingIsANoOpWhenNothingChanges() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: true, notes: ""))
        let before = try #require(workout.store.exercises.first?.sets.first)

        await workout.store.markSet(id: before.id, inEntryID: entry.id, isWarmup: true)

        // Every save restamps `updatedAt`, which is G-2.4's conflict key — so a write that changed
        // nothing would let a no-op local edit outrank a real remote one.
        let after = try #require(workout.store.exercises.first?.sets.first)
        #expect(after.updatedAt == before.updatedAt)
        #expect(after.isWarmup == true)
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

        await workout.store.markSet(id: UUID(), inEntryID: entry.id, isWarmup: true)

        // The row was deleted underneath the card. A diagnostic here would report a failure against
        // a set that is no longer on screen.
        #expect(workout.store.exercisesWriteFailure == nil)
        #expect(workout.store.exercises.first?.sets.map(\.isWarmup) == [false])
    }

    @Test("A set marked with no workout in progress is not written")
    func noWorkoutNoMarking() async throws {
        // The set has to be a real stored row, and the store has to have let go of the workout it
        // belongs to. A store that never held one reads nothing back either way, so the guard it is
        // meant to check would be unfalsifiable — measured: removing `guard session != nil` from
        // `writeMarkedSet` left the whole suite green against the earlier version of this test.
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

        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isWarmup: true)

        // The row is still there — finishing keeps it — and it is still working.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.isWarmup) == [false])
        #expect(workout.store.exercisesWriteFailure == nil)
    }

    @Test("A marking and a log in flight together are both applied")
    func markingSharesTheWriteChain() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 60_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)

        // The marking re-reads the entry's sets when it runs, and so does the append beside it.
        // Unchained, one of the two computes against a list the other is about to replace.
        async let marking: Void = workout.store.markSet(
            id: logged.id, inEntryID: entry.id, isWarmup: true)
        async let logging: Void = workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 3, rpe: nil, isWarmup: false, notes: ""))
        _ = await (marking, logging)

        let sets = try #require(workout.store.exercises.first?.sets)
        #expect(sets.count == 2)
        #expect(sets.map(\.order) == [0, 1])
        #expect(sets.first?.isWarmup == true)
        #expect(sets.last?.isWarmup == false)
    }
}
