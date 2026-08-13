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
            "\"movement\": \"\(movement)\"",
        ]
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
    func edited(
        name: String? = nil,
        notes: String? = nil,
        isArchived: Bool? = nil,
        isCustom: Bool? = nil
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name ?? self.name,
            movement: movement,
            parentExerciseID: parentExerciseID,
            equipment: equipment,
            laterality: laterality,
            barType: barType,
            implementCount: implementCount,
            isCustom: isCustom ?? self.isCustom,
            isArchived: isArchived ?? self.isArchived,
            notes: notes ?? self.notes
        )
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
        movement: .other,
        parentExerciseID: nil,
        equipment: .machine,
        laterality: .bilateral,
        barType: .noBar,
        implementCount: 1,
        isCustom: true,
        isArchived: false,
        notes: "mine"
    )
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
