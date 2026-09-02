import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// The scaffolding the five repository suites share.
//
// **One container per harness, five repositories over it, and a seeding context beside them.** The
// seeding context is how a test writes a row the repositories could not write themselves — a
// duplicate id, an unrecognised vocabulary spelling, a dangling join key — which is most of what
// there is to check here: every interesting input to this layer is one the layer refuses to
// produce.
//
// `store()` hands back a NEW context each call rather than one held for the harness's lifetime.
// Repository writes land in their own contexts, and a context caches the objects it has already
// materialised, so a held one can answer from before the write it is meant to be checking.

/// A store, the five repositories over it, and a way to reach the rows directly.
struct RepositoryHarness {
    let container: ModelContainer
    let stack: PersistenceStack

    /// Opens a store the way the app opens one, through `Persistence`'s own container factory.
    ///
    /// - Parameter location: Where the store lives. In memory unless a test needs a store that
    ///   survives the container that made it — see ``FirstLaunchIdentityTests``.
    init(at location: StoreLocation = .inMemory) throws {
        container = try makeModelContainer(at: location)
        stack = PersistenceStack(container: container)
    }

    /// A fresh context on the same store, for seeding and for reading behind the repositories.
    func store() -> ModelContext { ModelContext(container) }

    /// Inserts `entities` and saves, without stamping — a seed is not a repository write.
    func seed(_ entities: [any PersistentModel]) throws {
        let context = store()
        for entity in entities { context.insert(entity) }
        try context.save()
    }
}

let fixtureCreatedAt = Date(timeIntervalSince1970: 1_600_000_000)
let fixtureUpdatedAt = Date(timeIntervalSince1970: 1_600_003_600)

// MARK: - Records

func exerciseRecord(
    id: UUID = UUID(),
    name: String = "Back Squat",
    isArchived: Bool = false,
    updatedAt: Date = fixtureUpdatedAt,
    deletedAt: Date? = nil
) -> Exercise {
    Exercise(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        name: name,
        ukrainianName: nil,
        movement: .squat,
        parentExerciseID: nil,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        implementCount: 1,
        isCustom: false,
        isArchived: isArchived,
        notes: "",
        manualE1RM: nil)
}

func sessionRecord(
    id: UUID = UUID(),
    date: Date = fixtureCreatedAt,
    notes: String = ""
) -> WorkoutSession {
    WorkoutSession(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        date: date,
        startedAt: nil,
        endedAt: nil,
        notes: notes,
        bodyweight: nil,
        programRunID: nil,
        scheduledWorkoutID: nil
    )
}

func entryRecord(
    id: UUID = UUID(),
    sessionID: UUID,
    exerciseID: UUID,
    order: Int = 0
) -> ExerciseEntry {
    ExerciseEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        sessionID: sessionID,
        exerciseID: exerciseID,
        order: order,
        notes: ""
    )
}

func setRecord(
    id: UUID = UUID(),
    entryID: UUID,
    order: Int = 0,
    grams: Int = 100_000,
    reps: Int = 5,
    isWarmup: Bool = false,
    isCompleted: Bool = true
) -> SetEntry {
    SetEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        entryID: entryID,
        order: order,
        weight: Weight(grams: grams),
        reps: reps,
        rpe: nil,
        rir: nil,
        isWarmup: isWarmup,
        isCompleted: isCompleted,
        targetWeight: nil,
        targetReps: nil,
        modifiers: [],
        notes: "",
        completedAt: nil
    )
}

func bodyweightRecord(
    id: UUID = UUID(),
    date: Date = fixtureCreatedAt,
    grams: Int = 80_000
) -> BodyweightEntry {
    BodyweightEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        date: date,
        weight: Weight(grams: grams),
        source: .manual
    )
}

func trainingMaxRecord(
    id: UUID = UUID(),
    exerciseID: UUID,
    effectiveFrom: Date,
    grams: Int = 180_000
) -> TrainingMaxEntry {
    TrainingMaxEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        exerciseID: exerciseID,
        source: .manual,
        sourceRepCount: nil,
        manualWeight: Weight(grams: grams),
        percentage: 0.9,
        roundingIncrement: Weight(grams: 2500),
        roundingStrategy: .nearest,
        progressionIncrement: nil,
        effectiveFrom: effectiveFrom
    )
}

func profileRecord(
    id: UUID = UUID(),
    name: String = "Home gym",
    plates: [Int] = [25_000, 20_000],
    pairCounts: [Int] = [2, 2],
    isDefault: Bool = false
) -> EquipmentProfile {
    EquipmentProfile(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        name: name,
        barWeight: Weight(grams: 20_000),
        collarWeight: Weight(grams: 2500),
        plates: plates.map(Weight.init(grams:)),
        platePairCounts: pairCounts,
        isDefault: isDefault
    )
}

// MARK: - Entities the repositories could not have written

/// An exercise row carrying a `laterality` spelling this version cannot map.
///
/// Written through the column rather than through `init`, which takes the typed value — the whole
/// point is a row that only a newer version, or another device, could have produced.
func foreignLateralityExercise(id: UUID, spelling: String) -> ExerciseEntity {
    let entity = ExerciseEntity(
        id: id,
        name: "Split Squat",
        movement: .squat,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        isCustom: false
    )
    entity.lateralityRawValue = spelling
    return entity
}

/// Two rows sharing one `id`, differing in `updatedAt` and in `name`.
func duplicateExercises(
    id: UUID,
    olderName: String,
    newerName: String,
    tie: Bool = false
) -> (older: ExerciseEntity, newer: ExerciseEntity) {
    let older = duplicateExercise(id: id, name: olderName, updatedAt: fixtureCreatedAt)
    let newer = duplicateExercise(
        id: id, name: newerName, updatedAt: tie ? fixtureCreatedAt : fixtureUpdatedAt)
    return (older, newer)
}

private func duplicateExercise(id: UUID, name: String, updatedAt: Date) -> ExerciseEntity {
    ExerciseEntity(
        id: id,
        name: name,
        movement: .squat,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        isCustom: false,
        updatedAt: updatedAt
    )
}

/// A profile carrying the default flag, for the cross-row half of the tiebreak.
func markedProfile(id: UUID, name: String, updatedAt: Date) -> EquipmentProfileEntity {
    EquipmentProfileEntity(
        id: id,
        name: name,
        barWeightGrams: 20_000,
        collarWeightGrams: 0,
        plateGrams: [],
        platePairCounts: [],
        isDefault: true,
        updatedAt: updatedAt
    )
}
