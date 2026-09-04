import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.2`'s engine over a real store: which runs the walk sees, what it caches, and what the
/// `FR-1.6.x` readers still see (`TR-16.1`, `FR-16.2.1`–`FR-16.2.5`).
@Suite("Scheme record recompute")
struct SchemeRecordRecomputeTests {
    /// The record at one cell of what a recompute produced.
    private func cell(_ records: ExerciseRecords, _ reps: Int, _ sets: Int) -> DatedSchemeRecord? {
        records.schemeRecord(for: RecordScheme(reps: reps, sets: sets))
    }

    // MARK: - FR-16.2.1, the runs the engine counts

    @Test("Five consecutive fives fill the rectangle, and the cache holds all of it")
    func aRunFillsItsRectangle() async throws {
        let fixture = try await oneSession(
            sets: Array(repeating: working(100_000, 5), count: 5))

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(records.schemeRecords.count == 25)
        #expect(cell(records, 5, 5)?.record.weight == Weight(grams: 100_000))
        #expect(cell(records, 5, 6) == nil)
        let cached = try await fixture.log.repositories.personalRecords.personalRecords(
            forExerciseID: fixture.exerciseID, includingDeleted: false)
        #expect(cached.count == 25)
        #expect(cached.map(\.setCount).max() == 5)
    }

    /// The trap `T-16.01`'s review named: grouping a list the failures have already been dropped
    /// from joins sets a dropped one stood between, and here that fabricated run would be **written
    /// down as a record**.
    @Test("A failed set between two equal completed ones does not make a run of two")
    func aDroppedSetEndsTheRun() async throws {
        let fixture = try await oneSession(
            sets: [
                working(100_000, 5),
                LoggedSet(grams: 100_000, reps: 5, isWarmup: false, isCompleted: false),
                working(100_000, 5),
            ])

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(cell(records, 5, 1)?.record.weight == Weight(grams: 100_000))
        #expect(cell(records, 5, 2) == nil)
        #expect(records.schemeRecords.map(\.scheme.sets).max() == 1)
    }

    @Test("A warmup between two equal working sets does not make a run of two")
    func aWarmupEndsTheRun() async throws {
        let fixture = try await oneSession(
            sets: [
                working(100_000, 5),
                LoggedSet(grams: 100_000, reps: 5, isWarmup: true, isCompleted: true),
                working(100_000, 5),
            ])

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(cell(records, 5, 1)?.record.weight == Weight(grams: 100_000))
        #expect(cell(records, 5, 2) == nil)
    }

    /// A run never crosses an entry boundary, so two days of `× 3` are not a `× 6`.
    @Test("Two sessions of three sets are two runs of three, never one of six")
    func aRunNeverCrossesAnEntry() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: Array(repeating: working(100_000, 5), count: 3))
        try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: Array(repeating: working(100_000, 5), count: 3))
        let recomputer = recomputer(over: log)

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        #expect(cell(records, 5, 3)?.record.weight == Weight(grams: 100_000))
        #expect(cell(records, 5, 4) == nil)
    }

    /// The grain is pinned at `.loadAndReps`: a record is a load and a scheme, and a rating that
    /// drifted across one set of a run is not a second scheme.
    @Test("A rating on one set of a run does not split the run")
    func aRatingDoesNotSplitARun() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: Array(repeating: working(100_000, 5), count: 4))
        let stored = try await log.repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        try await log.repositories.workouts.save(
            log.setEntry(
                entryID: entryID,
                order: 2,
                on: weeksAgo(1),
                id: stored[2].id,
                rpe: 8,
                working(100_000, 5)))
        let recomputer = recomputer(over: log)

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        #expect(cell(records, 5, 4)?.record.weight == Weight(grams: 100_000))
        // The `.displayed` grain would break the run at the rated set and cap this at three.
        #expect(records.schemeRecords.map(\.scheme.sets).max() == 4)
    }

    // MARK: - FR-16.2.3, the load a record beat, through the cache

    @Test("A first run is a baseline and the next heavier one carries what it beat")
    func aBeatenLoadSurvivesTheCache() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: Array(repeating: working(100_000, 5), count: 5))
        let recomputer = recomputer(over: log)
        let baseline = try await recomputer.recompute(forExerciseID: exerciseID)
        #expect(cell(baseline, 5, 5)?.previous == nil)
        #expect(cell(baseline, 5, 5)?.isBaseline == true)

        try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: Array(repeating: working(105_000, 5), count: 5))
        try await recomputer.recompute(forExerciseID: exerciseID)

        // Read back off the cache, not off the walk that wrote it.
        let read = try await recomputer.schemeRecords(forExerciseID: exerciseID)
        let improved = read.first { $0.scheme == RecordScheme(reps: 5, sets: 5) }
        #expect(improved?.record.weight == Weight(grams: 105_000))
        #expect(improved?.previous == Weight(grams: 100_000))
        #expect(improved?.delta == Weight(grams: 5_000))
        #expect(improved?.isBaseline == false)
    }

    @Test("Repeating a run beats nothing and leaves the record where it was")
    func anEqualRunIsNotARecord() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: Array(repeating: working(100_000, 5), count: 5))
        let first = try await log.repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: Array(repeating: working(100_000, 5), count: 5))
        let recomputer = recomputer(over: log)

        let records = try await recomputer.recompute(forExerciseID: exerciseID)

        #expect(cell(records, 5, 5)?.previous == nil)
        #expect(cell(records, 5, 5)?.record.sourceSetID == first[0].id)
        #expect(cell(records, 5, 5)?.record.achievedAt == weeksAgo(2))
    }

    /// The record names the run's **first** set, at every cell the run filled — which is what makes
    /// `FR-1.6.5`'s feed group one run into one event rather than into up to sixty.
    @Test("Every cell a run fills names the run's first set")
    func everyCellNamesTheRunsFirstSet() async throws {
        let fixture = try await oneSession(
            sets: Array(repeating: working(100_000, 5), count: 5))
        let stored = try await fixture.log.repositories.workouts.sets(
            forExerciseID: fixture.exerciseID, includingDeleted: false)

        let records = try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        #expect(records.schemeRecords.allSatisfy { $0.record.sourceSetID == stored[0].id })
        #expect(Set(stored.map(\.id)).count == 5)
    }

    // MARK: - FR-1.6.x and FR-16.2.5, what did not change

    @Test("The rep-max read is the one-set column and nothing else")
    func repMaxesAreTheOneSetColumn() async throws {
        let fixture = try await oneSession(
            sets: Array(repeating: working(100_000, 5), count: 5))
        try await fixture.recomputer.recompute(forExerciseID: fixture.exerciseID)

        let repMaxes = try await fixture.recomputer.repMaxes(forExerciseID: fixture.exerciseID)

        #expect(repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(repMaxes.allSatisfy { $0.record.weight == Weight(grams: 100_000) })
    }

    /// `FR-16.2.5`: a scheme record never feeds e1RM. Four identical sets estimate exactly what one
    /// of them does — the group is invisible to the estimator.
    @Test("A grouped run estimates what its best single member does")
    func aRunDoesNotMoveTheEstimate() async throws {
        let grouped = try await oneSession(
            sets: Array(repeating: working(100_000, 5), count: 4))
        let single = try await oneSession(sets: [working(100_000, 5)])

        let fromRun = try await grouped.recomputer.estimatedMax(forExerciseID: grouped.exerciseID)
        let fromSet = try await single.recomputer.estimatedMax(forExerciseID: single.exerciseID)

        #expect(fromRun.weight == fromSet.weight)
        // Anchored, so two absences cannot agree: Epley over 100 kg × 5 is 116.667 kg.
        #expect(fromSet.weight == Weight(grams: 116_667))
        #expect(fromRun.record?.sourceSetID != nil)
    }

    /// The recomputer over `log`, with the fixtures' fixed clock.
    private func recomputer(over log: TrainingLog) -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
    }
}
