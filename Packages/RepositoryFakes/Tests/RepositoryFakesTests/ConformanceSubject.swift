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
// WHAT THE SUITE MAY DO TO A SUBJECT IS EXACTLY WHAT THE FIVE PROTOCOLS OFFER, and that boundary is
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
// Every other behaviour of all twenty-eight methods is here.

/// One implementation of the five protocols, as the suite sees it.
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
                equipment: stack.equipment
            )
        },
        Subject(name: "InMemoryRepositoryStack") {
            let stack = InMemoryRepositoryStack()
            return Repositories(
                exercises: stack.exercises,
                workouts: stack.workouts,
                settings: stack.settings,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment
            )
        },
    ]
}

/// The five existentials, in the shape both stacks hand out.
struct Repositories: Sendable {
    let exercises: any ExerciseRepository
    let workouts: any WorkoutRepository
    let settings: any SettingsRepository
    let bodyweight: any BodyweightRepository
    let equipment: any EquipmentRepository
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
        movement: .squat,
        parentExerciseID: parentExerciseID,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        implementCount: 1,
        isCustom: false,
        isArchived: isArchived,
        notes: ""
    )
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
