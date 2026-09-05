import Foundation
import PowerliftingCore
import RepositoryInterface

// The records the shared conformance suite builds from. Split out of `ConformanceSubject.swift`
// for size — that file reached the 500-line ceiling once `TR-16.2` added three program shapes. The
// line is the one the file was already drawn along: what a subject IS stays there, what a subject
// is HANDED lives here.
//
// EVERY FIXTURE CARRIES VALUES THAT DIFFER FROM EACH OTHER WITHIN A ROW, not merely values that
// differ from the defaults. Two columns of the same type on one row — a run's week and its day
// cursor, its start and its end — agree just as happily with a mapping that wrote either into
// both, so a fixture whose pair matches is a fixture that proves nothing about the pair.

// Deliberately far in the past, so "the write path stamped this" is a comparison against a literal
// rather than against another optional — the failure mode T-0.15 found three of.
let fixtureCreatedAt = Date(timeIntervalSince1970: 1_600_000_000)
let fixtureUpdatedAt = Date(timeIntervalSince1970: 1_600_003_600)
let fixtureDay = 86_400.0

func exerciseRecord(
    id: UUID = UUID(),
    name: String = "Back Squat",
    parentExerciseID: UUID? = nil,
    isArchived: Bool = false,
    createdAt: Date = fixtureCreatedAt,
    deletedAt: Date? = nil
) -> Exercise {
    Exercise(
        id: id,
        createdAt: createdAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        name: name,
        ukrainianName: nil,
        movement: .squat,
        parentExerciseID: parentExerciseID,
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
    notes: String = "",
    deletedAt: Date? = nil
) -> WorkoutSession {
    WorkoutSession(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        date: date,
        startedAt: nil,
        endedAt: nil,
        notes: notes,
        bodyweight: nil,
        programRunID: nil,
        scheduledWorkoutID: nil
    )
}

func programRecord(
    id: UUID = UUID(),
    name: String = "#2",
    notes: String = "14.09.25"
) -> Program {
    Program(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        name: name,
        notes: notes)
}

func programDayRecord(
    id: UUID = UUID(),
    programID: UUID,
    routineID: UUID,
    order: Int = 0
) -> ProgramDay {
    ProgramDay(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        programID: programID,
        routineID: routineID,
        order: order)
}

// The two `Int`s differ by default, and so do the two `Date`s: a run whose week and day agreed
// would pass for a mapping that wrote either into both.
func programRunRecord(
    id: UUID = UUID(),
    programID: UUID,
    startedAt: Date = fixtureCreatedAt,
    endedAt: Date? = nil,
    weekNumber: Int = 2,
    nextDayIndex: Int = 1
) -> ProgramRun {
    ProgramRun(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        programID: programID,
        startedAt: startedAt,
        endedAt: endedAt,
        weekNumber: weekNumber,
        nextDayIndex: nextDayIndex)
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
    isCompleted: Bool = true,
    modifiers: [SetModifier] = [],
    deletedAt: Date? = nil
) -> SetEntry {
    SetEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
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
        modifiers: modifiers,
        notes: "",
        completedAt: nil
    )
}

func bodyweightRecord(
    id: UUID = UUID(),
    date: Date = fixtureCreatedAt,
    grams: Int = 80_000,
    createdAt: Date = fixtureCreatedAt,
    deletedAt: Date? = nil
) -> BodyweightEntry {
    BodyweightEntry(
        id: id,
        createdAt: createdAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        date: date,
        weight: Weight(grams: grams),
        source: .manual
    )
}

func trainingMaxRecord(
    id: UUID = UUID(),
    exerciseID: UUID,
    effectiveFrom: Date,
    percentage: Double = 0.9
) -> TrainingMaxEntry {
    TrainingMaxEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        exerciseID: exerciseID,
        source: .manual,
        sourceRepCount: nil,
        percentage: percentage,
        roundingIncrement: Weight(grams: 2500),
        roundingStrategy: .nearest,
        progressionIncrement: nil,
        effectiveFrom: effectiveFrom
    )
}

func trainingMaxHistoryRecord(
    id: UUID = UUID(),
    exerciseID: UUID,
    effectiveFrom: Date,
    grams: Int = 180_000,
    oldGrams: Int? = nil,
    reason: String = "coach"
) -> TrainingMaxHistoryEntry {
    TrainingMaxHistoryEntry(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        exerciseID: exerciseID,
        effectiveFrom: effectiveFrom,
        oldWeight: oldGrams.map(Weight.init(grams:)),
        newWeight: Weight(grams: grams),
        reason: reason
    )
}

/// A settings record whose preferences **all differ from the bootstrap's first-launch choices**.
///
/// Deliberate: `settings()` mints kilograms / `.system` / 2 500 g / `.nearest`, so a save that
/// wrote no preference at all would be indistinguishable from a correct one under a fixture that
/// agreed with the bootstrap. Same rule the training-max fixture follows for `effectiveFrom`.
func settingsRecord(
    id: UUID = UUID(),
    userID: UUID = UUID(),
    createdAt: Date = fixtureCreatedAt,
    deletedAt: Date? = nil,
    displayUnit: MassUnit = .pounds,
    theme: ThemePreference = .dark,
    roundingIncrementGrams: Int = 5000,
    roundingStrategy: RoundingStrategy = .down
) -> UserSettings {
    UserSettings(
        id: id,
        createdAt: createdAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
        userID: userID,
        displayUnit: displayUnit,
        e1RMFormula: .defaultFormula,
        theme: theme,
        defaultRoundingIncrement: Weight(grams: roundingIncrementGrams),
        defaultRoundingStrategy: roundingStrategy
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

func routineRecord(
    id: UUID = UUID(),
    name: String = "Push day"
) -> Routine {
    Routine(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        name: name
    )
}

func routineExerciseRecord(
    id: UUID = UUID(),
    routineID: UUID,
    exerciseID: UUID,
    order: Int = 0
) -> RoutineExercise {
    RoutineExercise(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        routineID: routineID,
        exerciseID: exerciseID,
        order: order
    )
}

func routineTargetGroupRecord(
    id: UUID = UUID(),
    routineExerciseID: UUID,
    order: Int = 0,
    grams: Int = 100_000,
    reps: Int = 5,
    sets: Int = 4
) -> RoutineTargetGroup {
    RoutineTargetGroup(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        routineExerciseID: routineExerciseID,
        order: order,
        targetWeight: Weight(grams: grams),
        targetReps: reps,
        targetSets: sets
    )
}

func plannedTargetGroupRecord(
    id: UUID = UUID(),
    exerciseEntryID: UUID,
    order: Int = 0,
    grams: Int? = 100_000,
    reps: Int = 5,
    sets: Int = 4
) -> PlannedTargetGroup {
    PlannedTargetGroup(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: nil,
        exerciseEntryID: exerciseEntryID,
        order: order,
        targetWeight: grams.map(Weight.init(grams:)),
        targetReps: reps,
        targetSets: sets
    )
}

// MARK: - Ids that sort

/// Three UUIDs whose `uuidString`s sort `a < b < c`.
///
/// Every tiebreak in this layer ends in `id.uuidString`, so a test of one has to *control* that
/// clause rather than hope for it — an ordering test seeded with random ids passes about a third of
/// the time under a wrong implementation and is indistinguishable from a flake.
enum SortedIDs {
    // swiftlint:disable force_unwrapping
    /// Sorts before ``second``, and before any id a test leaves to `UUID()`.
    static let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let second = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
    static let third = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
    // swiftlint:enable force_unwrapping
}

/// Five ids whose `uuidString`s sort ascending — enough ties to score a tie-break probe.
///
/// Three would not be: a dropped `id.uuidString` clause leaves a permutation of however many rows
/// tie, so two rows let a wrong implementation pass half the time and three let it pass one time in
/// six. See `RoutineConformanceTests.routineChildrenAreOrderedByOrderThenID`.
enum TiedIDs {
    /// The five, already in the order a correct read returns them.
    static let ascending: [UUID] = [
        "00000000-0000-4000-8000-000000000001",
        "00000000-0000-4000-8000-000000000002",
        "00000000-0000-4000-8000-000000000003",
        "00000000-0000-4000-8000-00000000000A",
        "00000000-0000-4000-8000-00000000000B",
    ].compactMap(UUID.init(uuidString:))
}

// MARK: - Building a small history through the front door

/// One exercise, one session and one entry, all saved — the state most workout tests start from.
struct Timeline {
    let exerciseID: UUID
    let sessionID: UUID
    let entryID: UUID
}

extension Repositories {
    /// Saves an exercise, a session and an entry joining them, in the order the checks require.
    func timeline(
        exerciseID: UUID = UUID(),
        sessionID: UUID = UUID(),
        entryID: UUID = UUID(),
        date: Date = fixtureCreatedAt,
        entryOrder: Int = 0
    ) async throws -> Timeline {
        try await exercises.save(exerciseRecord(id: exerciseID))
        try await workouts.save(sessionRecord(id: sessionID, date: date))
        try await workouts.save(
            entryRecord(
                id: entryID, sessionID: sessionID, exerciseID: exerciseID, order: entryOrder))
        return Timeline(exerciseID: exerciseID, sessionID: sessionID, entryID: entryID)
    }
}
