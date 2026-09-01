import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

@MainActor
@Suite("Saving a past workout as a routine")
struct PastSessionSaveAsRoutineTests {
    @Test("The routine reproduces the workout's exercises, loads and reps")
    func routineReproducesTheWorkout() async throws {
        let past = try await PastSession.logged(names: ["Back Squat", "Bench Press"])
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 180_000), reps: 3)
        try await past.logSet(at: 0, order: 1, weight: Weight(grams: 150_000), reps: 8)
        try await past.logSet(at: 0, order: 2, weight: Weight(grams: 150_000), reps: 8)
        try await past.logSet(at: 1, order: 0, weight: Weight(grams: 100_000), reps: 5)
        await past.state.load()

        await past.state.saveAsRoutine(named: "Tuesday")

        #expect(past.state.saveAsRoutineOutcome == .saved("Tuesday"))
        let stored = try await past.repositories.routines.routines(includingDeleted: false)
        #expect(stored.map(\.name) == ["Tuesday"])
        let routineID = try #require(stored.first?.id)
        let slots = try await past.repositories.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        #expect(slots.map(\.exerciseID) == past.exercises.map(\.id))
        #expect(slots.map(\.order) == [0, 1])

        let squat = try await past.repositories.routines.targetGroups(
            forRoutineExerciseID: slots[0].id, includingDeleted: false)
        #expect(squat.map(\.targetWeight) == [Weight(grams: 180_000), Weight(grams: 150_000)])
        #expect(squat.map(\.targetReps) == [3, 8])
        #expect(squat.map(\.targetSets) == [1, 2])
        #expect(squat.map(\.order) == [0, 1])
    }

    @Test("What was lifted wins over what was planned — FR-15.2.6's own reading")
    func loggedValuesBeatPlannedOnes() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.repositories.workouts.save(
            PlannedTargetGroup(
                id: UUID(),
                createdAt: PastSession.stamp,
                updatedAt: PastSession.stamp,
                deletedAt: nil,
                exerciseEntryID: past.entries[0].id,
                order: 0,
                targetWeight: Weight(grams: 200_000),
                targetReps: 5,
                targetSets: 3))
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 180_000), reps: 4)
        await past.state.load()

        await past.state.saveAsRoutine(named: "Tuesday")

        let routineID = try #require(
            try await past.repositories.routines.routines(includingDeleted: false).first?.id)
        let slots = try await past.repositories.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        let groups = try await past.repositories.routines.targetGroups(
            forRoutineExerciseID: slots[0].id, includingDeleted: false)
        #expect(groups.map(\.targetWeight) == [Weight(grams: 180_000)])
        #expect(groups.map(\.targetReps) == [4])
        #expect(groups.map(\.targetSets) == [1])
    }

    @Test("The name is trimmed, as the routine editor trims what it saves")
    func nameIsTrimmed() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0)
        await past.state.load()

        await past.state.saveAsRoutine(named: "  Tuesday \n")

        #expect(past.state.saveAsRoutineOutcome == .saved("Tuesday"))
        let stored = try await past.repositories.routines.routines(includingDeleted: false)
        #expect(stored.map(\.name) == ["Tuesday"])
    }

    @Test("A name of nothing but spaces writes nothing and says which failure it was")
    func emptyNameIsRefused() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0)
        await past.state.load()

        await past.state.saveAsRoutine(named: "   ")

        #expect(past.state.saveAsRoutineOutcome == .nameRequired)
        #expect(try await past.repositories.routines.routines(includingDeleted: true).isEmpty)
    }

    @Test("A store that refuses says the other thing, and it is not the empty-name sentence")
    func refusedWriteIsReported() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0)
        let state = PastSession.state(
            sessionID: past.sessionID,
            over: past.repositories,
            routines: RefusingRoutineRepository())
        await state.load()

        await state.saveAsRoutine(named: "Tuesday")

        #expect(state.saveAsRoutineOutcome == .writeFailed)
        #expect(try await past.repositories.routines.routines(includingDeleted: true).isEmpty)
    }

    @Test("A fresh read retires the outcome, as it retires this screen's other three")
    func readRetiresTheOutcome() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0)
        await past.state.load()
        await past.state.saveAsRoutine(named: "Tuesday")
        #expect(past.state.saveAsRoutineOutcome != nil)

        await past.state.load()

        #expect(past.state.saveAsRoutineOutcome == nil)
    }
}

/// A routine store that refuses every write — the failure the in-memory stack cannot produce.
private struct RefusingRoutineRepository: RoutineRepository {
    /// What every write throws.
    struct Refusal: Error {}

    func routines(includingDeleted: Bool) async throws -> [Routine] { [] }

    func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? { nil }

    func save(_ routine: Routine) async throws { throw Refusal() }

    func deleteRoutine(id: UUID) async throws { throw Refusal() }

    func exercises(
        forRoutineID routineID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineExercise] { [] }

    func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? { nil }

    func save(_ exercise: RoutineExercise) async throws { throw Refusal() }

    func deleteRoutineExercise(id: UUID) async throws { throw Refusal() }

    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup] { [] }

    func save(_ group: RoutineTargetGroup) async throws { throw Refusal() }

    func deleteTargetGroup(id: UUID) async throws { throw Refusal() }
}
