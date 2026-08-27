import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// The recompute pipeline over a real store: what it computes, what it caches, and what it leaves
/// alone (`FR-1.6.1`, `FR-1.6.4`, `TR-1.6`, `G-1.5`).
@Suite("Personal record recompute")
struct PersonalRecordRecomputerTests {
    @Test("A 5-rep set holds every rep max from 1 to 5, and none above it")
    func aSetHoldsEveryRepMaxUpToItsReps() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(records.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(records.repMaxes.allSatisfy { $0.record.weight == Weight(grams: 100_000) })
        #expect(records.repMax(forReps: 6) == nil)
    }

    @Test("Warmups and failed sets hold no record")
    func onlyWorkingSetsCount() async throws {
        let fixture = try await oneSession(
            sets: [
                LoggedSet(grams: 200_000, reps: 5, isWarmup: true, isCompleted: true),
                LoggedSet(grams: 180_000, reps: 5, isWarmup: false, isCompleted: false),
                working(100_000, 5),
            ])

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        // The heaviest two rows are excluded by `G-1.8`'s two columns, so 100 kg is the 5RM.
        #expect(records.repMax(forReps: 5)?.weight == Weight(grams: 100_000))
        #expect(records.repMax(forReps: 1)?.weight == Weight(grams: 100_000))
    }

    @Test("A record is dated by its session's training day, not by when it was entered")
    func aRecordIsDatedByItsSession() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(6), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        #expect(records.repMax(forReps: 5)?.achievedAt == weeksAgo(6))
        // Anchored against the fallback as well as against the literal: the set claims a later
        // `completedAt`, so dating it from the set rather than the session is a visible failure.
        #expect(records.repMax(forReps: 5)?.achievedAt != weeksAgo(6).addingTimeInterval(enteredLate))
    }

    @Test("The record names the set that holds it, so a screen can link to it")
    func aRecordNamesItsSourceSet() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(80_000, 5), working(120_000, 3)])
        let logged = try await log.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        #expect(records.repMax(forReps: 3)?.sourceSetID == logged[1].id)
        #expect(records.repMax(forReps: 5)?.sourceSetID == logged[0].id)
    }

    /// **The offset invariant, which is the subtle way this could be wrong.** `PersonalRecord`
    /// reports a position in the collection the calculator was handed, and a set `SetRecord` refuses
    /// is not in that collection — so a record's identity has to be resolved against the *filtered*
    /// sequence. Resolving it against what the repository returned names the wrong set, plausibly,
    /// and only for exercises that happen to hold such a row.
    @Test("A set the analytical type refuses costs that set and not the exercise's records")
    func arefusedSetDoesNotShiftTheOthers() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(of: exerciseID, on: weeksAgo(2), sets: [])
        // First in the collection, and unreadable: an RPE outside 1…10 is what a newer version's row
        // or a corrupt one looks like, and the column stores it unvalidated.
        try await log.repositories.workouts.save(
            log.setEntry(entryID: entryID, order: 0, on: weeksAgo(2), rpe: 47, working(90_000, 5)))
        let readable = log.setEntry(entryID: entryID, order: 1, on: weeksAgo(2), working(110_000, 5))
        try await log.repositories.workouts.save(readable)
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        // The exercise keeps its records, and the record names the set that actually holds it.
        #expect(records.repMax(forReps: 5)?.weight == Weight(grams: 110_000))
        #expect(records.repMax(forReps: 5)?.sourceSetID == readable.id)
        #expect(records.bestE1RM?.sourceSetID == readable.id)
    }

    @Test("A recompute writes the N-rep maxes and stamps them with the rules version")
    func aRecomputeWritesTheCache() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])

        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        let cached = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false)
        #expect(cached.map(\.repCount) == [1, 2, 3, 4, 5])
        #expect(
            cached.allSatisfy {
                $0.computationVersion == PersonalRecordCalculator.computationVersion
            })
        #expect(cached.allSatisfy { $0.weight == Weight(grams: 100_000) })
    }

    /// **`TR-0.3.9`'s omission, asserted rather than assumed.** A best e1RM depends on a formula
    /// setting and a version cannot carry one, so the cache must never gain a row for it — which is
    /// the kind of thing a later reader helpfully adds.
    @Test("The estimate is computed and never cached")
    func theEstimateIsNotCached() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(records.bestE1RM != nil)
        let cached = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: true)
        // Every cached row is one of the ten N-rep maxes; nothing else was written.
        #expect(cached.allSatisfy { PersonalRecords.repRange.contains($0.repCount) })
        #expect(cached.count == 5)
    }

    @Test("A different formula gives a different estimate and the same rep maxes")
    func theFormulaMovesOnlyTheEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])
        let epley = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            formula: .epley,
            now: { fixtureNow })
        let brzycki = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            formula: .brzycki,
            now: { fixtureNow })

        let underEpley = try await epley.recompute(forExerciseID: exerciseID)
        let underBrzycki = try await brzycki.recompute(forExerciseID: exerciseID)

        #expect(underEpley.bestE1RM?.weight != underBrzycki.bestE1RM?.weight)
        #expect(underEpley.repMaxes == underBrzycki.repMaxes)
    }

    // MARK: - G-1.5, the version

    @Test("A cache the current rules produced is read rather than recomputed")
    func aCurrentCacheIsRead() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)
        let counting = CountingWorkouts(wrapped: fixture.log.repositories.workouts)
        let reader = PersonalRecordRecomputer(
            workouts: counting,
            exercises: InMemoryRepositoryStack().exercises,
            cache: fixture.log.repositories.personalRecords,
            now: { fixtureNow })

        let read = try await reader.repMaxes(forExerciseID: fixture.exerciseID)

        #expect(read.map(\.reps) == [1, 2, 3, 4, 5])
        // The walk is what `NFR-1.6` is about, so "did not recompute" is asserted as "did not walk".
        #expect(await counting.exerciseWalks == 0)
    }

    @Test("A cache another rules version produced is recomputed")
    func aStaleVersionIsInvalidated() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        try await fixture.log.repositories.personalRecords.replacePersonalRecords(
            forExerciseID: fixture.exerciseID,
            with: [
                PersonalRecordCacheValues(
                    repCount: 5,
                    weight: Weight(grams: 999_000),
                    sourceSetID: UUID(),
                    achievedAt: weeksAgo(50),
                    computationVersion: PersonalRecordCalculator.computationVersion + 1)
            ])

        let read = try await fixture.recomputer.repMaxes(forExerciseID: fixture.exerciseID)

        #expect(read.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(read.allSatisfy { $0.record.weight == Weight(grams: 100_000) })
    }

    /// A defaulted column holds zero, which `G-1.5` reserves for "no version recorded" — a row
    /// nothing computed must not read as current.
    @Test("A row at the reserved zero is not current")
    func versionZeroIsNeverCurrent() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        try await fixture.log.repositories.personalRecords.replacePersonalRecords(
            forExerciseID: fixture.exerciseID,
            with: [
                PersonalRecordCacheValues(
                    repCount: 5,
                    weight: Weight(grams: 999_000),
                    sourceSetID: UUID(),
                    achievedAt: weeksAgo(50),
                    computationVersion: 0)
            ])

        let read = try await fixture.recomputer.repMaxes(forExerciseID: fixture.exerciseID)

        #expect(read.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))
    }

    /// **Every row, not just one.** A cache half-written under an older version would otherwise be
    /// read as current on the strength of whichever row happened to be checked.
    @Test("One stale row invalidates the whole exercise's cache")
    func oneStaleRowIsEnough() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)
        var mixed = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false
        ).map {
            PersonalRecordCacheValues(
                repCount: $0.repCount,
                weight: Weight(grams: 999_000),
                sourceSetID: $0.sourceSetID,
                achievedAt: $0.achievedAt,
                computationVersion: PersonalRecordCalculator.computationVersion)
        }
        mixed[2] = PersonalRecordCacheValues(
            repCount: mixed[2].repCount,
            weight: mixed[2].weight,
            sourceSetID: mixed[2].sourceSetID,
            achievedAt: mixed[2].achievedAt,
            computationVersion: 0)
        try await fixture.log.repositories.personalRecords.replacePersonalRecords(
            forExerciseID: fixture.exerciseID, with: mixed)

        let read = try await fixture.recomputer.repMaxes(forExerciseID: fixture.exerciseID)

        // The planted 999 kg is gone from every rep count, not only from the stale one.
        #expect(read.allSatisfy { $0.record.weight == Weight(grams: 100_000) })
    }

    // MARK: - FR-1.6.4, the triggers and their scope

    @Test("A set change recomputes the exercise its entry names")
    func aSetChangeRecomputesItsExercise() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])

        await fixture.recomputer.setDidChange(inEntryID: fixture.entryID)

        let cached = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false)
        #expect(cached.map(\.repCount) == [1, 2, 3, 4, 5])
    }

    /// `FR-1.6.4`'s scope, and `NFR-1.6`'s reason for it: a set edited six sessions back must not
    /// make the app walk a catalogue.
    @Test("Editing a set six sessions ago recomputes that exercise and no other")
    func anEditRecomputesOneExerciseOnly() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        var oldest: UUID?
        for week in stride(from: 6, through: 1, by: -1) {
            let entryID = try await log.session(
                of: squat, on: weeksAgo(week), sets: [working(90_000 + week * 1_000, 5)])
            if week == 6 { oldest = entryID }
        }
        try await log.session(of: bench, on: weeksAgo(3), sets: [working(70_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: counting,
            exercises: InMemoryRepositoryStack().exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: bench)
        let benchBefore = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: bench, includingDeleted: false)
        await counting.reset()

        let entryID = try #require(oldest)
        let sets = try await log.repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        try await log.repositories.workouts.save(
            log.setEntry(
                entryID: entryID,
                order: 0,
                on: weeksAgo(6),
                id: sets[0].id,
                working(200_000, 5)))
        await recomputer.setDidChange(inEntryID: entryID)

        // One walk, and it was the squat's.
        #expect(await counting.walkedExercises == [squat])
        let squatCache = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: squat, includingDeleted: false)
        #expect(squatCache.first { $0.repCount == 5 }?.weight == Weight(grams: 200_000))
        // The other exercise's rows are the ones it already had, restamped by nothing.
        let benchAfter = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: bench, includingDeleted: false)
        #expect(benchAfter == benchBefore)
    }

    @Test("An entry that cannot be resolved recomputes nothing and does not throw")
    func anUnknownEntryIsSilent() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])

        await fixture.recomputer.setDidChange(inEntryID: UUID())

        #expect(
            try await fixture.log.repositories.personalRecords.personalRecords(
                forExerciseID: fixture.exerciseID, includingDeleted: true
            ).isEmpty)
    }

    /// `FR-1.2.12`'s discard cascades to every set under the session without writing a single set
    /// column, so none of ``setDidChange(inEntryID:)``'s five call sites fires.
    @Test("A discarded session's records stop standing, for every exercise it touched")
    func aSessionChangeRecomputesEveryExerciseInIt() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let entryID = try await log.session(
            of: squat, on: weeksAgo(1), sets: [working(100_000, 5)])
        try await log.session(of: bench, on: weeksAgo(1), sets: [working(70_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        let entry = try #require(
            try await log.repositories.workouts.entry(id: entryID, includingDeleted: false))
        try await log.repositories.workouts.deleteSession(id: entry.sessionID)

        await recomputer.sessionDidChange(id: entry.sessionID)

        let squatCache = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: squat, includingDeleted: false)
        #expect(squatCache.isEmpty)
        // The other exercise trained that day was in a different session and is untouched.
        let benchSets = try await log.repositories.workouts.sets(
            forExerciseID: bench, includingDeleted: false)
        #expect(benchSets.count == 1)
    }

    @Test("A formula change touches no cached record")
    func aFormulaChangeLeavesTheCacheAlone() async throws {
        let fixture = try await oneSession(sets: [working(100_000, 5)])
        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)
        let before = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false)

        await fixture.recomputer.formulaDidChange(to: .brzycki)

        let after = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false)
        #expect(after == before)
        #expect(await fixture.recomputer.formulaInForce() == .brzycki)
    }
}

/// One exercise trained once, and the recomputer over the store it was logged into.
struct Fixture {
    /// The store, so a test can read the cache back or log another set.
    let log: TrainingLog

    /// The exercise trained.
    let exerciseID: UUID

    /// Its entry in the session — what a set-change trigger is given.
    let entryID: UUID

    /// The subject.
    let recomputer: PersonalRecordRecomputer
}

/// A log holding one exercise trained once, and the recomputer over it.
func oneSession(sets: [LoggedSet]) async throws -> Fixture {
    let log = TrainingLog()
    let exerciseID = try await log.exercise()
    let entryID = try await log.session(of: exerciseID, on: weeksAgo(1), sets: sets)
    return Fixture(
        log: log,
        exerciseID: exerciseID,
        entryID: entryID,
        recomputer: PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow }))
}

/// Counts what was walked, so "did not recompute" can be asserted as "did not read the sets".
actor CountingWorkouts: WorkoutRepository {
    private let wrapped: any WorkoutRepository

    /// The exercises whose whole history was read, in order.
    private(set) var walkedExercises: [UUID] = []

    /// How many such walks there have been.
    var exerciseWalks: Int { walkedExercises.count }

    /// How many ranged session reads there have been — `FR-1.7.1`'s window, and nothing else in
    /// this pipeline, asks for sessions by date.
    private(set) var windowReads = 0

    init(wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// Forgets what has been walked and read so far.
    func reset() {
        walkedExercises = []
        windowReads = 0
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        walkedExercises.append(exerciseID)
        return try await wrapped.sets(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        windowReads += 1
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
}
