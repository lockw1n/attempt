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
        #expect(try await workout.store.pendingSets().map(\.id) == [setID])
    }

    /// The read the refusal rests on is the repository's, not the cards' — so it still answers
    /// while this store is holding a workout whose cards it has dropped.
    ///
    /// **`adopt(sessionID:)` is that window in one call**: it holds the session and ends with
    /// `forgetExercises()`. A count taken off ``ActiveSessionStore/exercises`` reads zero here, and
    /// a Finish built on it would end the workout silently — `FR-16.4.4`'s one prohibition.
    @Test("Pending sets are counted with the cards dropped, and Finish still refuses")
    func pendingSetsSurviveTheCardsBeingDropped() async throws {
        let pending = try await workoutWithOnePendingSet()
        let (workout, setID) = (pending.workout, pending.set)
        let sessionID = try #require(workout.store.session?.id)

        await workout.store.adopt(sessionID: sessionID)

        #expect(workout.store.exercises.isEmpty)
        #expect(try await workout.store.pendingSets().map(\.id) == [setID])

        await workout.store.finish()

        #expect(workout.store.session?.endedAt == nil)
        #expect(workout.store.pendingSetCount == 1)
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
        // And the screen is told what to ask about, by the same read that declined.
        #expect(workout.store.pendingSetCount == 1)
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

        #expect(try await workout.store.pendingSets().isEmpty)
        await workout.store.finish()

        #expect(workout.store.session == nil)
        #expect(workout.store.pendingSetCount == 0)
    }

    // MARK: - FR-15.3.3

    /// **Over a workout that has a plan**, because the claim is about a ratio rather than about its
    /// absence: a fixture prescribing nothing gives `nil` before and `nil` after, which any
    /// implementation satisfies.
    ///
    /// `RoutineFixture` prescribes seven sets — a squat top set, three backoffs, and three bench —
    /// of which one is performed as prescribed and one is left pending. **Remove them** deletes the
    /// pending row, and the figure does not move: the denominator is the plan, and the plan did not
    /// change.
    @Test("Adherence counts the plan, not the log, so resolving a pending set does not move it")
    func pendingSetsDoNotMoveAdherence() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)
        await store.start(
            on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines)
        await store.loadExercises()
        let squat = try #require(store.exercises.first)
        for (grams, reps) in [(100_000, 5), (85_000, 8)] {
            let values = SetEntryValues(
                weight: Weight(grams: grams),
                reps: reps,
                rpe: nil,
                isWarmup: false,
                notes: ""
            )
            await store.addSet(toEntryID: squat.id, values: values)
        }
        let backoff = try #require(store.exercises.first?.sets.last)
        await store.markSet(id: backoff.id, inEntryID: squat.id, isCompleted: false)

        let sessionID = try #require(store.session?.id)
        let before = try #require(store.adherence)
        // Anchored to literals: the plan's seven, and the one set that was both completed and on
        // target. The pending set is in neither number.
        #expect(before.prescribed == 7)
        #expect(before.asPrescribed == 1)

        await store.finish(resolving: .remove)
        #expect(store.session == nil)

        // The same workout read back, now finished and one row lighter.
        let after = ActiveSessionStore.over(fixture.stack)
        await after.adopt(sessionID: sessionID)
        await after.loadExercises()
        let resolved = try #require(after.adherence)
        #expect(resolved == before)
    }
}
