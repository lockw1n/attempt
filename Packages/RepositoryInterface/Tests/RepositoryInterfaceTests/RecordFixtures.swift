import Foundation
import PowerliftingCore
import RepositoryInterface

// Fixtures for the suites in this target. Every default here differs from the value the schema
// defaults the matching column to, so a test asserting a field never passes because two unrelated
// defaults happened to agree — T-0.32's rule, inherited.
//
// `deletedAt: nil` is the one exception and it is deliberate rather than missed: it is the axis
// `softDeletionReadsTheDate` and `deletedFlagIsHonoured` vary, and both values are stated at the
// call site on both sides, so there is nothing for a coincidence to hide behind.

let fixtureCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
let fixtureUpdatedAt = Date(timeIntervalSince1970: 1_700_003_600)

func makeExercise(
    id: UUID = UUID(),
    deletedAt: Date? = nil,
    name: String = "Low-bar back squat",
    ukrainianName: String? = nil,
    movement: Movement = .squat,
    implementCount: Int = 2,
    isArchived: Bool = true
) -> Exercise {
    Exercise(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        name: name,
        ukrainianName: ukrainianName,
        movement: movement,
        parentExerciseID: nil,
        equipment: .barbell,
        laterality: .unilateral,
        barType: .safetySquat,
        implementCount: implementCount,
        isCustom: true,
        isArchived: isArchived,
        notes: "belt from 140",
        manualE1RM: nil)
}

func makeSetEntry(
    id: UUID = UUID(),
    deletedAt: Date? = nil,
    order: Int = 3,
    reps: Int = 5,
    rpe: Double? = 8.5,
    rir: Int? = 2,
    isWarmup: Bool = true,
    isCompleted: Bool = true,
    notes: String = "paused rep 4",
    // Unsorted and carrying a duplicate on purpose: the initialiser canonicalises, so a fixture
    // already in canonical form could not show it doing anything.
    modifiers: [SetModifier] = [
        SetModifier(rawValue: "curriculum"), SetModifier(rawValue: "belt"),
        SetModifier(rawValue: "curriculum"),
    ]
) -> SetEntry {
    SetEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        entryID: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
        order: order,
        weight: Weight(grams: 142_500),
        reps: reps,
        rpe: rpe,
        rir: rir,
        isWarmup: isWarmup,
        isCompleted: isCompleted,
        targetWeight: Weight(grams: 140_000),
        targetReps: 6,
        modifiers: modifiers,
        notes: notes,
        completedAt: fixtureUpdatedAt
    )
}
