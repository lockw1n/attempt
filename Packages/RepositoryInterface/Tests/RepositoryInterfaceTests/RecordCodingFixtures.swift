import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

// One fully-populated instance of each of the nine records, plus the JSON key scanner the wire
// format is pinned with.
//
// **Every optional is non-nil here**, which is the opposite of the usual fixture instinct and is
// deliberate: an optional left nil is omitted from the encoding entirely, so a fixture full of nils
// would pin a key order with half the keys missing and a round trip that never carried a value.
// The omission rule gets its own test, with its own fixture.

let codingCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
let codingUpdatedAt = Date(timeIntervalSince1970: 1_700_003_600)
let codingDeletedAt = Date(timeIntervalSince1970: 1_700_007_200)
let codingID = UUID(uuidString: "0f7b6a5c-1111-4222-8333-444455556666") ?? UUID()
let codingJoinID = UUID(uuidString: "0f7b6a5c-7777-4888-8999-aaaabbbbcccc") ?? UUID()

func codingExercise() -> Exercise {
    Exercise(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        name: "Low-bar back squat",
        ukrainianName: "Присідання зі штангою на низькій позиції",
        movement: .squat,
        parentExerciseID: codingJoinID,
        equipment: .barbell,
        laterality: .unilateral,
        barType: .safetySquat,
        implementCount: 2,
        isCustom: true,
        isArchived: true,
        notes: "belt from 140",
        manualE1RM: Weight(grams: 182_500))
}

func codingSession() -> WorkoutSession {
    WorkoutSession(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        date: codingCreatedAt,
        startedAt: codingUpdatedAt,
        endedAt: codingDeletedAt,
        notes: "hot gym",
        bodyweight: Weight(grams: 82_400),
        programRunID: codingJoinID,
        scheduledWorkoutID: codingJoinID
    )
}

func codingExerciseEntry() -> ExerciseEntry {
    ExerciseEntry(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        sessionID: codingJoinID,
        exerciseID: codingJoinID,
        order: 3,
        notes: "wide stance"
    )
}

func codingSetEntry(
    rpe: Double? = 8.5,
    modifiers: [SetModifier] = [SetModifier(.belt), SetModifier(rawValue: "curriculum")]
) -> SetEntry {
    SetEntry(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        entryID: codingJoinID,
        order: 3,
        weight: Weight(grams: 142_500),
        reps: 5,
        rpe: rpe,
        rir: 2,
        isWarmup: true,
        isCompleted: true,
        targetWeight: Weight(grams: 140_000),
        targetReps: 6,
        modifiers: modifiers,
        notes: "paused rep 4",
        completedAt: codingUpdatedAt
    )
}

func codingBodyweightEntry() -> BodyweightEntry {
    BodyweightEntry(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        date: codingCreatedAt,
        weight: Weight(grams: 82_400),
        source: .healthKit
    )
}

func codingTrainingMaxEntry() -> TrainingMaxEntry {
    TrainingMaxEntry(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        exerciseID: codingJoinID,
        source: .percentOfRepMax,
        sourceRepCount: 3,
        manualWeight: Weight(grams: 180_000),
        percentage: 0.85,
        roundingIncrement: Weight(grams: 5000),
        roundingStrategy: .down,
        progressionIncrement: Weight(grams: 2500),
        effectiveFrom: codingCreatedAt
    )
}

func codingEquipmentProfile(
    plates: [Weight] = [Weight(grams: 25_000), Weight(grams: 15_000)],
    platePairCounts: [Int] = [2, 3]
) -> EquipmentProfile {
    EquipmentProfile(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        name: "the meet",
        barWeight: Weight(grams: 20_000),
        collarWeight: Weight(grams: 2500),
        plates: plates,
        platePairCounts: platePairCounts,
        isDefault: true
    )
}

func codingUserSettings(
    defaultRoundingIncrement: Weight = Weight(grams: 5000)
) -> UserSettings {
    UserSettings(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        userID: codingJoinID,
        displayUnit: .pounds,
        e1RMFormula: .brzycki,
        theme: .dark,
        defaultRoundingIncrement: defaultRoundingIncrement,
        defaultRoundingStrategy: .down
    )
}

func codingPersonalRecordCache() -> PersonalRecordCache {
    PersonalRecordCache(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        exerciseID: codingJoinID,
        repCount: 3,
        weight: Weight(grams: 180_000),
        sourceSetID: codingJoinID,
        achievedAt: codingCreatedAt,
        computationVersion: 1
    )
}

func codingRoutine() -> Routine {
    Routine(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        name: "Squat day"
    )
}

func codingRoutineExercise() -> RoutineExercise {
    RoutineExercise(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        routineID: codingJoinID,
        exerciseID: codingJoinID,
        order: 2
    )
}

func codingRoutineTargetGroup() -> RoutineTargetGroup {
    RoutineTargetGroup(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        routineExerciseID: codingJoinID,
        order: 1,
        targetWeight: Weight(grams: 90_000),
        targetReps: 4,
        targetSets: 4
    )
}

func codingPlannedTargetGroup(grams: Int? = 90_000) -> PlannedTargetGroup {
    PlannedTargetGroup(
        id: codingID,
        createdAt: codingCreatedAt,
        updatedAt: codingUpdatedAt,
        deletedAt: codingDeletedAt,
        exerciseEntryID: codingJoinID,
        order: 1,
        targetWeight: grams.map(Weight.init(grams:)),
        targetReps: 4,
        targetSets: 4
    )
}

/// `record` encoded as JSON text.
///
/// `String(bytes:encoding:)` rather than `String(decoding:as:)`, which SwiftLint bans here and is
/// right to: the latter substitutes replacement characters for invalid UTF-8, so a corrupt encoding
/// would read back as a plausible string and every assertion built on it would be about the
/// substitution rather than about the bytes.
func jsonText<R: StoredRecord>(of record: R) throws -> String {
    try #require(String(bytes: try JSONEncoder().encode(record), encoding: .utf8))
}

/// The keys `record` encodes at the top level, **sorted**.
///
/// Sorted rather than in encoding order, and that is a finding rather than a convenience:
/// `JSONEncoder` accumulates a keyed container into a dictionary, so the order it emits keys in is
/// Swift's per-process hash order and **differs between runs of the same binary** — measured, three
/// consecutive runs, three different orders. An assertion on encoding order through this encoder is
/// not a strict test, it is a flaky one.
///
/// So what this pins is key *spelling* and *completeness*, which is all `JSONEncoder` can be asked
/// about. Declaration order is a property of the conformance rather than of these bytes; see
/// `RecordCoding.swift`.
///
/// A scanner rather than `JSONSerialization`, which would hand back a `Dictionary` and silently
/// merge a duplicated key. Nested objects and arrays are skipped by depth, so the modifiers list
/// and the plate list contribute no keys of their own.
func encodedKeys<R: StoredRecord>(of record: R) throws -> [String] {
    let text = try jsonText(of: record)
    var keys: [String] = []
    var depth = 0
    var token = ""
    var inString = false
    var escaped = false

    for character in text {
        if escaped {
            token.append(character)
            escaped = false
            continue
        }
        if inString {
            switch character {
            case "\\": escaped = true
            case "\"": inString = false
            default: token.append(character)
            }
            continue
        }
        switch character {
        case "\"":
            inString = true
            token = ""
        case ":":
            if depth == 1 { keys.append(token) }
        case "{", "[":
            depth += 1
        case "}", "]":
            depth -= 1
        default:
            break
        }
    }
    return keys.sorted()
}
