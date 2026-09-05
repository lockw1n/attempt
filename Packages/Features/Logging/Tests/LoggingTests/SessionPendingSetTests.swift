import DerivedValues
import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Pending sets on the workout in progress, and the question Finish asks about them
/// (`FR-16.4.1`, `FR-16.4.4`, `FR-15.3.3`).
@Suite("Pending sets in the workout in progress")
struct SessionPendingSetTests {
    /// The fixture, and the two ids a case needs off it.
    private struct PendingWorkout {
        let workout: Workout
        let entry: UUID
        let set: UUID
    }

    /// A started workout with one squat set logged and then marked not completed.
    ///
    /// **Marked rather than written uncompleted**, because that is how a set becomes pending
    /// through the front door: the editor writes a completed set and the outcome control toggles it.
    private func workoutWithOnePendingSet() async throws -> PendingWorkout {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))
        let logged = try #require(workout.store.exercises.first?.sets.first)
        await workout.store.markSet(id: logged.id, inEntryID: entry.id, isCompleted: false)
        return PendingWorkout(workout: workout, entry: entry.id, set: logged.id)
    }

    // MARK: - FR-16.4.1

    @Test("A set nobody attempted is pending, not failed")
    func anUncompletedSetInAnOpenWorkoutIsPending() async throws {
        let pending = try await workoutWithOnePendingSet()
        let (workout, setID) = (pending.workout, pending.set)
        let session = try #require(workout.store.session)
        let set = try #require(workout.store.exercises.first?.sets.first)

        #expect(session.isPending(set))
        #expect(SetOutcome.of(isCompleted: false, isSessionOpen: true) == .pending)
        #expect(SetOutcome.of(isCompleted: false, isSessionOpen: false) == .failed)
        #expect(SetOutcome.of(isCompleted: true, isSessionOpen: true) == .completed)
        #expect(workout.store.pendingSets.map(\.id) == [setID])
    }

    @Test("A pending set is drawn in the tertiary ramp, a failed one in the negative")
    func pendingIsNotDrawnAsAFailure() async throws {
        // `G-7.3` reserves red for failure and `G-4.5` wants a second cue, so the glyphs differ in
        // shape as well as in tint — a hollow circle against a cross.
        #expect(SetOutcome.pending.tint == ColorToken.textTertiary)
        #expect(SetOutcome.failed.tint == ColorToken.negative)
        #expect(SetOutcome.pending.glyph == "circle")
        #expect(SetOutcome.failed.glyph == "xmark.circle")
        #expect(SetOutcome.pending.glyph != SetOutcome.failed.glyph)
        #expect(SetOutcome.pending.valueColour(isWarmup: false) == ColorToken.textTertiary)
        // The outcome outranks the warmup de-emphasis in both directions.
        #expect(SetOutcome.pending.valueColour(isWarmup: true) == ColorToken.textTertiary)
        #expect(SetOutcome.failed.valueColour(isWarmup: true) == ColorToken.negative)
    }

    // MARK: - FR-16.4.4

    @Test("Finish with no answer leaves the workout open, and does not convert anything")
    func finishRefusesWithoutAnAnswer() async throws {
        let pending = try await workoutWithOnePendingSet()
        let (workout, entry) = (pending.workout, pending.entry)

        await workout.store.finish()

        // Held, not ended: the alert is what the screen does next, and the store is what makes the
        // refusal true whichever screen asked.
        #expect(workout.store.session != nil)
        #expect(workout.store.session?.endedAt == nil)
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)
        #expect(stored.count == 1)
        #expect(stored.first?.isCompleted == false)
    }

    @Test("Keep as failed ends the workout and leaves the row alone")
    func keepAsFailedEndsTheWorkout() async throws {
        let pending = try await workoutWithOnePendingSet()
        let (workout, entry, setID) = (pending.workout, pending.entry, pending.set)
        let before = try await workout.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)

        await workout.store.finish(resolving: .keepAsFailed)

        #expect(workout.store.session == nil)
        let after = try await workout.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)
        #expect(after == before)
        #expect(after.map(\.id) == [setID])
    }

    @Test("Remove them ends the workout and soft-deletes the rows")
    func removeThemSoftDeletesTheRows() async throws {
        let pending = try await workoutWithOnePendingSet()
        let (workout, entry, setID) = (pending.workout, pending.entry, pending.set)

        await workout.store.finish(resolving: .remove)

        #expect(workout.store.session == nil)
        let live = try await workout.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: false)
        #expect(live.isEmpty)
        // `G-1.3`: gone from the read, still in the store, stamped.
        let all = try await workout.repositories.workouts.sets(
            forEntryID: entry, includingDeleted: true)
        #expect(all.map(\.id) == [setID])
        #expect(all.map(\.isSoftDeleted) == [true])
    }

    @Test("A workout with nothing pending finishes on the first tap")
    func nothingPendingNeedsNoAnswer() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id,
            values: SetEntryValues(
                weight: Weight(grams: 100_000), reps: 5, rpe: nil, isWarmup: false, notes: ""))

        #expect(workout.store.pendingSets.isEmpty)
        await workout.store.finish()

        #expect(workout.store.session == nil)
    }

    // MARK: - FR-15.3.3

    @Test("Adherence counts the plan, not the log, so a pending set does not move it")
    func pendingSetsDoNotMoveAdherence() async throws {
        let workout = try await workoutWithOnePendingSet().workout
        let withPending = workout.store.adherence

        await workout.store.finish(resolving: .keepAsFailed)
        await workout.store.resume()
        await workout.store.loadExercises()

        // Nothing planned this workout, so there is no adherence either way — which is the claim:
        // resolving a pending set is not a change to the plan.
        #expect(withPending == nil)
        #expect(workout.store.adherence == nil)
    }
}
