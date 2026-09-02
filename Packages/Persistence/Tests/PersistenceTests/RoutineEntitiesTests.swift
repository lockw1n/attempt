import Foundation
import SwiftData
import Testing

@testable import Persistence

// The three routine entities under a real store. Built through `makeContext(for:)` rather than
// `ModelContainer(...)`: concurrent construction crashes the process, and the helper serialises it.

let routineSchema = Schema([
    RoutineEntity.self,
    RoutineExerciseEntity.self,
    RoutineTargetGroupEntity.self,
])

func makeRoutineContext() throws -> ModelContext {
    try makeContext(for: routineSchema)
}

@Suite("Routine entities")
struct RoutineEntitiesTests {
    @Test("RoutineEntity honours the conventions against a real store")
    func routineHonoursConventions() throws {
        let context = try makeRoutineContext()
        try assertStoredEntityConventions({ RoutineEntity(name: "Squat day") }, in: context)
    }

    @Test("RoutineExerciseEntity honours the conventions against a real store")
    func routineExerciseHonoursConventions() throws {
        let context = try makeRoutineContext()
        try assertStoredEntityConventions(
            { RoutineExerciseEntity(routineID: UUID(), exerciseID: UUID(), order: 0) },
            in: context
        )
    }

    @Test("RoutineTargetGroupEntity honours the conventions against a real store")
    func targetGroupHonoursConventions() throws {
        let context = try makeRoutineContext()
        try assertStoredEntityConventions(
            {
                RoutineTargetGroupEntity(
                    routineExerciseID: UUID(),
                    order: 0,
                    targetWeightGrams: 100_000,
                    targetReps: 5,
                    targetSets: 4
                )
            },
            in: context
        )
    }

    // The shape a repository actually reads back: one slot carrying two target groups at different
    // weights, reassembled by UUID because the schema declares no relationships (G-2.5). Inserted
    // out of order, so a fetch that leaned on insertion order would answer wrongly.
    @Test("A slot with two target groups persists and re-reads in order")
    func slotWithTwoGroupsRoundTrips() throws {
        let context = try makeRoutineContext()
        let routine = RoutineEntity(name: "Squat day")
        let slot = RoutineExerciseEntity(routineID: routine.id, exerciseID: UUID(), order: 0)
        let backoff = RoutineTargetGroupEntity(
            routineExerciseID: slot.id, order: 1, targetWeightGrams: 80_000, targetReps: 5, targetSets: 4)
        let topSet = RoutineTargetGroupEntity(
            routineExerciseID: slot.id, order: 0, targetWeightGrams: 90_000, targetReps: 4, targetSets: 4)
        context.insert(routine)
        context.insert(slot)
        context.insert(backoff)
        context.insert(topSet)
        try context.save()

        let slotID = slot.id
        let groups = try context.fetch(
            FetchDescriptor<RoutineTargetGroupEntity>.notDeleted(
                matching: #Predicate { $0.routineExerciseID == slotID },
                sortBy: [SortDescriptor(\.order)]
            )
        )

        #expect(groups.map(\.targetWeightGrams) == [90_000, 80_000])
        #expect(groups.map(\.targetReps) == [4, 5])
    }
}
