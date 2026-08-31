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

    @Test("A training max resolves to the latest entry effective on or before the date")
    func theTrainingMaxLookupPicksTheLatestApplicable() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)

        // **Saved newest-effective FIRST**, so `updatedAt` runs opposite to `effectiveFrom`. Saved
        // in the natural order the two agree, and a probe showed the lookup then passes with
        // `effectiveFrom` dropped from the key entirely — the fixture was satisfying the property
        // under test.
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        try await stack.exercises.saveTrainingMax(
            trainingMaxRecord(
                exerciseID: exercise.id, effectiveFrom: base + 3 * day, grams: 170_000))
        try await stack.exercises.saveTrainingMax(
            trainingMaxRecord(
                exerciseID: exercise.id, effectiveFrom: base + day, grams: 160_000))
        try await stack.exercises.saveTrainingMax(
            trainingMaxRecord(exerciseID: exercise.id, effectiveFrom: base, grams: 150_000))

        #expect(
            try await stack.exercises.trainingMax(forExerciseID: exercise.id, on: base - day)
                == nil)
        #expect(
            try await stack.exercises.trainingMax(forExerciseID: exercise.id, on: base)?
                .manualWeight == Weight(grams: 150_000))
        #expect(
            try await stack.exercises.trainingMax(forExerciseID: exercise.id, on: base + 2 * day)?
                .manualWeight == Weight(grams: 160_000))
        #expect(
            try await stack.exercises.trainingMax(forExerciseID: exercise.id, on: base + 9 * day)?
                .manualWeight == Weight(grams: 170_000))
    }

    @Test("A training max saved for an exercise that does not exist is refused")
    func aTrainingMaxNeedsItsExercise() async throws {
        let harness = try RepositoryHarness()
        let entry = trainingMaxRecord(exerciseID: UUID(), effectiveFrom: fixtureCreatedAt)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: entry.id, referencing: entry.exerciseID)
        ) { try await harness.stack.exercises.saveTrainingMax(entry) }

        #expect(try harness.store().fetch(FetchDescriptor<TrainingMaxConfigEntity>()).isEmpty)
    }

    @Test("Saving a training max appends rather than replacing the one it supersedes")
    func theHistoryIsKept() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        try await stack.exercises.saveTrainingMax(
            trainingMaxRecord(exerciseID: exercise.id, effectiveFrom: base, grams: 150_000))
        try await stack.exercises.saveTrainingMax(
            trainingMaxRecord(
                exerciseID: exercise.id, effectiveFrom: base + day, grams: 160_000))

        let history = try await stack.exercises.trainingMaxHistory(
            forExerciseID: exercise.id, includingDeleted: false)

        #expect(history.map(\.manualWeight) == [Weight(grams: 160_000), Weight(grams: 150_000)])
    }
}
