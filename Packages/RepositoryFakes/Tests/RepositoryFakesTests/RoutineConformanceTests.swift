import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Routines, their exercise slots and target groups (`FR-15.2`), against both implementations.
@Suite("Conformance — routines")
struct RoutineConformanceTests {
    @Test(
        "A slot with two target groups at different weights round-trips, order and boundaries intact",
        arguments: Subject.all
    )
    func targetGroupsRoundTrip(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord(name: "Squat day")
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)

        let topSet = routineTargetGroupRecord(
            routineExerciseID: slot.id, order: 0, grams: 90_000, reps: 4, sets: 4)
        let backoff = routineTargetGroupRecord(
            routineExerciseID: slot.id, order: 1, grams: 80_000, reps: 5, sets: 4)
        // Saved out of order, so a read that trusted insertion order would still fail.
        try await repositories.routines.save(backoff)
        try await repositories.routines.save(topSet)

        let readRoutine = try await repositories.routines.routine(id: routine.id, includingDeleted: false)
        let readSlots = try await repositories.routines.exercises(
            forRoutineID: routine.id, includingDeleted: false)
        let readGroups = try await repositories.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)

        #expect(readRoutine?.name == "Squat day")
        #expect(readSlots.map(\.id) == [slot.id])
        #expect(readGroups.map(\.order) == [0, 1])
        #expect(readGroups.map(\.targetWeight) == [Weight(grams: 90_000), Weight(grams: 80_000)])
        #expect(readGroups.map(\.targetReps) == [4, 5])
        #expect(readGroups.map(\.targetSets) == [4, 4])
        #expect(
            readGroups.map(\.prescription) == [
                .fixedWeight(Weight(grams: 90_000)), .fixedWeight(Weight(grams: 80_000)),
            ])
    }

    @Test("Deleting a routine cascades to its slots and their target groups", arguments: Subject.all)
    func deletingARoutineCascades(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord()
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)
        let group = routineTargetGroupRecord(routineExerciseID: slot.id)
        try await repositories.routines.save(group)

        // A bystander routine that must not be touched — a cascade keyed on the wrong column would
        // take it, and every assertion below would still pass without it.
        let bystander = routineRecord(name: "Bench day")
        try await repositories.routines.save(bystander)
        let bystanderSlot = routineExerciseRecord(routineID: bystander.id, exerciseID: exerciseID)
        try await repositories.routines.save(bystanderSlot)
        let bystanderGroup = routineTargetGroupRecord(routineExerciseID: bystanderSlot.id)
        try await repositories.routines.save(bystanderGroup)

        try await repositories.routines.deleteRoutine(id: routine.id)

        #expect(try await repositories.routines.routine(id: routine.id, includingDeleted: false) == nil)
        #expect(
            try await repositories.routines.exercises(forRoutineID: routine.id, includingDeleted: false)
                .isEmpty)
        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ).isEmpty)

        #expect(try await repositories.routines.routine(id: bystander.id, includingDeleted: false) != nil)
        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: bystanderSlot.id, includingDeleted: false
            ).count == 1)
    }

    @Test("A slot needs both its routine and its exercise", arguments: Subject.all)
    func aSlotNeedsBothOfItsJoinKeys(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let routine = routineRecord()
        let exerciseID = UUID()
        try await repositories.routines.save(routine)
        let orphan = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: orphan.id, referencing: exerciseID)
        ) { try await repositories.routines.save(orphan) }

        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.routines.save(orphan)
        #expect(
            try await repositories.routines.exercises(forRoutineID: routine.id, includingDeleted: false)
                .count == 1)
    }

    @Test("A target group needs its slot", arguments: Subject.all)
    func aTargetGroupNeedsItsSlot(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let slotID = UUID()
        let orphan = routineTargetGroupRecord(routineExerciseID: slotID)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: orphan.id, referencing: slotID)
        ) { try await repositories.routines.save(orphan) }
    }
}
