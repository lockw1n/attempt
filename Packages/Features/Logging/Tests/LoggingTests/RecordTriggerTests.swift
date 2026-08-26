import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.6.4`'s trigger set, from this side: every write that moves a set column announces it, so a
/// personal record does not go stale the moment one is logged.
///
/// **Five call sites, five tests, and that is the point of the file.** `LoggedSetWriter`'s doc
/// comment names them — its own edit and delete, plus `addSet` and both `markSet` commands on the
/// store — and each writes a column one of the two calculators reads. A hook on four of the five
/// leaves a record that is wrong only after one particular gesture, which is the kind of defect that
/// survives a whole phase.
///
/// The subject is the real `PersonalRecordRecomputer` over the same fakes the store writes to, so
/// what is asserted is the cache actually moving rather than a spy having been called.
@Suite("Record recompute triggers")
struct RecordTriggerTests {
    /// The exercise's cached N-rep max for `reps`, or `nil`.
    private func cached(
        _ workout: Workout, _ exerciseID: UUID, reps: Int
    ) async throws -> Weight? {
        try await workout.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false
        ).first { $0.repCount == reps }?.weight
    }

    /// A workout with one working set of `grams` × 5 logged against the squat.
    private func loggedSquat(grams: Int = 100_000) async throws -> (
        workout: Workout, entryID: UUID
    ) {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let card = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: card.id,
            values: SetEntryValues(
                weight: Weight(grams: grams), reps: 5, rpe: nil, isWarmup: false))
        return (workout, card.id)
    }

    @Test("Logging a set puts its records in the cache")
    func addingASetRecomputes() async throws {
        let (workout, _) = try await loggedSquat()

        #expect(try await cached(workout, workout.squat.id, reps: 5) == Weight(grams: 100_000))
        #expect(try await cached(workout, workout.squat.id, reps: 1) == Weight(grams: 100_000))
        #expect(try await cached(workout, workout.squat.id, reps: 6) == nil)
    }

    @Test("Editing a set moves the record it held")
    func editingASetRecomputes() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)

        await workout.store.editSet(
            id: logged[0].id,
            inEntryID: entryID,
            to: SetEntryValues(
                weight: Weight(grams: 130_000), reps: 5, rpe: nil, isWarmup: false))

        #expect(try await cached(workout, workout.squat.id, reps: 5) == Weight(grams: 130_000))
    }

    @Test("Deleting the only set leaves no record standing")
    func deletingASetRecomputes() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)

        await workout.store.deleteSet(id: logged[0].id, inEntryID: entryID)

        #expect(try await cached(workout, workout.squat.id, reps: 5) == nil)
    }

    /// A warmup is out of the analysed sequence altogether, so marking one takes its record away —
    /// which is a column `LoggedSetWriter` never writes and the store does.
    @Test("Marking a set as a warmup takes its record away")
    func markingAWarmupRecomputes() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)

        await workout.store.markSet(id: logged[0].id, inEntryID: entryID, isWarmup: true)

        #expect(try await cached(workout, workout.squat.id, reps: 5) == nil)
    }

    /// `FR-1.2.5`'s failed set: the record calculator excludes on `isCompleted`, so the same set
    /// holds a record before the mark and none after it.
    @Test("Marking a set as failed takes its record away")
    func markingAFailureRecomputes() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)

        await workout.store.markSet(id: logged[0].id, inEntryID: entryID, isCompleted: false)

        #expect(try await cached(workout, workout.squat.id, reps: 5) == nil)
    }

    /// The History-side half: `LoggedSetWriter` is reachable without a workout in progress, and the
    /// trigger is on the writer rather than on either screen precisely so that both are covered.
    @Test("An edit made through the writer alone still recomputes")
    func theWriterAnnouncesWithoutAStore() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        let writer = LoggedSetWriter(
            repository: workout.repositories.workouts,
            records: PersonalRecordRecomputer(
                workouts: workout.repositories.workouts,
                cache: workout.repositories.personalRecords))

        let written = try await writer.edit(
            id: logged[0].id,
            inEntryID: entryID,
            to: SetEntryValues(
                weight: Weight(grams: 145_000), reps: 5, rpe: nil, isWarmup: false))

        #expect(written)
        #expect(try await cached(workout, workout.squat.id, reps: 5) == Weight(grams: 145_000))
    }

    /// **A write that changed nothing announces nothing**, which is the same `G-2.4` argument the
    /// writer's own no-op guard rests on: the announcement costs every screen showing this exercise
    /// a re-read, and the record cannot have moved.
    @Test("A no-op edit announces nothing")
    func aNoOpEditIsSilent() async throws {
        let (workout, entryID) = try await loggedSquat()
        let logged = try await workout.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        let recomputer = PersonalRecordRecomputer(
            workouts: workout.repositories.workouts,
            cache: workout.repositories.personalRecords)
        let writer = LoggedSetWriter(
            repository: workout.repositories.workouts, records: recomputer)

        let written = try await writer.edit(
            id: logged[0].id,
            inEntryID: entryID,
            to: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false))

        #expect(!written)
        // Nothing announced, so nothing recomputed — the rows are the ones `addSet` left.
        #expect(try await cached(workout, workout.squat.id, reps: 5) == Weight(grams: 100_000))
    }
}
