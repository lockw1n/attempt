import Foundation
import RepositoryInterface
import Testing

@testable import Persistence

// `FR-1.14.2`'s mapping half. Its own file rather than a section of `RecordMappingTests`, which is
// at SwiftLint's file ceiling — and the round trip there already covers the way *in*, so what is
// left here is the one direction that suite's source/target fixture pair cannot express.

@Suite("The Ukrainian name maps in both directions (FR-1.14.2)")
struct RecordMappingUkrainianNameTests {
    // `RecordMappingTests`' round trip carries the Ukrainian name onto a row that had none, which
    // is the direction `FR-1.14.2` needs on the way in. This is the other one, and it is the one an
    // unconditional overwrite gets right by accident and a `??` gets wrong: a record whose column is
    // absent must *clear* the row's, or a user could never take a Ukrainian name back off an
    // exercise. The seed importer's fill-if-absent rule lives a layer above, on the record.
    @Test("Clearing the Ukrainian name on a record clears the column")
    func clearingTheUkrainianNameClearsTheColumn() throws {
        let id = UUID()
        let entity = mappingSourceExercise(id: id)
        #expect(entity.ukrainianName != nil, "the fixture has nothing to clear")

        let cleared = Exercise(
            id: id,
            createdAt: mappingCreatedAt,
            updatedAt: mappingUpdatedAt,
            deletedAt: nil,
            name: "Low-bar back squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .unilateral,
            barType: .safetySquat,
            implementCount: 2,
            isCustom: true,
            isArchived: true,
            notes: "belt from 140",
            manualE1RM: nil)
        entity.update(from: cleared)

        #expect(entity.ukrainianName == nil)
        #expect(entity.name == "Low-bar back squat", "the rest of the row is still there")
    }
}
