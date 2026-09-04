import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("TrainingMaxRepository over SwiftData")
struct TrainingMaxRepositoryTests {
    private static let day = 86_400.0
    private static let base = Date(timeIntervalSince1970: 1_600_000_000)

    // The read the whole feature rests on (`FR-16.7.1`), and the one `<=` lives in. Three entries,
    // and every assertion is anchored to a literal weight rather than to another read — a
    // comparison of two lookups agrees just as happily when both return nothing.
    //
    // **The middle assertion is the mutation probe.** `on: base` sits exactly on the first entry's
    // effective date, so narrowing the repository's `<=` to `<` turns it red: the lookup falls back
    // to nothing, and 150 kg is not nil.
    //
    // Saved newest-effective FIRST, so `updatedAt` runs opposite to `effectiveFrom`. Saved in the
    // natural order the two agree, and the lookup then passes with `effectiveFrom` dropped from the
    // key entirely — the fixture would be satisfying the property under test.
    @Test("A training max resolves to the latest entry effective on or before the date")
    func theTrainingMaxLookupPicksTheLatestApplicable() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let (base, day) = (Self.base, Self.day)

        for (offset, grams) in [(3.0, 170_000), (1.0, 160_000), (0.0, 150_000)] {
            try await stack.trainingMaxes.save(
                trainingMaxHistoryRecord(
                    exerciseID: exercise.id,
                    effectiveFrom: base + offset * day,
                    grams: grams))
        }

        #expect(
            try await stack.trainingMaxes.trainingMax(
                forExerciseID: exercise.id, on: base - day) == nil)
        #expect(
            try await stack.trainingMaxes.trainingMax(forExerciseID: exercise.id, on: base)?
                .newWeight == Weight(grams: 150_000))
        #expect(
            try await stack.trainingMaxes.trainingMax(
                forExerciseID: exercise.id, on: base + 2 * day)?.newWeight
                == Weight(grams: 160_000))
        #expect(
            try await stack.trainingMaxes.trainingMax(
                forExerciseID: exercise.id, on: base + 9 * day)?.newWeight
                == Weight(grams: 170_000))
    }

    // `FR-15.1.4`'s three columns, read back off a real store rather than off the record that went
    // in: the old value is written rather than derived, so a mapping that dropped it would leave
    // every history row claiming to be the first.
    @Test("A change carries what it replaced and why")
    func aChangeCarriesItsOldValueAndReason() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id,
                effectiveFrom: Self.base,
                grams: 180_000,
                oldGrams: 140_000,
                reason: "block 3, coach"))

        let read = try await #require(
            stack.trainingMaxes.trainingMax(forExerciseID: exercise.id, on: Self.base))

        #expect(read.newWeight == Weight(grams: 180_000))
        #expect(read.oldWeight == Weight(grams: 140_000))
        #expect(read.reason == "block 3, coach")
    }

    // The first entry for an exercise replaced nothing, which is a different statement from a
    // change from zero — and the only one of the two a nil column can make.
    @Test("The first entry for an exercise names no old value")
    func theFirstEntryHasNoOldValue() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id, effectiveFrom: Self.base, grams: 140_000, oldGrams: nil))

        let read = try await #require(
            stack.trainingMaxes.trainingMax(forExerciseID: exercise.id, on: Self.base))

        // Anchored on the other side too: a decoder that threw the row away and rebuilt an empty
        // one would satisfy the nil on its own.
        #expect(read.oldWeight == nil)
        #expect(read.newWeight == Weight(grams: 140_000))
    }

    @Test("A training max saved for an exercise that does not exist is refused")
    func aTrainingMaxNeedsItsExercise() async throws {
        let harness = try RepositoryHarness()
        let entry = trainingMaxHistoryRecord(exerciseID: UUID(), effectiveFrom: fixtureCreatedAt)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: entry.id, referencing: entry.exerciseID)
        ) { try await harness.stack.trainingMaxes.save(entry) }

        #expect(try harness.store().fetch(FetchDescriptor<TrainingMaxHistoryEntity>()).isEmpty)
    }

    // The guard this test names is the exercise check, and the arrangement reaches it: the store is
    // empty, so there is no earlier guard for the save to stop at.
    @Test("A configuration saved for an exercise that does not exist is refused")
    func aConfigurationNeedsItsExercise() async throws {
        let harness = try RepositoryHarness()
        let entry = trainingMaxRecord(exerciseID: UUID(), effectiveFrom: fixtureCreatedAt)

        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: entry.id, referencing: entry.exerciseID)
        ) { try await harness.stack.trainingMaxes.saveConfiguration(entry) }

        #expect(try harness.store().fetch(FetchDescriptor<TrainingMaxConfigEntity>()).isEmpty)
    }

    @Test("Saving a training max appends rather than replacing the one it supersedes")
    func theHistoryIsKept() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id, effectiveFrom: Self.base, grams: 150_000))
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id, effectiveFrom: Self.base + Self.day, grams: 160_000))

        let history = try await stack.trainingMaxes.history(
            forExerciseID: exercise.id, includingDeleted: false)

        #expect(history.map(\.newWeight) == [Weight(grams: 160_000), Weight(grams: 150_000)])
    }

    @Test("A configuration appends the same way, and the two tables do not see each other")
    func theTwoTablesAreIndependent() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        try await stack.trainingMaxes.saveConfiguration(
            trainingMaxRecord(exerciseID: exercise.id, effectiveFrom: Self.base, percentage: 0.85))
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id, effectiveFrom: Self.base, grams: 140_000))

        #expect(
            try await stack.trainingMaxes.configurationHistory(
                forExerciseID: exercise.id, includingDeleted: false
            ).map(\.percentage) == [0.85])
        #expect(
            try await stack.trainingMaxes.history(
                forExerciseID: exercise.id, includingDeleted: false
            ).map(\.newWeight) == [Weight(grams: 140_000)])
    }

    // The guard this names is `recordNotFound` on a live row, and the arrangement reaches it: the
    // entry is saved first, so the delete stops on the second call rather than on the first.
    @Test("Deleting a history entry twice refuses the second time")
    func deletingTwiceRefuses() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let entry = trainingMaxHistoryRecord(exerciseID: exercise.id, effectiveFrom: Self.base)
        try await stack.trainingMaxes.save(entry)

        try await stack.trainingMaxes.deleteEntry(id: entry.id)

        await #expect(throws: RepositoryError.recordNotFound(id: entry.id)) {
            try await stack.trainingMaxes.deleteEntry(id: entry.id)
        }
        #expect(
            try await stack.trainingMaxes.trainingMax(
                forExerciseID: exercise.id, on: Self.base) == nil)
        #expect(
            try await stack.trainingMaxes.history(
                forExerciseID: exercise.id, includingDeleted: true
            ).count == 1)
    }
}

/// `NFR-15.2`: writing a training max never mutates already-logged work.
///
/// **A before-and-after snapshot of the tables rather than a spot check on one row.** The
/// requirement is about what a write *does not* touch, and a test naming three columns would pass
/// for a write that moved a fourth. Every row of each table is read whole — the columns a repository
/// reserves to itself included, since `updatedAt` moving is exactly the silent form this would take
/// (`G-2.4` keys its conflict resolution on it).
@Suite("A training max write touches nothing that was logged")
struct TrainingMaxIsolationTests {
    @Test("Writing a training max leaves every set, planned target and routine row untouched")
    func writingATrainingMaxTouchesNothingLogged() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord(name: "Squat")
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        try await stack.workouts.save(setRecord(entryID: entry.id))
        // The routine and planned tables are seeded as rows rather than written through their
        // repositories: what this test is about is whether they *move*, and how they arrived says
        // nothing about that.
        let routine = RoutineEntity(name: "Week 3, day 1")
        let slot = RoutineExerciseEntity(
            routineID: routine.id, exerciseID: exercise.id, order: 0)
        try harness.seed([
            routine,
            slot,
            RoutineTargetGroupEntity(
                routineExerciseID: slot.id,
                order: 0,
                targetWeightGrams: 120_000,
                targetReps: 5,
                targetSets: 3),
            PlannedTargetGroupEntity(
                exerciseEntryID: entry.id,
                order: 0,
                targetWeightGrams: 120_000,
                targetReps: 5,
                targetSets: 3),
        ])

        let before = try Self.snapshot(harness)
        try await stack.trainingMaxes.save(
            trainingMaxHistoryRecord(
                exerciseID: exercise.id,
                effectiveFrom: Date(timeIntervalSince1970: 1_600_000_000),
                grams: 180_000))
        let after = try Self.snapshot(harness)

        // The positive control: without it a snapshot helper that read nothing would report
        // "unchanged" for every table forever.
        #expect(before.isEmpty == false)
        #expect(after == before)
        #expect(
            try await stack.trainingMaxes.trainingMax(
                forExerciseID: exercise.id, on: Date(timeIntervalSince1970: 1_600_000_000))?
                .newWeight == Weight(grams: 180_000))
    }

    /// Every row of the four tables `NFR-15.2` names, as comparable text.
    ///
    /// - Parameter harness: The open store.
    /// - Returns: One line per row, sorted so two reads of an unchanged store agree.
    private static func snapshot(_ harness: RepositoryHarness) throws -> [String] {
        let context = harness.store()
        var lines: [String] = []
        for row in try context.fetch(FetchDescriptor<SetEntryEntity>()) {
            lines.append(
                line(
                    table: "set",
                    row: row,
                    columns: [
                        row.entryID, row.order, row.weightGrams, row.reps, row.rpe, row.rir,
                        row.modifiers, row.notes, row.targetWeightGrams, row.targetReps,
                        row.isWarmup, row.isCompleted, row.completedAt,
                    ]))
        }
        for row in try context.fetch(FetchDescriptor<PlannedTargetGroupEntity>()) {
            lines.append(
                line(
                    table: "planned",
                    row: row,
                    columns: [
                        row.exerciseEntryID, row.order, row.targetWeightGrams, row.targetReps,
                        row.targetSets,
                    ]))
        }
        for row in try context.fetch(FetchDescriptor<RoutineExerciseEntity>()) {
            lines.append(
                line(
                    table: "slot",
                    row: row,
                    columns: [row.routineID, row.exerciseID, row.order]))
        }
        for row in try context.fetch(FetchDescriptor<RoutineTargetGroupEntity>()) {
            lines.append(
                line(
                    table: "group",
                    row: row,
                    columns: [
                        row.routineExerciseID, row.order, row.targetWeightGrams, row.targetReps,
                        row.targetSets,
                    ]))
        }
        return lines.sorted()
    }

    /// One row as text — the four audit columns always, because `updatedAt` moving is the silent
    /// form this suite is looking for, and then whatever else the table holds.
    ///
    /// **Joined from a list rather than interpolated into one string**, which is not only style: a
    /// fourteen-part interpolation defeats the type checker outright here.
    ///
    /// - Parameters:
    ///   - table: What to call the row, so two tables cannot collide on one line.
    ///   - row: The row, read for its audit columns.
    ///   - columns: Everything else the table holds.
    /// - Returns: The line.
    private static func line(
        table: String,
        row: some StoredEntity,
        columns: [Any?]
    ) -> String {
        let audit: [Any?] = [table, row.id, row.createdAt, row.updatedAt, row.deletedAt]
        return (audit + columns)
            .map { $0.map { String(describing: $0) } ?? "-" }
            .joined(separator: " ")
    }
}
