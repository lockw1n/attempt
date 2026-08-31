import Foundation
import Persistence
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

// The shared conformance suite's scaffolding: what a subject is, and the records every test builds
// from.
//
// ONE SUITE, TWO SUBJECTS, AND EVERY TEST RUNS TWICE. `@Test(arguments: Subject.all)` is the whole
// mechanism — there is no base class to subclass and no protocol for a test author to forget to
// conform to, so a test added here is a test both implementations must pass, by construction. A
// suite that had to be re-listed per subject is a suite that drifts one subject at a time, which is
// the failure this task exists to prevent.
//
// WHAT THE SUITE MAY DO TO A SUBJECT IS EXACTLY WHAT THE PROTOCOLS OFFER, and that boundary is
// the settled answer to "how does a shared suite seed a row no repository will write". It does not,
// and the three cases that prompted the question turn out to be three different answers:
//
//   A LIVE SET UNDER A DELETED ENTRY needs no seeding at all. Saving a set whose entry is
//   soft-deleted is legal — a soft-deleted target is not a dangling reference — so the state is
//   built through the front door, by both subjects, and `theCascadeReachesThroughADeletedEntry`
//   does exactly that.
//
//   A DUPLICATE `id` cannot be reached: every save upserts by id and `settings()` is find-or-create.
//   A seeding door for it would have to be matched by an OBSERVATION door — no protocol read
//   returns both rows — and both doors would be a second, untested contract shaped by whichever
//   subject implemented it first. It would also force the fakes to store arrays and carry their own
//   copy of the tiebreak, so the suite would be asserting a rule the fake exists in order not to
//   have. `G-2.4`'s tiebreak stays `Persistence`'s, tested there.
//
//   AN UNMAPPABLE VOCABULARY SPELLING is not representable in a record at all: `Exercise.laterality`
//   is a `Laterality`, and rule 4 resolves the stored string to a fallback before any record exists.
//   There is no record-shaped door that could express it. It is a mapping behaviour rather than a
//   repository one, and `RecordMappingTests` is where it lives.
//
// FOUR THINGS ARE THEREFORE OUT OF SCOPE HERE, each named so the exclusion is a decision rather than
// an omission, and each still tested on the side that can reach it:
//
//   1. the duplicate-`id` tiebreak, and its residual, which T-0.42 deliberately left open;
//   2. a save writing every duplicate rather than the tiebreak winner;
//   3. `settings()` finding a soft-deleted settings row (this protocol has no delete);
//   4. a soft-deleted exercise or training-max row being hidden by default — no protocol call
//      deletes either, so only the `includingDeleted:` flag's *live* half is reachable, and that
//      half is asserted.
//
// Every other behaviour of every method on every protocol is here.
// `PersonalRecordCacheRepository` (TR-1.6) joined a phase after the rest and brought two of those
// three: its reconciliation is cross-row and is written twice, once per subject, which is exactly
// the drift this suite exists to catch. `RoutineRepository` (FR-15.2) joined later still, with the
// same shape of hand-written-twice cascade.
//
// **THE METHOD COUNT USED TO BE SPELLED OUT HERE AND IT WAS WRONG.** This line read "all
// thirty-one methods" while the protocols carried thirty-three — the cache repository had grown
// from one method to three and the prose did not move — and it then survived a whole new protocol
// being added beside it. A total in a comment is a claim about a set that nothing walks, so it is
// stale from the first member added after it is written, and it reads as authoritative the whole
// time. What holds the claim now is the tests below naming their own populations ("on all eight
// deletes") plus `Repositories` failing to compile when a protocol is added and not threaded
// through both subjects.

/// One implementation of the protocols, as the suite sees it.
struct Subject: Sendable, CustomTestStringConvertible {
    let name: String
    private let build: @Sendable () throws -> Repositories

    /// A fresh, empty instance. Called once per test — the two subjects are independent stores.
    func make() throws -> Repositories { try build() }

    var testDescription: String { name }

    /// The SwiftData implementations over an in-memory store, and the fakes.
    ///
    /// `PersistenceStack(location: .inMemory)` is the supported way to build a container from
    /// outside the module: it takes the lock that serialises `ModelContainer` construction, which a
    /// suite running its cases in parallel very much needs.
    static let all: [Subject] = [
        Subject(name: "PersistenceStack") {
            let stack = try PersistenceStack(location: .inMemory)
            return Repositories(
                exercises: stack.exercises,
                workouts: stack.workouts,
                settings: stack.settings,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                personalRecords: stack.personalRecords,
                routines: stack.routines
            )
        },
        Subject(name: "InMemoryRepositoryStack") {
            let stack = InMemoryRepositoryStack()
            return Repositories(
                exercises: stack.exercises,
                workouts: stack.workouts,
                settings: stack.settings,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                personalRecords: stack.personalRecords,
                routines: stack.routines
            )
        },
    ]
}

/// The existentials, in the shape both stacks hand out.
struct Repositories: Sendable {
    let exercises: any ExerciseRepository
    let workouts: any WorkoutRepository
    let settings: any SettingsRepository
    let bodyweight: any BodyweightRepository
    let equipment: any EquipmentRepository
    let personalRecords: any PersonalRecordCacheRepository
    let routines: any RoutineRepository
}

// MARK: - Records

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
    name: String = "Push day",
    deletedAt: Date? = nil
) -> Routine {
    Routine(
        id: id,
        createdAt: fixtureCreatedAt,
        updatedAt: fixtureUpdatedAt,
        deletedAt: deletedAt,
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
