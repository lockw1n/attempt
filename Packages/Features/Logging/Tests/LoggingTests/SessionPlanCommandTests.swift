import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-15.3.4`'s check-off and `NFR-15.3`'s one-tap log, as writes against the workout in progress.
@MainActor
@Suite("The plan's two commands")
struct SessionPlanCommandTests {
    @Test("Checking an exercise off is stored, and survives a re-read")
    func checkOffIsStored() async throws {
        let fixture = try await PlannedSessionFixture()

        await fixture.store.markExercise(id: fixture.entryID, isDone: true)

        #expect(fixture.store.exercises.first?.entry.isMarkedDone == true)
        // `NFR-1.8`'s posture: what the screen shows after a fresh read is what is in the store,
        // not what the command left in memory.
        let stored = try await fixture.stack.workouts.entries(
            forSessionID: fixture.sessionID, includingDeleted: false)
        #expect(stored.first?.isMarkedDone == true)
    }

    @Test("The check-off goes back off again")
    func checkOffToggles() async throws {
        let fixture = try await PlannedSessionFixture()

        await fixture.store.markExercise(id: fixture.entryID, isDone: true)
        await fixture.store.markExercise(id: fixture.entryID, isDone: false)

        #expect(fixture.store.exercises.first?.entry.isMarkedDone == false)
    }

    /// `G-2.4`'s conflict key: assigning a `@Model` property marks the row changed whatever the
    /// value was, so a no-op local write would outrank a real remote edit.
    @Test("Marking an exercise the way it already is writes nothing")
    func noOpMarkWritesNothing() async throws {
        let fixture = try await PlannedSessionFixture()
        let before = try await fixture.stack.workouts.entries(
            forSessionID: fixture.sessionID, includingDeleted: false
        ).first?.updatedAt

        await fixture.store.markExercise(id: fixture.entryID, isDone: false)

        let after = try await fixture.stack.workouts.entries(
            forSessionID: fixture.sessionID, includingDeleted: false
        ).first?.updatedAt
        #expect(before != nil)
        #expect(after == before)
    }

    /// An exercise the read cannot find is silently nothing, on the set commands' rule — the row
    /// went away underneath the card.
    @Test("Checking off an exercise the workout does not hold reports no failure")
    func markingAnAbsentExerciseIsSilent() async throws {
        let fixture = try await PlannedSessionFixture()

        await fixture.store.markExercise(id: UUID(), isDone: true)

        #expect(fixture.store.exercisesWriteFailure == nil)
        #expect(fixture.store.exercises.first?.entry.isMarkedDone == false)
    }

    /// `NFR-15.3`'s second tap: the prescription is written as it stands, with no editor in
    /// between.
    @Test("The one-tap command logs the next planned set exactly as prescribed")
    func oneTapLogsThePrescription() async throws {
        let fixture = try await PlannedSessionFixture()

        await fixture.store.logPlannedSet(inEntryID: fixture.entryID)

        let logged = try #require(fixture.store.exercises.first?.sets.first)
        #expect(logged.weight == Weight(grams: 100_000))
        #expect(logged.reps == 5)
        #expect(logged.isWarmup == false)
    }

    /// The walk, exercised through the command: the second tap is the backoff, not the top set
    /// again.
    @Test("A second tap logs the next group, not the first one twice")
    func secondTapAdvancesTheWalk() async throws {
        let fixture = try await PlannedSessionFixture()

        await fixture.store.logPlannedSet(inEntryID: fixture.entryID)
        await fixture.store.logPlannedSet(inEntryID: fixture.entryID)

        let logged = try #require(fixture.store.exercises.first).sets
        #expect(logged.map(\.weight) == [Weight(grams: 100_000), Weight(grams: 85_000)])
        #expect(logged.map(\.reps) == [5, 8])
    }

    /// `FR-15.2.2`: a blank target names no load, so there is nothing to log without asking — and
    /// a command that invented a zero would assert a load nobody chose.
    @Test("A blank-weight group logs nothing, rather than logging zero")
    func blankWeightGroupLogsNothing() async throws {
        let fixture = try await PlannedSessionFixture(grams: nil)

        await fixture.store.logPlannedSet(inEntryID: fixture.entryID)

        #expect(fixture.store.exercises.first?.sets.isEmpty == true)
        #expect(fixture.store.exercisesWriteFailure == nil)
    }

    /// `FR-15.2.4`'s independence at the other end of the plan.
    @Test("Past the end of the plan the command logs nothing")
    func pastThePlanLogsNothing() async throws {
        let fixture = try await PlannedSessionFixture()

        for _ in 0..<5 {
            await fixture.store.logPlannedSet(inEntryID: fixture.entryID)
        }

        // One top set and three backoffs, and the fifth tap adds nothing.
        #expect(fixture.store.exercises.first?.sets.count == 4)
    }
}

/// A workout in progress with one planned exercise on it — the plan T-15.03 would have snapshotted,
/// written straight into the fakes rather than through a routine, because what is under test here
/// is the reading of it.
@MainActor
private struct PlannedSessionFixture {
    let stack = InMemoryRepositoryStack()
    let store: ActiveSessionStore
    let sessionID = UUID()
    let entryID = UUID()
    let exerciseID = UUID()

    /// - Parameter grams: The top set's load, or `nil` for `FR-15.2.2`'s blank target.
    init(grams: Int? = 100_000) async throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        store = ActiveSessionStore.over(stack)

        try await stack.exercises.save(
            Exercise(
                id: exerciseID,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                name: "Back Squat",
                ukrainianName: nil,
                movement: .squat,
                parentExerciseID: nil,
                equipment: .barbell,
                laterality: .bilateral,
                barType: .standard,
                implementCount: 1,
                isCustom: false,
                isArchived: false,
                notes: "",
                manualE1RM: nil
            )
        )
        try await stack.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                date: stamp,
                startedAt: stamp,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil
            )
        )
        try await stack.workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: ""
            )
        )
        try await stack.workouts.save(group(order: 0, grams: grams, reps: 5, sets: 1, at: stamp))
        try await stack.workouts.save(group(order: 1, grams: 85_000, reps: 8, sets: 3, at: stamp))

        await store.adopt(sessionID: sessionID)
        await store.loadExercises()
    }

    private func group(
        order: Int, grams: Int?, reps: Int, sets: Int, at stamp: Date
    ) -> PlannedTargetGroup {
        PlannedTargetGroup(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            exerciseEntryID: entryID,
            order: order,
            targetWeight: grams.map(Weight.init(grams:)),
            targetReps: reps,
            targetSets: sets
        )
    }
}
