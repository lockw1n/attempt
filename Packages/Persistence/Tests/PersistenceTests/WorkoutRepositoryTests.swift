import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("WorkoutRepository over SwiftData")
struct WorkoutRepositoryTests {
    @Test("Sessions in a range come back newest first, and the range excludes both ends' outsiders")
    func sessionsAreRangedAndOrdered() async throws {
        let stack = try RepositoryHarness().stack
        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let before = sessionRecord(date: base - day, notes: "before")
        let first = sessionRecord(date: base, notes: "first")
        let second = sessionRecord(date: base + day, notes: "second")
        let after = sessionRecord(date: base + 2 * day, notes: "after")
        for session in [before, first, second, after] { try await stack.workouts.save(session) }

        let read = try await stack.workouts.sessions(
            in: base...(base + day), includingDeleted: false)

        #expect(read.map(\.notes) == ["second", "first"])
    }

    @Test("Entries and sets come back in their own order field")
    func childrenAreOrdered() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)

        let second = entryRecord(sessionID: session.id, exerciseID: exercise.id, order: 1)
        let first = entryRecord(sessionID: session.id, exerciseID: exercise.id, order: 0)
        try await stack.workouts.save(second)
        try await stack.workouts.save(first)

        for order in [2, 0, 1] {
            try await stack.workouts.save(setRecord(entryID: first.id, order: order))
        }

        #expect(
            try await stack.workouts.entries(forSessionID: session.id, includingDeleted: false)
                .map(\.order) == [0, 1])
        #expect(
            try await stack.workouts.sets(forEntryID: first.id, includingDeleted: false)
                .map(\.order) == [0, 1, 2])
    }

    @Test("Deleting a session cascades to its entries and their sets")
    func deletingASessionCascades() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        let set = setRecord(entryID: entry.id)
        try await stack.workouts.save(set)

        // A second session that must not be touched — a cascade keyed on the wrong column would
        // take it, and every assertion below would still pass without it.
        let bystander = sessionRecord()
        try await stack.workouts.save(bystander)
        let bystanderEntry = entryRecord(sessionID: bystander.id, exerciseID: exercise.id)
        try await stack.workouts.save(bystanderEntry)
        let bystanderSet = setRecord(entryID: bystanderEntry.id)
        try await stack.workouts.save(bystanderSet)

        try await stack.workouts.deleteSession(id: session.id)

        #expect(try await stack.workouts.session(id: session.id, includingDeleted: false) == nil)
        #expect(
            try await stack.workouts.entries(forSessionID: session.id, includingDeleted: false)
                .isEmpty)
        #expect(try await stack.workouts.sets(forEntryID: entry.id, includingDeleted: false).isEmpty)

        #expect(try await stack.workouts.session(id: bystander.id, includingDeleted: false) != nil)
        #expect(
            try await stack.workouts.sets(forEntryID: bystanderEntry.id, includingDeleted: false)
                .count == 1)
    }

    @Test("The cascade lands in one write, so every swept row carries one timestamp")
    func theCascadeIsOneWrite() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        try await stack.workouts.save(setRecord(entryID: entry.id))

        try await stack.workouts.deleteSession(id: session.id)

        let context = harness.store()
        let stamps =
            try context.fetch(FetchDescriptor<WorkoutSessionEntity>()).compactMap(\.deletedAt)
            + context.fetch(FetchDescriptor<ExerciseEntryEntity>()).compactMap(\.deletedAt)
            + context.fetch(FetchDescriptor<SetEntryEntity>()).compactMap(\.deletedAt)
        #expect(stamps.count == 3)
        #expect(Set(stamps).count == 1)
    }

    @Test("A live set under an already-deleted entry is still swept with the session")
    func theCascadeReachesThroughADeletedEntry() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)

        // Only a sync or an import can produce this: an entry that is gone while its set is not.
        let entry = ExerciseEntryEntity(sessionID: session.id, exerciseID: exercise.id, order: 0)
        entry.markDeleted(at: fixtureCreatedAt)
        entry.updatedAt = fixtureCreatedAt
        try harness.seed([entry, loggedSet(entryID: entry.id, grams: 100_000)])

        try await stack.workouts.deleteSession(id: session.id)

        let context = harness.store()
        let sets = try context.fetch(FetchDescriptor<SetEntryEntity>())
        let deletedSets = sets.filter(\.isSoftDeleted).count
        #expect(deletedSets == sets.count)
        // …and the entry is not written at all: it keeps the date it actually left the user's
        // history AND the timestamp of the write that put it there. `deletedAt` alone does not say
        // that — `markDeleted` is idempotent in that column and moves `updatedAt` regardless — so
        // both are asserted, which is what makes the cascade's `isSoftDeleted` guard load-bearing.
        let entries = try context.fetch(FetchDescriptor<ExerciseEntryEntity>())
        #expect(entries.map(\.deletedAt) == [fixtureCreatedAt])
        #expect(entries.map(\.updatedAt) == [fixtureCreatedAt])
    }

    @Test("Deleting an entry takes its sets and leaves the session alone")
    func deletingAnEntryCascadesDownwardsOnly() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        try await stack.workouts.save(setRecord(entryID: entry.id))

        try await stack.workouts.deleteExerciseEntry(id: entry.id)

        #expect(try await stack.workouts.sets(forEntryID: entry.id, includingDeleted: false).isEmpty)
        #expect(try await stack.workouts.session(id: session.id, includingDeleted: false) != nil)
    }

    @Test("Deleting a set touches nothing else")
    func deletingASetCascadesNowhere() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)
        let doomed = setRecord(entryID: entry.id, order: 0)
        let survivor = setRecord(entryID: entry.id, order: 1)
        try await stack.workouts.save(doomed)
        try await stack.workouts.save(survivor)

        try await stack.workouts.deleteSet(id: doomed.id)

        #expect(
            try await stack.workouts.sets(forEntryID: entry.id, includingDeleted: false)
                .map(\.id) == [survivor.id])
        #expect(
            try await stack.workouts.entries(forSessionID: session.id, includingDeleted: false)
                .count == 1)
    }

    @Test("Every delete names a live row, and refuses when none does")
    func deletesRefuseAMissingRow() async throws {
        let stack = try RepositoryHarness().stack
        let absent = UUID()

        await #expect(throws: RepositoryError.recordNotFound(id: absent)) {
            try await stack.workouts.deleteSession(id: absent)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: absent)) {
            try await stack.workouts.deleteExerciseEntry(id: absent)
        }
        await #expect(throws: RepositoryError.recordNotFound(id: absent)) {
            try await stack.workouts.deleteSet(id: absent)
        }
    }

    @Test("A save carrying a join key that names no row is refused, not stored")
    func aDanglingReferenceIsRefused() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)

        let noSuchSession = entryRecord(sessionID: UUID(), exerciseID: exercise.id)
        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: noSuchSession.id, referencing: noSuchSession.sessionID)
        ) { try await stack.workouts.save(noSuchSession) }

        let noSuchExercise = entryRecord(sessionID: session.id, exerciseID: UUID())
        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: noSuchExercise.id, referencing: noSuchExercise.exerciseID)
        ) { try await stack.workouts.save(noSuchExercise) }

        let noSuchEntry = setRecord(entryID: UUID())
        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: noSuchEntry.id, referencing: noSuchEntry.entryID)
        ) { try await stack.workouts.save(noSuchEntry) }

        #expect(try harness.store().fetch(FetchDescriptor<ExerciseEntryEntity>()).isEmpty)
        #expect(try harness.store().fetch(FetchDescriptor<SetEntryEntity>()).isEmpty)
    }

    @Test("A soft-deleted target is not a dangling reference")
    func aDeletedParentStillAcceptsAChild() async throws {
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id)
        try await stack.workouts.save(entry)

        try await stack.workouts.deleteSession(id: session.id)

        // The entry was swept with the session. Re-saving it is an edit to a deleted row, which is
        // not a dangling reference — the session exists, it is just gone from the user's history.
        try await stack.workouts.save(entry)
        #expect(
            try await stack.workouts.entries(forSessionID: session.id, includingDeleted: true)
                .count == 1)
    }
}

@Suite("The personal-record feed's ordering")
struct WorkoutRepositorySetOrderingTests {
    /// Two sessions, three entries and seven sets, inserted in an order matching none of the three
    /// sort keys — so a repository that returned the fetch order, or sorted on any single key,
    /// answers differently.
    private func seededFeed() async throws -> SeededFeed {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        let other = exerciseRecord(name: "Deadlift")
        try await stack.exercises.save(exercise)
        try await stack.exercises.save(other)

        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let older = sessionRecord(date: base)
        let newer = sessionRecord(date: base + day)
        try await stack.workouts.save(newer)
        try await stack.workouts.save(older)

        // In the newer session the exercise is second; in the older one it is first. Sorting on
        // entry order alone would put the newer session's sets first.
        let newerEntry = entryRecord(sessionID: newer.id, exerciseID: exercise.id, order: 1)
        let olderEntry = entryRecord(sessionID: older.id, exerciseID: exercise.id, order: 0)
        // A third entry, same exercise, same older session, later in it.
        let olderSecond = entryRecord(sessionID: older.id, exerciseID: exercise.id, order: 2)
        // A bystander entry for a different exercise, which must not appear.
        let bystander = entryRecord(sessionID: older.id, exerciseID: other.id, order: 1)
        for entry in [newerEntry, olderSecond, bystander, olderEntry] {
            try await stack.workouts.save(entry)
        }

        // Weights encode the expected position, and the sets are saved out of order.
        try await stack.workouts.save(setRecord(entryID: newerEntry.id, order: 1, grams: 60))
        try await stack.workouts.save(setRecord(entryID: olderEntry.id, order: 1, grams: 20))
        try await stack.workouts.save(setRecord(entryID: olderSecond.id, order: 0, grams: 30))
        try await stack.workouts.save(
            setRecord(entryID: olderEntry.id, order: 0, grams: 10, isWarmup: true))
        try await stack.workouts.save(setRecord(entryID: newerEntry.id, order: 0, grams: 50))
        try await stack.workouts.save(
            setRecord(entryID: olderSecond.id, order: 1, grams: 40, isCompleted: false))
        try await stack.workouts.save(setRecord(entryID: bystander.id, order: 0, grams: 999))

        return SeededFeed(
            harness: harness, exerciseID: exercise.id, expected: [10, 20, 30, 40, 50, 60])
    }

    @Test("Sets sort by session date, then entry order, then set order — oldest first")
    func theFeedIsOrderedByAllThreeKeys() async throws {
        let seeded = try await seededFeed()

        let feed = try await seeded.harness.stack.workouts.sets(
            forExerciseID: seeded.exerciseID, includingDeleted: false)

        #expect(feed.map(\.weight.grams) == seeded.expected)
    }

    @Test("Warmups and incomplete sets are included, because an offset is a position")
    func nothingIsPreFiltered() async throws {
        let seeded = try await seededFeed()

        let feed = try await seeded.harness.stack.workouts.sets(
            forExerciseID: seeded.exerciseID, includingDeleted: false)

        #expect(feed.count == seeded.expected.count)
        #expect(feed.contains { $0.isWarmup })
        #expect(feed.contains { !$0.isCompleted })
    }

    @Test("Sets sharing all three keys order by id, which is a claim about the answer")
    func theOrderIsTotalRatherThanMerelyStable() async throws {
        // `order` is not unique, so three sets can tie on the whole stated key. Asserting only that
        // the answer is *repeatable* is not enough — a probe showed it passes with the fourth clause
        // removed, because one store's fetch order does not vary within a run. The claim has to be
        // which order, so this pins the ids' own.
        let stack = try RepositoryHarness().stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord()
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id, order: 0)
        try await stack.workouts.save(entry)

        let tied = [
            (UUID(uuidString: "cccccccc-0000-0000-0000-000000000000") ?? UUID(), 30),
            (UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000000") ?? UUID(), 10),
            (UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000000") ?? UUID(), 20),
        ]
        for (id, grams) in tied {
            try await stack.workouts.save(
                setRecord(id: id, entryID: entry.id, order: 0, grams: grams))
        }

        let feed = try await stack.workouts.sets(
            forExerciseID: exercise.id, includingDeleted: false)

        #expect(feed.map(\.weight.grams) == [10, 20, 30])
    }

    @Test("A live set under a deleted session keeps that session's date for ordering")
    func aDeletedSessionStillSuppliesItsDate() async throws {
        // The session is read for its date rather than for itself, so the third fetch takes deleted
        // rows whatever the caller asked for. Filtering there would cost the *ordering* of a set the
        // caller did ask for — it would fall to the orphan position, last.
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)

        let day = 86_400.0
        let base = Date(timeIntervalSince1970: 1_600_000_000)
        let earlier = sessionRecord(date: base)
        let later = sessionRecord(date: base + day)
        try await stack.workouts.save(earlier)
        try await stack.workouts.save(later)
        for (session, grams) in [(earlier, 10), (later, 20)] {
            let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id, order: 0)
            try await stack.workouts.save(entry)
            try await stack.workouts.save(setRecord(entryID: entry.id, order: 0, grams: grams))
        }

        // The earlier session alone is deleted, its entry and set left live — a state only a sync
        // can produce, since the cascade would have taken them.
        let context = harness.store()
        for row in try context.fetch(FetchDescriptor<WorkoutSessionEntity>())
        where row.id == earlier.id {
            row.markDeleted()
        }
        try context.save()

        let feed = try await stack.workouts.sets(
            forExerciseID: exercise.id, includingDeleted: false)

        #expect(feed.map(\.weight.grams) == [10, 20])
    }

    @Test("A set whose session row is missing sorts last, and is not dropped")
    func anOrphanSortsLast() async throws {
        let harness = try RepositoryHarness()
        let stack = harness.stack
        let exercise = exerciseRecord()
        try await stack.exercises.save(exercise)
        let session = sessionRecord(date: Date(timeIntervalSince1970: 1_600_000_000))
        try await stack.workouts.save(session)
        let entry = entryRecord(sessionID: session.id, exerciseID: exercise.id, order: 0)
        try await stack.workouts.save(entry)
        try await stack.workouts.save(setRecord(entryID: entry.id, order: 0, grams: 10))

        // An entry naming a session that is not there — only a sync or an import can write one, so
        // the store is where it goes.
        let orphanEntry = ExerciseEntryEntity(sessionID: UUID(), exerciseID: exercise.id, order: 0)
        try harness.seed([orphanEntry, loggedSet(entryID: orphanEntry.id, grams: 99)])

        let feed = try await stack.workouts.sets(
            forExerciseID: exercise.id, includingDeleted: false)

        // Last, not first: earliest is the position that wins every TR-0.2.8 tie, and a row this
        // app did not write must not land there. Present, because dropping it would shift offsets.
        #expect(feed.map(\.weight.grams) == [10, 99])
    }
}

/// A completed working set, for the rows a repository cannot write.
private func loggedSet(entryID: UUID, grams: Int) -> SetEntryEntity {
    SetEntryEntity(
        entryID: entryID,
        order: 0,
        weightGrams: grams,
        reps: 5,
        isWarmup: false,
        isCompleted: true
    )
}

/// The feed fixture and what it should read back as.
private struct SeededFeed {
    let harness: RepositoryHarness
    let exerciseID: UUID
    let expected: [Int]
}
