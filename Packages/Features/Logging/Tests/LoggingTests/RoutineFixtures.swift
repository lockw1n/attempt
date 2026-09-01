import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

// The routine every `FR-15.2`/`FR-15.3` suite starts a workout from, in a file of its own because
// two suites now need it: `SessionRoutineStartTests` proves the snapshot is taken, and
// `SessionPlanAdjustmentTests` proves an adjustment made afterwards cannot reach back to it.

/// One target group's three numbers, as a value: a helper taking all three plus an id, a slot and
/// an order is a six-parameter function, and a tuple of three is a large tuple.
private struct TargetSpec {
    let grams: Int?
    let reps: Int
    let sets: Int
}

/// The day every record in the fixture is stamped with, at file scope so the helpers below can
/// be called while the fixture is still initialising.
private let routineFixtureDay = Date(timeIntervalSince1970: 1_700_000_000)

/// A routine of two exercises: a squat with a top set and a backoff, and a bench with a blank
/// target — the three shapes `FR-15.2.1` and `FR-15.2.2` between them allow.
@MainActor
struct RoutineFixture {
    let stack = InMemoryRepositoryStack()
    let squat = UUID()
    let bench = UUID()
    let routineID = UUID()
    let squatSlotID = UUID()
    let today = routineFixtureDay

    /// The squat's top set, whose id the "a later edit changes nothing" test rewrites.
    let topSetID = UUID()

    init() async throws {
        for (id, name) in [(squat, "Back Squat"), (bench, "Bench Press")] {
            try await stack.exercises.save(exercise(id: id, named: name))
        }
        try await stack.routines.save(
            Routine(
                id: routineID,
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                name: "Squat day"
            )
        )

        try await stack.routines.save(slot(id: squatSlotID, exerciseID: squat, order: 0))
        try await stack.routines.save(
            group(id: topSetID, slotID: squatSlotID, order: 0, target: TargetSpec(grams: 100_000, reps: 5, sets: 1)))
        try await stack.routines.save(
            group(id: UUID(), slotID: squatSlotID, order: 1, target: TargetSpec(grams: 85_000, reps: 8, sets: 3)))

        let benchSlotID = UUID()
        try await stack.routines.save(slot(id: benchSlotID, exerciseID: bench, order: 1))
        try await stack.routines.save(
            group(id: UUID(), slotID: benchSlotID, order: 0, target: TargetSpec(grams: nil, reps: 5, sets: 3)))
    }

    private func slot(id: UUID, exerciseID: UUID, order: Int) -> RoutineExercise {
        RoutineExercise(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            routineID: routineID,
            exerciseID: exerciseID,
            order: order
        )
    }

    private func group(
        id: UUID,
        slotID: UUID,
        order: Int,
        target: TargetSpec
    ) -> RoutineTargetGroup {
        RoutineTargetGroup(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            routineExerciseID: slotID,
            order: order,
            targetWeight: target.grams.map(Weight.init(grams:)),
            targetReps: target.reps,
            targetSets: target.sets
        )
    }

    private func exercise(id: UUID, named name: String) -> Exercise {
        Exercise(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            name: name,
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
    }
}
