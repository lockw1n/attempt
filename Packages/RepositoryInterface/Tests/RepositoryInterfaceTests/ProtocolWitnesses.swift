import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

// Witnesses, not fakes. Each one exists to prove three things a `swift build` of the module cannot:
// that the protocol is satisfiable at all, that it is satisfiable by an **actor** — which is what
// the uniform `async throws` shape is for, since an actor-isolated implementation cannot witness a
// synchronous requirement — and that it is usable as an existential, which dependency injection
// needs.
//
// **They do not honour the contract and no test here may be read as evidence about behaviour.**
// Soft-delete exclusion, the duplicate-id tiebreak, the cascade and find-or-create are T-0.42's to
// implement and T-0.43's to hold both implementations to with one shared suite. `ExerciseWitness`
// is the exception and only just: it keeps an array so that `includingDeleted:` can be shown to
// reach an implementation and change an answer.

actor ExerciseWitness: ExerciseRepository {
    private var stored: [Exercise] = []

    func insert(_ exercise: Exercise) { stored.append(exercise) }

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        includingDeleted ? stored : stored.filter { !$0.isSoftDeleted }
    }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        try await exercises(includingDeleted: includingDeleted).first { $0.id == id }
    }

    func save(_ exercise: Exercise) async throws {
        stored.removeAll { $0.id == exercise.id }
        stored.append(exercise)
    }

    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) async throws -> TrainingMaxEntry? {
        nil
    }

    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        []
    }

    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}

actor WorkoutWitness: WorkoutRepository {
    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] { [] }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { nil }
    func save(_ session: WorkoutSession) async throws {}
    func deleteSession(id: UUID) async throws { throw RepositoryError.recordNotFound(id: id) }
    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] { [] }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { nil }
    func save(_ entry: ExerciseEntry) async throws {}
    func deleteExerciseEntry(id: UUID) async throws { throw RepositoryError.recordNotFound(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] { [] }
    func save(_ set: SetEntry) async throws {}
    func deleteSet(id: UUID) async throws { throw RepositoryError.recordNotFound(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] { [] }
}

actor SettingsWitness: SettingsRepository {
    func settings() async throws -> UserSettings {
        UserSettings(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            userID: UUID(),
            displayUnit: .pounds,
            e1RMFormula: .brzycki,
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 1_250),
            defaultRoundingStrategy: .down
        )
    }

    func save(_ settings: UserSettings) async throws {
        throw RepositoryError.identityAlreadyEstablished(recordID: settings.id)
    }
}

actor BodyweightWitness: BodyweightRepository {
    func entries(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [BodyweightEntry] { [] }
    func entry(id: UUID, includingDeleted: Bool) async throws -> BodyweightEntry? { nil }
    func save(_ entry: BodyweightEntry) async throws {}
    func deleteEntry(id: UUID) async throws { throw RepositoryError.recordNotFound(id: id) }
}

actor EquipmentWitness: EquipmentRepository {
    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile] { [] }
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile? { nil }
    func defaultProfile() async throws -> EquipmentProfile? { nil }
    func save(_ profile: EquipmentProfile) async throws {}
    func makeDefault(profileID: UUID) async throws { throw RepositoryError.recordNotFound(id: profileID) }
    func deleteProfile(id: UUID) async throws { throw RepositoryError.recordNotFound(id: id) }
}

@Suite("Protocol witnesses")
struct ProtocolWitnessTests {
    // The layering claim in one line: this target links PowerliftingCore and RepositoryInterface
    // and nothing else, so a protocol whose signature mentioned a @Model — or a record that needed
    // one to construct — would not compile here. On Linux the SwiftData module does not exist at
    // all, which is what turns "does not link SwiftData" from an assertion into a build result.
    @Test("All five protocols are satisfiable and usable as existentials")
    func everyProtocolIsSatisfiableWithoutSwiftData() async throws {
        let exercises: any ExerciseRepository = ExerciseWitness()
        let workouts: any WorkoutRepository = WorkoutWitness()
        let settings: any SettingsRepository = SettingsWitness()
        let bodyweight: any BodyweightRepository = BodyweightWitness()
        let equipment: any EquipmentRepository = EquipmentWitness()

        #expect(try await exercises.exercises(includingDeleted: false).isEmpty)
        #expect(try await workouts.sets(forExerciseID: UUID(), includingDeleted: false).isEmpty)
        #expect(try await settings.settings().displayUnit == .pounds)
        #expect(try await bodyweight.entry(id: UUID(), includingDeleted: false) == nil)
        #expect(try await equipment.defaultProfile() == nil)
    }

    // `includingDeleted:` has no default value on any read, so every call site states it. That
    // cannot be asserted — an omitted argument is a compile error, not a failing test — but its
    // *meaning* can be, and this is the reading T-0.43's shared suite holds both implementations
    // to.
    @Test("The deleted flag reaches the implementation and changes the answer")
    func deletedFlagIsHonoured() async throws {
        let live = makeExercise(name: "Comp bench")
        let removed = makeExercise(deletedAt: fixtureUpdatedAt, name: "Typo bench")
        let witness = ExerciseWitness()
        await witness.insert(live)
        await witness.insert(removed)

        #expect(try await witness.exercises(includingDeleted: false).map(\.name) == ["Comp bench"])
        #expect(try await witness.exercises(includingDeleted: true).count == 2)
        #expect(try await witness.exercise(id: removed.id, includingDeleted: false) == nil)
        #expect(try await witness.exercise(id: removed.id, includingDeleted: true) == removed)
    }

    // A save keyed on `id` replaces rather than appends. The store has no unique constraint
    // (G-2.5), so an implementation that inserted blind would fork a seed re-import or a restore
    // into two rows sharing an id — the duplicate this layer's tiebreak then has to resolve
    // forever.
    @Test("A save upserts on id rather than inserting a second row")
    func saveUpsertsOnID() async throws {
        let original = makeExercise(name: "Squat")
        let witness = ExerciseWitness()
        await witness.insert(original)

        try await witness.save(makeExercise(id: original.id, name: "Low-bar squat"))

        #expect(try await witness.exercises(includingDeleted: true).map(\.name) == ["Low-bar squat"])
    }
}
