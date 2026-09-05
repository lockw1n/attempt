import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("ExerciseRepository over SwiftData")
struct ExerciseRepositoryTests {
    @Test("Archived exercises are listed, because filtering them is the caller's")
    func archivedExercisesAreListed() async throws {
        let stack = try RepositoryHarness().stack
        try await stack.exercises.save(exerciseRecord(name: "Squat"))
        try await stack.exercises.save(exerciseRecord(name: "Behind-the-neck press", isArchived: true))

        let read = try await stack.exercises.exercises(includingDeleted: false)

        #expect(read.count == 2)
        #expect(read.contains { $0.isArchived })
    }

    @Test("A save upserts on id rather than appending a second row")
    func aSaveUpserts() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "Squat"))
        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "Back Squat"))

        #expect(try harness.store().fetch(FetchDescriptor<ExerciseEntity>()).count == 1)
        #expect(
            try await harness.stack.exercises.exercise(id: id, includingDeleted: false)?.name
                == "Back Squat")
    }

    @Test("A save leaves createdAt alone on an existing row and stamps updatedAt")
    func auditColumnsBelongToTheSavePath() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "Squat"))
        let created = try #require(
            try harness.store().fetch(FetchDescriptor<ExerciseEntity>()).first?.createdAt)

        // A record claiming a different history, and a stale updatedAt.
        let rewritten = Exercise(
            id: id,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            deletedAt: Date(timeIntervalSince1970: 0),
            name: "Back Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "",
            manualE1RM: nil)
        try await harness.stack.exercises.save(rewritten)

        let row = try #require(try harness.store().fetch(FetchDescriptor<ExerciseEntity>()).first)
        #expect(row.name == "Back Squat")
        #expect(row.createdAt == created)
        #expect(row.updatedAt > Date(timeIntervalSince1970: 0))
        #expect(row.deletedAt == nil)
    }

    @Test("A save whose id names a soft-deleted row writes it and does not resurrect it")
    func savingOverADeletedRowInsertsNothing() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try await harness.stack.bodyweight.save(bodyweightRecord(id: id, grams: 80_000))
        try await harness.stack.bodyweight.deleteEntry(id: id)

        try await harness.stack.bodyweight.save(bodyweightRecord(id: id, grams: 81_000))

        let rows = try harness.store().fetch(FetchDescriptor<BodyweightEntryEntity>())
        #expect(rows.count == 1)
        #expect(rows.first?.weightGrams == 81_000)
        #expect(rows.first?.deletedAt != nil)
        #expect(try await harness.stack.bodyweight.entry(id: id, includingDeleted: false) == nil)
    }

    @Test("A variation whose parent is not there is refused; saved after it, it is stored")
    func aVariationNeedsItsParent() async throws {
        let harness = try RepositoryHarness()
        let parentID = UUID()
        let variation = Exercise(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            name: "Pause Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: parentID,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: true,
            isArchived: false,
            notes: "",
            manualE1RM: nil)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: variation.id, referencing: parentID)
        ) { try await harness.stack.exercises.save(variation) }
        #expect(try harness.store().fetch(FetchDescriptor<ExerciseEntity>()).isEmpty)

        try await harness.stack.exercises.save(exerciseRecord(id: parentID, name: "Back Squat"))
        try await harness.stack.exercises.save(variation)
        #expect(try await harness.stack.exercises.exercises(includingDeleted: false).count == 2)
    }

    @Test("An exercise naming itself as its parent is refused, before and after it exists")
    func anExerciseCannotBeItsOwnParent() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let selfParenting = Exercise(
            id: id,
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            name: "Back Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: id,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: true,
            isArchived: false,
            notes: "",
            manualE1RM: nil)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: id, referencing: id)
        ) { try await harness.stack.exercises.save(selfParenting) }

        // …and still refused once the row exists, which existence alone would have accepted.
        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "Back Squat"))
        await #expect(
            throws: RepositoryError.danglingReference(recordID: id, referencing: id)
        ) { try await harness.stack.exercises.save(selfParenting) }

        let stored = try harness.store().fetch(FetchDescriptor<ExerciseEntity>())
        #expect(stored.map(\.parentExerciseID) == [nil])
    }
}
