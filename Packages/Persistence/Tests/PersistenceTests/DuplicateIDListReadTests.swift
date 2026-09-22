import Foundation
import PowerliftingCore
import RepositoryInterface
import SeedImport
import SwiftData
import Testing

@testable import Persistence

// FR-18.8.1, FR-18.8.2, DOD-18.10. What a list read does when two rows share an id — the state
// `G-2.5` leaves reachable and two synced installs actually produce.
//
// Every test here seeds the pair straight into a context, because a duplicate id is a state this
// layer refuses to produce: a save writes every row carrying the id and a delete sweeps every one
// of them, so no sequence of protocol calls reaches it. That is also why none of this can live in
// `RepositoryFakes` — those key each table by `id`, so the input is unrepresentable there.
//
// Each expectation is anchored to the winner **by a value**, never to `count == 1` alone: a read
// that kept the loser and dropped the winner satisfies the count and is exactly the defect.
//
// **One read per repository is what this file holds, and `DuplicateIDCallSiteTests` says why that
// is not the whole claim** — the other fourteen call sites the rule reached have their own tests
// there.

@Suite("A list read returns one row per id")
struct DuplicateIDListReadTests {
    @Test("The catalogue lists a duplicated exercise once")
    func exercisesListItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(exerciseRecord(id: id, name: "older"), as: ExerciseEntity.self, updatedAt: twinOlder),
            twin(exerciseRecord(id: id, name: "newer"), as: ExerciseEntity.self, updatedAt: twinNewer),
        ])

        #expect(
            try await harness.stack.exercises.exercises(includingDeleted: false).map(\.name)
                == ["newer"])
    }

    @Test("The profile list returns one row per id")
    func profilesListItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                profileRecord(id: id, name: "older"),
                as: EquipmentProfileEntity.self,
                updatedAt: twinOlder),
            twin(
                profileRecord(id: id, name: "newer"),
                as: EquipmentProfileEntity.self,
                updatedAt: twinNewer),
        ])

        #expect(
            try await harness.stack.equipment.profiles(includingDeleted: false).map(\.name)
                == ["newer"])
    }

    @Test("A dated range returns one bodyweight reading per id")
    func bodyweightListsItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                bodyweightRecord(id: id, grams: 80_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                bodyweightRecord(id: id, grams: 81_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.bodyweight.entries(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(read.map(\.weight.grams) == [81_000])
    }

    @Test("The routine list returns one row per id")
    func routinesListItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(routineRecord(id: id, name: "older"), as: RoutineEntity.self, updatedAt: twinOlder),
            twin(routineRecord(id: id, name: "newer"), as: RoutineEntity.self, updatedAt: twinNewer),
        ])

        #expect(
            try await harness.stack.routines.routines(includingDeleted: false).map(\.name)
                == ["newer"])
    }

    @Test("The program list returns one row per id")
    func programsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(programRecord(id: id, name: "older"), as: ProgramEntity.self, updatedAt: twinOlder),
            twin(programRecord(id: id, name: "newer"), as: ProgramEntity.self, updatedAt: twinNewer),
        ])

        #expect(
            try await harness.stack.programs.programs(includingDeleted: false).map(\.name)
                == ["newer"])
    }

    @Test("A dated range returns one session per id")
    func sessionsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                sessionRecord(id: id, notes: "older"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: id, notes: "newer"),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.sessions(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(read.map(\.notes) == ["newer"])
    }

    // The join-keyed form, and the reason the rule is per id rather than per table: this match set
    // is a list of *different* entry ids, any one of which may have been duplicated.
    @Test("A session's entries return one row per id")
    func entriesListItOnce() async throws {
        let harness = try RepositoryHarness()
        let session = UUID()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                entryRecord(id: id, sessionID: session, exerciseID: exercise, order: 0),
                as: ExerciseEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                entryRecord(id: id, sessionID: session, exerciseID: exercise, order: 3),
                as: ExerciseEntryEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.entries(
            forSessionID: session, includingDeleted: false)
        #expect(read.map(\.order) == [3])
    }

    @Test("An entry's sets return one row per id")
    func setsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let entry = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                setRecord(id: id, entryID: entry, grams: 100_000),
                as: SetEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                setRecord(id: id, entryID: entry, grams: 102_500),
                as: SetEntryEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.sets(forEntryID: entry, includingDeleted: false)
        #expect(read.map(\.weight.grams) == [102_500])
    }

    @Test("A training-max history returns one row per id")
    func trainingMaxHistoryListsItOnce() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                trainingMaxHistoryRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, grams: 180_000),
                as: TrainingMaxHistoryEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxHistoryRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, grams: 185_000),
                as: TrainingMaxHistoryEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.trainingMaxes.history(
            forExerciseID: exercise, includingDeleted: false)
        #expect(read.map(\.newWeight.grams) == [185_000])
    }

    // The derived table. Its rows are written by a reconciliation rather than by a save, and the
    // reconciliation keeps the raw read on purpose — it rewrites every duplicate — so this checks
    // the read alone.
    @Test("The record cache returns one row per id")
    func personalRecordsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            cachedRecord(id: id, exerciseID: exercise, grams: 140_000, updatedAt: twinOlder),
            cachedRecord(id: id, exerciseID: exercise, grams: 145_000, updatedAt: twinNewer),
        ])

        let all = try await harness.stack.personalRecords.personalRecords(includingDeleted: false)
        let byExercise = try await harness.stack.personalRecords.personalRecords(
            forExerciseID: exercise, includingDeleted: false)
        #expect(all.map(\.weight.grams) == [145_000])
        #expect(byExercise.map(\.weight.grams) == [145_000])
    }

    // The settings row is the one table with no resolved list read, and that is not an oversight:
    // neither of its two reads is a list read. `settings()` fetches every row, resolves among them
    // itself and returns one; `write(_:refusingAForeignIdentity:)` fetches every row and updates
    // all of them. Two installs bootstrap two settings rows with **different** ids, which rule 2
    // already decides; a duplicated settings *id* is resolved by the first and written by the
    // second exactly as a duplicated anything else is.
}

@Suite("Resolve first, then hide what was deleted")
struct DuplicateIDSoftDeleteTests {
    // THE ORDER IS THE TEST. A delete that reached one row of a pair is what a mirrored delete
    // looks like — the twins are separate CloudKit records — and a read that filtered before
    // resolving would answer from the live loser and put the deleted exercise back on the list.
    @Test("A delete that reached one row of a pair hides the record")
    func aOneSidedDeleteHidesIt() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let loser = twin(
            exerciseRecord(id: id, name: "older"), as: ExerciseEntity.self, updatedAt: twinOlder)
        let winner = twin(
            exerciseRecord(id: id, name: "newer"), as: ExerciseEntity.self, updatedAt: twinNewer)
        winner.markDeleted(at: twinNewer)
        try harness.seed([loser, winner])

        let exercises = harness.stack.exercises
        #expect(try await exercises.exercises(includingDeleted: false).isEmpty)
        #expect(try await exercises.exercise(id: id, includingDeleted: false) == nil)
        #expect(try await exercises.exercises(includingDeleted: true).map(\.name) == ["newer"])
        #expect(try await exercises.exercise(id: id, includingDeleted: true)?.name == "newer")
    }

    // The pair carries ONE weight on purpose, and it is not laziness. `deleteEntry(id:)` sweeps
    // every row of the id and `saveStamped(at:)` then writes one instant onto all of them, so after
    // the delete the twins are tied on `updatedAt` as well as on `id` — the residual
    // `RowResolution`'s header names, which nothing here invents a clause for. Twins that disagreed
    // about the weight would make this test assert which of two legal answers came back.
    @Test("A delete through the repository leaves nothing for the twin to resurface")
    func aSweepingDeleteHidesIt() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(
                bodyweightRecord(id: id, grams: 81_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                bodyweightRecord(id: id, grams: 81_000),
                as: BodyweightEntryEntity.self,
                updatedAt: twinNewer),
        ])

        try await harness.stack.bodyweight.deleteEntry(id: id)

        let range = Date.distantPast...Date.distantFuture
        let bodyweight = harness.stack.bodyweight
        #expect(try await bodyweight.entries(in: range, includingDeleted: false).isEmpty)
        #expect(try await bodyweight.entry(id: id, includingDeleted: false) == nil)
        let deleted = try await bodyweight.entries(in: range, includingDeleted: true)
        #expect(deleted.map(\.id) == [id])
        #expect(deleted.map(\.weight.grams) == [81_000])
        #expect(deleted.allSatisfy { $0.deletedAt != nil })
    }

    @Test("A save over a duplicated id leaves one row saying the new thing")
    func aSaveIsReadBackOnce() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(exerciseRecord(id: id, name: "older"), as: ExerciseEntity.self, updatedAt: twinOlder),
            twin(exerciseRecord(id: id, name: "newer"), as: ExerciseEntity.self, updatedAt: twinNewer),
        ])

        try await harness.stack.exercises.save(exerciseRecord(id: id, name: "edited"))

        #expect(
            try await harness.stack.exercises.exercises(includingDeleted: false).map(\.name)
                == ["edited"])
        // Both rows still carry the edit — the save writes every duplicate — so nothing stale is
        // left to win the next tie-break.
        let stored = try harness.store().fetch(FetchDescriptor<ExerciseEntity>())
        #expect(stored.count == 2)
        #expect(stored.allSatisfy { $0.name == "edited" })
    }
}

@Suite("Two seeded twins answer the same way every time")
struct DuplicateIDStabilityTests {
    // The residual `RowResolution`'s header names: one id, one `updatedAt`, no column left to
    // separate the pair. The order is total over what it compares and says nothing beyond that —
    // so what is pinned here is that the answer does not *move*. `fetchLimit = 1` over a tie
    // answered this 13/7 across runs; nothing may bring that back by another door.
    //
    // **THE TWINS DISAGREE ABOUT THE NAME, AND THEY HAVE TO.** Two installs seeding one catalogue
    // produce twins with *equal* contents, which is the benign form — and a fixture in that shape
    // cannot witness this claim at all: with both rows reading "Back Squat" no observation
    // distinguishes them, so the test collapses to `count == 1`, the one thing the header of this
    // file says never to anchor on alone. Measured: randomising the tie-break inside `oneRowPerID`
    // left the equal-contents version green. Naming the rows costs nothing, because the assertion
    // below still does not say *which* of the two is legal — only that twenty reads agree.
    @Test("Twenty reads of a tied pair give one row, and the same one")
    func aTiedPairIsStable() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        try harness.seed([
            twin(exerciseRecord(id: id, name: "left"), as: ExerciseEntity.self, updatedAt: twinNewer),
            twin(exerciseRecord(id: id, name: "right"), as: ExerciseEntity.self, updatedAt: twinNewer),
        ])

        var answers: Set<String> = []
        for _ in 0..<20 {
            let read = try await harness.stack.exercises.exercises(includingDeleted: false)
            #expect(read.count == 1)
            answers.formUnion(read.map(\.name))
        }
        #expect(answers.count == 1)
        #expect(answers.isSubset(of: ["left", "right"]))
    }
}

@Suite("A purge still sees both rows of a pair")
struct DuplicateIDPurgeTests {
    // WHY THE PURGE KEEPS THE RAW READ. It frees an id only when every row carrying it is
    // eligible, and it hard-deletes the rows it freed — so a purge that resolved first would
    // remove the winner and leave its twin, which is the one outcome worse than leaving both.
    @Test("A purged duplicate pair leaves neither row")
    func aPurgeTakesBothRows() async throws {
        let harness = try RepositoryHarness()
        let longAgo = Date(timeIntervalSince1970: 1_000_000)
        let cutoff = Date(timeIntervalSince1970: 1_500_000)
        let id = UUID()
        let loser = twin(
            exerciseRecord(id: id, name: "older"), as: ExerciseEntity.self, updatedAt: twinOlder)
        let winner = twin(
            exerciseRecord(id: id, name: "newer"), as: ExerciseEntity.self, updatedAt: twinNewer)
        loser.markDeleted(at: longAgo)
        winner.markDeleted(at: longAgo)
        try harness.seed([loser, winner])

        let report = try await harness.stack.purge(.deleted(onOrBefore: cutoff))

        #expect(report.removed == 2)
        #expect(try harness.store().fetch(FetchDescriptor<ExerciseEntity>()).isEmpty)
    }
}

@Suite("The catalogue seeded twice")
struct DoublySeededCatalogueTests {
    // DOD-18.10, and the state the author's phone is actually in: two installs that each seeded the
    // bundled catalogue locally and then mirrored, so every built-in is stored twice under one
    // permanent id.
    //
    // **`DOD-18.10` also asks for `ExerciseListState` and `ExerciseChoiceSections` over this
    // repository, and no target can run that.** `ExerciseChoiceSections` is `internal` to
    // `Dashboard`, `ExerciseListState` lives in `ExerciseLibrary`, and neither package may depend
    // on `Persistence` — a feature reaches storage through `RepositoryInterface` alone. Their own
    // suites use the fakes, which key each table by `id` and cannot hold the input at all. So the
    // claim is met one layer down, where it is decidable: both states are handed whatever
    // `exercises(includingDeleted:)` returns, and it returns each exercise once.
    @Test("A store holding the real catalogue twice lists 132 exercises")
    func aDoubledCatalogueListsEachOnce() async throws {
        let harness = try RepositoryHarness()
        try await SeedImporter(exercises: harness.stack.exercises).importBundledCatalogue()

        // The mirror's copy: the same rows, the same ids, arriving as separate records.
        let context = harness.store()
        for row in try context.fetch(FetchDescriptor<ExerciseEntity>()) {
            context.insert(ExerciseEntity(record: row.record))
        }
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ExerciseEntity>()).count == 264)

        let listed = try await harness.stack.exercises.exercises(includingDeleted: false)
        #expect(listed.count == 132)
        #expect(Set(listed.map(\.id)).count == 132)
    }
}
