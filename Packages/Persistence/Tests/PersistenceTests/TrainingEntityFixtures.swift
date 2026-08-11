import Foundation
import PowerliftingCore
import SwiftData

@testable import Persistence

// The four training entities under a real store. Built through `makeContext(for:)` rather than
// `ModelContainer(...)`: concurrent construction crashes the process, and the helper serialises it.

let trainingSchema = Schema([
    ExerciseEntity.self,
    WorkoutSessionEntity.self,
    ExerciseEntryEntity.self,
    SetEntryEntity.self,
])

func makeTrainingContext() throws -> ModelContext {
    try makeContext(for: trainingSchema)
}

/// A barbell back squat, with each vocabulary column set to a different case so a test can tell
/// which one was written where.
func makeSquat(name: String = "Back Squat") -> ExerciseEntity {
    ExerciseEntity(
        name: name,
        movement: .squat,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        isCustom: false
    )
}

/// A barbell bench press, so a session can hold two distinguishable exercises.
func makeBench() -> ExerciseEntity {
    ExerciseEntity(
        name: "Bench Press",
        movement: .bench,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        isCustom: false
    )
}

/// The live sets of one entry, by their own `order` — the innermost of the three ordering fields.
func loadsInOrder(ofEntry entryID: UUID, in context: ModelContext) throws -> [Int] {
    try context.fetch(
        FetchDescriptor<SetEntryEntity>.notDeleted(
            matching: #Predicate { $0.entryID == entryID },
            sortBy: [SortDescriptor(\.order)]
        )
    )
    .map(\.weightGrams)
}

/// A logged set with the fields a test is not varying already filled in.
///
/// `isWarmup` and `isCompleted` carry no default here either — `G-1.8`'s point is that no call site
/// may omit them, and a fixture that quietly supplied one would be the first exception.
func makeSet(
    entryID: UUID,
    order: Int,
    isWarmup: Bool,
    isCompleted: Bool,
    weightGrams: Int = 100_000,
    reps: Int = 5,
    rpe: Double? = nil,
    rir: Int? = nil,
    targetWeightGrams: Int? = nil,
    targetReps: Int? = nil,
    modifiers: [SetModifier] = [],
    completedAt: Date? = nil
) -> SetEntryEntity {
    SetEntryEntity(
        entryID: entryID,
        order: order,
        weightGrams: weightGrams,
        reps: reps,
        isWarmup: isWarmup,
        isCompleted: isCompleted,
        rpe: rpe,
        rir: rir,
        targetWeightGrams: targetWeightGrams,
        targetReps: targetReps,
        modifiers: modifiers,
        completedAt: completedAt
    )
}
