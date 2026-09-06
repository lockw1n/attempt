import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import SeedContent
import Testing

@testable import SeedImport

// The suite's payloads are built as text rather than as values, because `SeedExercise` decodes only
// — it has no memberwise initialiser, deliberately, since nothing writes the published file. A
// builder is enough here where `SeedContent`'s own suite needed files on disk: that suite exists to
// break the decoder, and this one only ever feeds it well-formed documents.

/// One catalogue entry as an author writes it.
struct AuthoredEntry {
    var id: UUID
    var name: String
    var ukrainianName: String?
    var movement = "squat"
    var parentExerciseID: UUID?
    var equipment = "barbell"
    var laterality = "bilateral"
    var barType = "standard"
    var implementCount: Int?

    init(_ id: UUID, _ name: String) {
        self.id = id
        self.name = name
    }

    /// The spelling this entry carries for `field`.
    func spelling(of field: SeedVocabularyField) -> String {
        switch field {
        case .movement: movement
        case .equipment: equipment
        case .laterality: laterality
        case .barType: barType
        }
    }

    /// `self` with a Ukrainian name, which the file carries only where the catalogue has one.
    func translated(_ value: String?) -> AuthoredEntry {
        var copy = self
        copy.ukrainianName = value
        return copy
    }

    /// `self` with one vocabulary field respelled.
    func spelling(_ field: SeedVocabularyField, as value: String) -> AuthoredEntry {
        var copy = self
        switch field {
        case .movement: copy.movement = value
        case .equipment: copy.equipment = value
        case .laterality: copy.laterality = value
        case .barType: copy.barType = value
        }
        return copy
    }

    /// The entry as it appears in the file.
    var json: String {
        var fields = [
            "\"id\": \"\(id.uuidString)\"",
            "\"name\": \"\(name)\"",
        ]
        if let ukrainianName {
            fields.append("\"ukrainianName\": \"\(ukrainianName)\"")
        }
        fields.append("\"movement\": \"\(movement)\"")
        if let parentExerciseID {
            fields.append("\"parentExerciseID\": \"\(parentExerciseID.uuidString)\"")
        }
        fields += [
            "\"equipment\": \"\(equipment)\"",
            "\"laterality\": \"\(laterality)\"",
            "\"barType\": \"\(barType)\"",
        ]
        if let implementCount {
            fields.append("\"implementCount\": \(implementCount)")
        }
        return "{ \(fields.joined(separator: ", ")) }"
    }
}

/// A whole payload's bytes.
func payload(revision: Int = 1, _ entries: [AuthoredEntry]) -> Data {
    let body = entries.map(\.json).joined(separator: ",\n    ")
    return Data(
        """
        {
          "schemaVersion": 1,
          "revision": \(revision),
          "exercises": [
            \(body)
          ]
        }
        """.utf8)
}

/// The decoded form of the same payload, for a test of the ordering alone.
func decoded(_ data: Data) throws -> [SeedExercise] {
    try JSONDecoder().decode(SeedCatalogue.self, from: data).exercises
}

/// One store, one importer over it.
struct Subject {
    let exercises: any ExerciseRepository
    let importer: SeedImporter

    init() {
        let stack = InMemoryRepositoryStack()
        exercises = stack.exercises
        importer = SeedImporter(exercises: stack.exercises)
    }

    /// Imports `data`, defaulting the floor to one entry.
    ///
    /// `importCatalogue(from:minimumExercises:at:)` takes no default on purpose — `TR-0.5.1`'s floor
    /// is eighty and a production caller should have to say so. These payloads are two or three
    /// entries, so the floor is this suite's business rather than each test's; the two tests that
    /// are *about* the floor pass it.
    @discardableResult
    func importing(
        _ data: Data,
        minimum: Int = 1,
        at now: Date = Date()
    ) async throws -> SeedImportSummary {
        try await importer.importCatalogue(from: data, minimumExercises: minimum, at: now)
    }

    /// Every stored exercise, archived ones included.
    func stored() async throws -> [Exercise] {
        try await exercises.exercises(includingDeleted: true)
    }

    /// The stored row carrying `id`.
    func stored(_ id: UUID) async throws -> Exercise? {
        try await exercises.exercise(id: id, includingDeleted: true)
    }
}

extension Exercise {
    /// A copy with the columns a user may edit replaced — the edits `FR-1.1.4` and `FR-1.1.5` allow,
    /// plus `isCustom` for the rows an import may not touch at all.
    ///
    /// The suite's one restatement of the fourteen-column initialiser; every setup that hand-edits a
    /// seeded row goes through it, so a column added later is added in one place on this side.
    ///
    /// ``Exercise/movement`` is here despite being seed-owned rather than user-editable: a row that
    /// differs from another in a *kept* column is indistinguishable to the merge, so a duplicate
    /// standing in for one the repository would resolve differently has to differ in an owned one.
    ///
    /// ``clearingUkrainianName`` exists because every other parameter here reads `nil` as *leave it
    /// alone*, which leaves no way to express the one edit that matters most for a column whose
    /// interesting value is `nil` — a user taking a Ukrainian name back off an exercise.
    func edited(
        name: String? = nil,
        ukrainianName: String? = nil,
        clearingUkrainianName: Bool = false,
        notes: String? = nil,
        isArchived: Bool? = nil,
        isCustom: Bool? = nil,
        movement: Movement? = nil,
        manualE1RM: Weight? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name ?? self.name,
            ukrainianName: clearingUkrainianName ? nil : ukrainianName ?? self.ukrainianName,
            movement: movement ?? self.movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: laterality,
            barType: barType,
            implementCount: implementCount,
            isCustom: isCustom ?? self.isCustom,
            isArchived: isArchived ?? self.isArchived,
            notes: notes ?? self.notes,
            manualE1RM: manualE1RM ?? self.manualE1RM)
    }
}

/// A repository that reports one extra row, sharing an id with a row the store already holds.
///
/// `G-2.5` forbids the unique constraint that would prevent such a pair, so a real store can hold
/// one — but ``InMemoryExerciseRepository`` keys its store by id and therefore cannot, which would
/// leave the importer's duplicate branch unreachable and unprobeable.
///
/// **Not a second implementation of the protocol**, and not in tension with this package's "one
/// subject" argument: every call forwards to the fake and exactly one answer is embellished, so the
/// branch has a state to run in. `exercise(id:)` is forwarded untouched on purpose — the whole
/// point of the branch is that resolving a duplicated id is the repository's answer to give.
struct DuplicateIDRepository: ExerciseRepository {
    let base: any ExerciseRepository

    /// The row reported a second time by ``exercises(includingDeleted:)``.
    let twin: Exercise

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        try await base.exercises(includingDeleted: includingDeleted) + [twin]
    }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        try await base.exercise(id: id, includingDeleted: includingDeleted)
    }

    func save(_ exercise: Exercise) async throws {
        try await base.save(exercise)
    }
}

/// An exercise the user authored (`FR-1.1.3`), which no import may overwrite.
func userAuthored(_ id: UUID, _ name: String, at now: Date = Date()) -> Exercise {
    Exercise(
        id: id,
        createdAt: now,
        updatedAt: now,
        deletedAt: nil,
        name: name,
        ukrainianName: nil,
        movement: .other,
        parentExerciseID: nil,
        equipment: .machine,
        laterality: .bilateral,
        barType: .noBar,
        implementCount: 1,
        isCustom: true,
        isArchived: false,
        notes: "mine",
        manualE1RM: nil)
}

/// The spelling a stored row carries for `field`, so a test can walk the four rather than name them.
func spelling(of exercise: Exercise, for field: SeedVocabularyField) -> String {
    switch field {
    case .movement: exercise.movement.rawValue
    case .equipment: exercise.equipment.rawValue
    case .laterality: exercise.laterality.rawValue
    case .barType: exercise.barType.rawValue
    }
}

/// A second valid spelling for one field, so a re-import has something to re-supply.
struct VocabularyChange: Sendable, CustomTestStringConvertible {
    let field: SeedVocabularyField
    let alternative: String

    var testDescription: String { field.rawValue }

    init(_ field: SeedVocabularyField, _ alternative: String) {
        self.field = field
        self.alternative = alternative
    }
}

/// Walked rather than named, and `everyVocabularyFieldHasAnAlternative` is what keeps a fifth field
/// from being half-covered.
let vocabularyChanges: [VocabularyChange] = [
    VocabularyChange(.movement, "bench"),
    VocabularyChange(.equipment, "dumbbell"),
    VocabularyChange(.laterality, "unilateral"),
    VocabularyChange(.barType, "trap"),
]

let squatID = testID("11111111-1111-4111-8111-111111111111")
let frontSquatID = testID("22222222-2222-4222-8222-222222222222")
let paceSquatID = testID("33333333-3333-4333-8333-333333333333")
let benchID = testID("44444444-4444-4444-8444-444444444444")
let customID = testID("55555555-5555-4555-8555-555555555555")
let absentID = testID("99999999-9999-4999-8999-999999999999")

/// A malformed literal fails every assertion naming it rather than quietly matching nothing.
private func testID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID()
}
