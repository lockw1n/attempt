import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// The four cross-cutting rules, checked once each against the real store rather than five times in
// five suites. Everything here is about the *rules*; the per-protocol behaviour is next door.

/// The ids of the rows ``RepositorySoftDeleteTests`` seeds and then deletes.
struct DeletedRowIDs {
    let exercise: UUID
    let session: UUID
    let entry: UUID
    let reading: UUID
    let profile: UUID
}

@Suite("Reads return live rows by default")
struct RepositorySoftDeleteTests {
    /// One row of every kind, then every one of them soft-deleted.
    ///
    /// The exercise and its training max have no delete on their protocol, so those two are marked
    /// through the store — which is the point, since what is under test here is the *read*.
    private func seededThenAllDeleted() async throws -> (RepositoryHarness, DeletedRowIDs) {
        let harness = try RepositoryHarness()
        let stack = harness.stack

        let exercise = exerciseRecord(name: "Bench Press")
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        let set = setRecord(entryID: entry.id)
        try await stack.workouts.save(set)
        let reading = bodyweightRecord()
        try await stack.bodyweight.save(reading)
        let profile = profileRecord()
        try await stack.equipment.save(profile)
        let trainingMax = trainingMaxRecord(
            exerciseID: exercise.id, effectiveFrom: fixtureCreatedAt)
        try await stack.exercises.saveTrainingMax(trainingMax)

        // Soft-delete every row that has a delete. The exercise and its training max have none, so
        // they are deleted through the store to check the *read* rather than the delete.
        try await stack.workouts.deleteSession(id: session.id)
        try await stack.bodyweight.deleteEntry(id: reading.id)
        try await stack.equipment.deleteProfile(id: profile.id)
        let context = harness.store()
        for row in try context.fetch(FetchDescriptor<ExerciseEntity>()) { row.markDeleted() }
        for row in try context.fetch(FetchDescriptor<TrainingMaxConfigEntity>()) {
            row.markDeleted()
        }
        try context.save()

        return (
            harness,
            DeletedRowIDs(
                exercise: exercise.id,
                session: session.id,
                entry: entry.id,
                reading: reading.id,
                profile: profile.id
            )
        )
    }

    @Test("Every enumerating read excludes soft-deleted rows")
    func everyFlaggedReadExcludesThem() async throws {
        let (harness, ids) = try await seededThenAllDeleted()
        let stack = harness.stack
        let range = Date.distantPast...Date.distantFuture
        #expect(try await stack.exercises.exercises(includingDeleted: false).isEmpty)
        #expect(try await stack.exercises.exercise(id: ids.exercise, includingDeleted: false) == nil)
        #expect(
            try await stack.exercises.trainingMaxHistory(
                forExerciseID: ids.exercise, includingDeleted: false
            ).isEmpty)
        #expect(try await stack.workouts.sessions(in: range, includingDeleted: false).isEmpty)
        #expect(try await stack.workouts.session(id: ids.session, includingDeleted: false) == nil)
        #expect(
            try await stack.workouts.entries(forSessionID: ids.session, includingDeleted: false)
                .isEmpty)
        #expect(
            try await stack.workouts.sets(forEntryID: ids.entry, includingDeleted: false).isEmpty)
        #expect(
            try await stack.workouts.sets(forExerciseID: ids.exercise, includingDeleted: false)
                .isEmpty)
        #expect(try await stack.bodyweight.entries(in: range, includingDeleted: false).isEmpty)
        #expect(try await stack.bodyweight.entry(id: ids.reading, includingDeleted: false) == nil)
        #expect(try await stack.equipment.profiles(includingDeleted: false).isEmpty)
        #expect(try await stack.equipment.profile(id: ids.profile, includingDeleted: false) == nil)
    }

    @Test("The include flag brings every one of them back")
    func everyFlaggedReadCanReturnThem() async throws {
        let (harness, ids) = try await seededThenAllDeleted()
        let stack = harness.stack
        let range = Date.distantPast...Date.distantFuture
        #expect(try await stack.exercises.exercises(includingDeleted: true).count == 1)
        #expect(try await stack.exercises.exercise(id: ids.exercise, includingDeleted: true) != nil)
        #expect(
            try await stack.exercises.trainingMaxHistory(
                forExerciseID: ids.exercise, includingDeleted: true
            ).count == 1)
        #expect(try await stack.workouts.sessions(in: range, includingDeleted: true).count == 1)
        #expect(try await stack.workouts.session(id: ids.session, includingDeleted: true) != nil)
        #expect(
            try await stack.workouts.entries(forSessionID: ids.session, includingDeleted: true)
                .count == 1)
        #expect(
            try await stack.workouts.sets(forEntryID: ids.entry, includingDeleted: true).count == 1)
        #expect(
            try await stack.workouts.sets(forExerciseID: ids.exercise, includingDeleted: true)
                .count == 1)
        #expect(try await stack.bodyweight.entries(in: range, includingDeleted: true).count == 1)
        #expect(try await stack.bodyweight.entry(id: ids.reading, includingDeleted: true) != nil)
        #expect(try await stack.equipment.profiles(includingDeleted: true).count == 1)
        #expect(try await stack.equipment.profile(id: ids.profile, includingDeleted: true) != nil)
    }

    @Test("The three reads with no flag resolve to a live row")
    func theUnflaggedReadsResolve() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack

        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let superseded = trainingMaxRecord(
            exerciseID: exercise.id, effectiveFrom: fixtureCreatedAt, grams: 150_000)
        try await stack.exercises.saveTrainingMax(superseded)
        let profile = profileRecord()
        try await stack.equipment.save(profile)
        try await stack.equipment.makeDefault(profileID: profile.id)

        #expect(
            try await stack.exercises.trainingMax(
                forExerciseID: exercise.id, on: fixtureUpdatedAt)?.manualWeight
                == Weight(grams: 150_000))
        #expect(try await stack.equipment.defaultProfile()?.id == profile.id)

        let context = harness.store()
        for row in try context.fetch(FetchDescriptor<TrainingMaxConfigEntity>()) {
            row.markDeleted()
        }
        try context.save()
        try await stack.equipment.deleteProfile(id: profile.id)

        // A deleted configuration is one the user replaced; a deleted profile is a gym they left.
        #expect(
            try await stack.exercises.trainingMax(
                forExerciseID: exercise.id, on: fixtureUpdatedAt) == nil)
        #expect(try await stack.equipment.defaultProfile() == nil)
    }

    @Test("Deleting the default profile leaves no default rather than promoting another")
    func deletingTheDefaultPromotesNobody() async throws {
        let stack = try RepositoryHarness().stack
        let first = profileRecord(name: "A")
        let second = profileRecord(name: "B")
        try await stack.equipment.save(first)
        try await stack.equipment.save(second)
        try await stack.equipment.makeDefault(profileID: first.id)

        try await stack.equipment.deleteProfile(id: first.id)

        #expect(try await stack.equipment.defaultProfile() == nil)
    }
}

@Suite("Two rows may share an id")
struct RepositoryDuplicateIDTests {
    @Test("A by-id read returns the later updatedAt")
    func theTiebreakPicksTheLaterWrite() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let pair = duplicateExercises(id: id, olderName: "older", newerName: "newer")
        try harness.seed([pair.newer, pair.older])

        let read = try await harness.stack.exercises.exercise(id: id, includingDeleted: false)
        #expect(read?.name == "newer")
    }

    @Test("An updatedAt tie between two ids resolves on id.uuidString, and does so every time")
    func theSecondClauseIsTotalAcrossIDs() async throws {
        // Two DIFFERENT profiles both claiming the flag — the case rule 2 names, and the one where
        // the second clause is total. Repeated because the failure this pins is a nondeterministic
        // one: `fetchLimit = 1` over a sort answers this 13/7 across runs.
        let lower = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
        let upper = UUID(uuidString: "99999999-9999-9999-9999-999999999999") ?? UUID()

        for _ in 0..<12 {
            let harness = try RepositoryHarness()
            let stamp = fixtureUpdatedAt
            try harness.seed([
                markedProfile(id: lower, name: "A", updatedAt: stamp),
                markedProfile(id: upper, name: "B", updatedAt: stamp),
            ])

            #expect(try await harness.stack.equipment.defaultProfile()?.id == upper)
        }
    }

    @Test("A save writes every duplicate, not only the one a read returns")
    func aSaveConverges() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let pair = duplicateExercises(id: id, olderName: "older", newerName: "newer")
        try harness.seed([pair.older, pair.newer])

        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "edited"))

        let rows = try harness.store().fetch(FetchDescriptor<ExerciseEntity>())
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.name == "edited" })
    }

    @Test("A delete sweeps every duplicate, so the row does not come back")
    func aDeleteSweeps() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            duplicateReading(id: id, grams: 80_000, updatedAt: fixtureCreatedAt),
            duplicateReading(id: id, grams: 81_000, updatedAt: fixtureUpdatedAt),
        ])

        try await harness.stack.bodyweight.deleteEntry(id: id)

        #expect(try await harness.stack.bodyweight.entry(id: id, includingDeleted: false) == nil)
        #expect(
            try await harness.stack.bodyweight.entries(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false
            ).isEmpty)
    }
}

@Suite("An unreadable field costs the field, never the row")
struct RepositoryFallbackTests {
    @Test("An exercise whose laterality this version cannot map still comes back")
    func anUnmappableSpellingDoesNotCostTheExercise() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([foreignLateralityExercise(id: id, spelling: "quadrilateral")])

        let read = try await harness.stack.exercises.exercise(id: id, includingDeleted: false)

        // `Laterality` has no unknown case and throws on an unrecognised value, which is exactly
        // why the loss would route in through it. The row survives and the field degrades.
        #expect(read?.name == "Split Squat")
        #expect(read?.laterality == .bilateral)
    }

    @Test("A malformed plate inventory is returned whole by a read and refused by a save")
    func aMalformedInventoryReadsAndRefuses() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let malformed = EquipmentProfileEntity(
            id: id,
            name: "Corrupt",
            barWeightGrams: 20_000,
            collarWeightGrams: 0,
            plateGrams: [25_000, 25_000],
            platePairCounts: [2, 2]
        )
        try harness.seed([malformed])

        let read = try #require(
            try await harness.stack.equipment.profile(id: id, includingDeleted: false))
        #expect(read.name == "Corrupt")
        #expect(read.plates.count == 2)
        #expect(throws: RecordProjectionError.self) { try read.inventory() }

        await #expect(throws: RepositoryError.self) {
            try await harness.stack.equipment.save(read)
        }
    }
}

/// One of two bodyweight rows sharing an id — a state only a sync or a re-import produces.
private func duplicateReading(id: UUID, grams: Int, updatedAt: Date) -> BodyweightEntryEntity {
    BodyweightEntryEntity(
        id: id,
        date: fixtureCreatedAt,
        weightGrams: grams,
        source: .manual,
        updatedAt: updatedAt
    )
}
