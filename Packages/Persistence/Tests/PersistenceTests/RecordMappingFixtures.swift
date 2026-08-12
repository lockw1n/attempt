import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// Fixtures for the mapping round trip. Each entity gets a `source` and a `target`, and the rule
// that makes them worth having is: **every column `update(from:)` writes differs between the two**,
// while the four audit columns are identical. A dropped assignment then shows up as an inequality
// rather than as a coincidence, and the audit columns can be compared without carving them out of
// the record.
//
// `userID` and `isDefault` are the two deliberate exceptions: `update(from:)` writes neither, being
// cross-row invariants a single row's record cannot carry, so the fixtures for those two entities
// share them. `settingsUpdateLeavesTheIdentityAlone` and `profileUpdateLeavesTheDefaultFlagAlone`
// vary each explicitly instead.

let mappingCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
let mappingUpdatedAt = Date(timeIntervalSince1970: 1_700_003_600)
let mappingDeletedAt = Date(timeIntervalSince1970: 1_700_007_200)

/// Reads `source` back out of the store, maps it to a record, applies that record to `target`, and
/// checks that `target` now reads back as the same record.
///
/// The store leg is not decoration: it is what makes this a claim about columns SwiftData actually
/// persisted rather than about two objects in memory. `target` is left out of the store on purpose,
/// so a mapping that wrote nothing cannot be rescued by both sides sharing a row.
func assertRoundTrips<E: StoredEntity, R: StoredRecord>(
    source: E,
    target: E,
    record: (E) -> R,
    update: (E, R) -> Void,
    in context: ModelContext,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    context.insert(source)
    try context.save()

    let stored = try #require(
        try context.fetch(FetchDescriptor<E>.includingDeleted()).first(where: { $0.id == source.id }),
        sourceLocation: sourceLocation
    )
    let original = record(stored)
    update(target, original)

    #expect(record(target) == original, "\(E.self) does not round-trip", sourceLocation: sourceLocation)
}

/// Checks that a **new** row built from a live record reads back as that record.
///
/// `source` is cleared of its deletion date first, because the insert direction deliberately does
/// not carry one — a live row is the one case where it is lossless in full, and the deleted case
/// has its own assertion.
func assertInsertReproduces<E: StoredEntity, R: StoredRecord>(
    _ source: E,
    insert: (R) -> E,
    read: (E) -> R,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    source.deletedAt = nil
    let record = read(source)

    #expect(
        read(insert(record)) == record,
        "\(E.self) does not reproduce a record it was built from",
        sourceLocation: sourceLocation)
}

// MARK: - The four training entities

func mappingSourceExercise(id: UUID) -> ExerciseEntity {
    let entity = ExerciseEntity(
        id: id,
        name: "Low-bar back squat",
        movement: .squat,
        equipment: .barbell,
        laterality: .unilateral,
        barType: .safetySquat,
        isCustom: true,
        implementCount: 2,
        parentExerciseID: UUID(uuidString: "11111111-1111-1111-1111-111111111111"),
        isArchived: true,
        notes: "belt from 140",
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetExercise(id: UUID) -> ExerciseEntity {
    let entity = ExerciseEntity(
        id: id,
        name: "",
        movement: .bench,
        equipment: .machine,
        laterality: .alternating,
        barType: .noBar,
        isCustom: false,
        implementCount: 7,
        parentExerciseID: nil,
        isArchived: false,
        notes: "",
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingSourceSession(id: UUID) -> WorkoutSessionEntity {
    let entity = WorkoutSessionEntity(
        id: id,
        date: Date(timeIntervalSince1970: 1_690_000_000),
        startedAt: Date(timeIntervalSince1970: 1_690_003_600),
        endedAt: Date(timeIntervalSince1970: 1_690_010_000),
        notes: "hot gym",
        bodyweightGrams: 82_400,
        programRunID: UUID(uuidString: "22222222-2222-2222-2222-222222222222"),
        scheduledWorkoutID: UUID(uuidString: "33333333-3333-3333-3333-333333333333"),
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetSession(id: UUID) -> WorkoutSessionEntity {
    let entity = WorkoutSessionEntity(
        id: id,
        date: Date(timeIntervalSince1970: 1_600_000_000),
        notes: "",
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingSourceEntry(id: UUID) -> ExerciseEntryEntity {
    let entity = ExerciseEntryEntity(
        id: id,
        sessionID: UUID(uuidString: "44444444-4444-4444-4444-444444444444") ?? UUID(),
        exerciseID: UUID(uuidString: "55555555-5555-5555-5555-555555555555") ?? UUID(),
        order: 3,
        notes: "wide stance",
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetEntry(id: UUID) -> ExerciseEntryEntity {
    let entity = ExerciseEntryEntity(
        id: id,
        sessionID: SchemaDefaults.unlinkedID,
        exerciseID: SchemaDefaults.unlinkedID,
        order: 0,
        notes: "",
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingSourceSet(id: UUID) -> SetEntryEntity {
    let entity = SetEntryEntity(
        id: id,
        entryID: UUID(uuidString: "66666666-6666-6666-6666-666666666666") ?? UUID(),
        order: 3,
        weightGrams: 142_500,
        reps: 5,
        isWarmup: true,
        isCompleted: true,
        rpe: 8.5,
        rir: 2,
        targetWeightGrams: 140_000,
        targetReps: 6,
        // One built-in spelling and one no version has: the second is the half a fallback table
        // would destroy, and it has to survive the store, the record and the write back.
        modifiers: [SetModifier(.belt), SetModifier(rawValue: "curriculum")],
        notes: "paused rep 4",
        completedAt: Date(timeIntervalSince1970: 1_690_010_000),
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetSet(id: UUID) -> SetEntryEntity {
    let entity = SetEntryEntity(
        id: id,
        entryID: SchemaDefaults.unlinkedID,
        order: 0,
        weightGrams: 60_000,
        reps: 0,
        isWarmup: false,
        isCompleted: false,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

// MARK: - The five supporting entities

func mappingSourceBodyweight(id: UUID) -> BodyweightEntryEntity {
    let entity = BodyweightEntryEntity(
        id: id,
        date: Date(timeIntervalSince1970: 1_690_000_000),
        weightGrams: 82_400,
        source: .healthKit,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetBodyweight(id: UUID) -> BodyweightEntryEntity {
    let entity = BodyweightEntryEntity(
        id: id,
        date: Date(timeIntervalSince1970: 1_600_000_000),
        weightGrams: 0,
        source: .manual,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingSourceTrainingMax(id: UUID) -> TrainingMaxConfigEntity {
    let entity = TrainingMaxConfigEntity(
        id: id,
        exerciseID: UUID(uuidString: "77777777-7777-7777-7777-777777777777") ?? UUID(),
        source: .percentOfRepMax,
        percentage: 0.85,
        roundingIncrementGrams: 5000,
        roundingStrategy: .down,
        effectiveFrom: Date(timeIntervalSince1970: 1_690_000_000),
        sourceRepCount: 3,
        manualWeightGrams: 180_000,
        incrementGrams: 2500,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetTrainingMax(id: UUID) -> TrainingMaxConfigEntity {
    let entity = TrainingMaxConfigEntity(
        id: id,
        exerciseID: SchemaDefaults.unlinkedID,
        source: .percentOfE1RM,
        percentage: 0.9,
        roundingIncrementGrams: 1000,
        roundingStrategy: .up,
        effectiveFrom: Date(timeIntervalSince1970: 1_600_000_000),
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

/// A profile whose inventory `PlateInventory` refuses — 25 kg listed twice, and **not** in
/// heaviest-first order.
///
/// Malformed on purpose, in both ways, and the second one was added after a mutation probe.
/// A well-formed fixture would round-trip through the validating writer too, so it could not tell
/// whether the raw writer exists at all; and a fixture that happened to be sorted let a raw writer
/// that quietly sorted survive, because sorting an already-sorted list changes nothing.
func mappingSourceProfile(id: UUID) -> EquipmentProfileEntity {
    let entity = EquipmentProfileEntity(
        id: id,
        name: "the meet",
        barWeightGrams: 20_000,
        collarWeightGrams: 2500,
        plateGrams: [15_000, 25_000, 25_000],
        platePairCounts: [3, 2, 1],
        isDefault: true,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetProfile(id: UUID) -> EquipmentProfileEntity {
    let entity = EquipmentProfileEntity(
        id: id,
        name: "",
        barWeightGrams: 0,
        collarWeightGrams: 0,
        plateGrams: [],
        platePairCounts: [],
        // Shared with the source fixture, exactly as `userID` is: `update(from:)` does not write
        // `isDefault`, so a differing one would fail the round trip for a reason that is not a
        // mapping defect. `profileUpdateLeavesTheDefaultFlagAlone` varies it explicitly instead.
        isDefault: true,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

/// The user id both settings fixtures share. `update(from:)` never writes it, so a differing one
/// would make the round trip fail for a reason that is not a mapping defect.
let mappingUserID = UUID(uuidString: "88888888-8888-8888-8888-888888888888") ?? UUID()

func mappingSourceSettings(id: UUID, userID: UUID = mappingUserID) -> UserSettingsEntity {
    let entity = UserSettingsEntity(
        id: id,
        userID: userID,
        displayUnit: .pounds,
        e1RMFormula: .brzycki,
        theme: .dark,
        defaultRoundingIncrementGrams: 5000,
        defaultRoundingStrategy: .down,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetSettings(id: UUID, userID: UUID = mappingUserID) -> UserSettingsEntity {
    let entity = UserSettingsEntity(
        id: id,
        userID: userID,
        displayUnit: .kilograms,
        e1RMFormula: .wathan,
        theme: .light,
        defaultRoundingIncrementGrams: 1000,
        defaultRoundingStrategy: .up,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingSourceCache(id: UUID) -> PersonalRecordCacheEntity {
    let entity = PersonalRecordCacheEntity(
        id: id,
        exerciseID: UUID(uuidString: "99999999-9999-9999-9999-999999999999") ?? UUID(),
        repCount: 3,
        weightGrams: 180_000,
        sourceSetID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa") ?? UUID(),
        achievedAt: Date(timeIntervalSince1970: 1_690_000_000),
        computationVersion: PersonalRecordCalculator.computationVersion,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}

func mappingTargetCache(id: UUID) -> PersonalRecordCacheEntity {
    let entity = PersonalRecordCacheEntity(
        id: id,
        exerciseID: SchemaDefaults.unlinkedID,
        repCount: 0,
        weightGrams: 0,
        sourceSetID: SchemaDefaults.unlinkedID,
        achievedAt: Date.distantPast,
        computationVersion: 0,
        createdAt: mappingCreatedAt,
        updatedAt: mappingUpdatedAt
    )
    entity.deletedAt = mappingDeletedAt
    return entity
}
