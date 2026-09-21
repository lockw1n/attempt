import Foundation
import PowerliftingCore
import RepositoryInterface
import SeedImport
import SwiftData
import Testing

@testable import Persistence

// FR-18.8.1, applied per *call site* — which is not the claim its sibling file makes.
//
// `DuplicateIDListReadTests` covers one read per repository. That is what `DOD-18.10`'s checklist
// asks for and it is not enough on its own: the rule was applied at sixty-odd call sites, and a
// review probe returned fourteen of them to the raw read with every test in this package still
// green. A read nothing pins is a read the next task may quietly revert. So each of the fourteen
// has one test here, and each was confirmed to fail with its own site — and only its own site —
// back on `allRows`.
//
// The pair-building helpers are in `DuplicateIDFixtures`; every expectation is anchored to a
// literal rather than to `count == 1`, for the reason stated there.

@Suite("Every other list read resolves too")
struct DuplicateIDRemainingListReadTests {
    @Test("A run's sessions for a week return one row per id")
    func programRunSessionsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let run = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                sessionRecord(id: id, notes: "older", programRunID: run, weekNumber: 1, dayIndex: 0),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: id, notes: "newer", programRunID: run, weekNumber: 1, dayIndex: 0),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.sessions(
            forProgramRunID: run, week: 1, includingDeleted: false)
        #expect(read.map(\.notes) == ["newer"])
    }

    @Test("A program's days return one row per id")
    func programDaysListItOnce() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let routine = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                programDayRecord(id: id, programID: program, routineID: routine, order: 0),
                as: ProgramDayEntity.self,
                updatedAt: twinOlder),
            twin(
                programDayRecord(id: id, programID: program, routineID: routine, order: 2),
                as: ProgramDayEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.programs.days(
            forProgramID: program, includingDeleted: false)
        #expect(read.map(\.order) == [2])
    }

    @Test("A program's runs return one row per id")
    func programRunsListItOnce() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                programRunRecord(id: id, programID: program, weekNumber: 1),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(id: id, programID: program, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.programs.runs(
            forProgramID: program, includingDeleted: false)
        #expect(read.map(\.weekNumber) == [4])
    }

    @Test("A routine's slots return one row per id")
    func routineExercisesListItOnce() async throws {
        let harness = try RepositoryHarness()
        let routine = UUID()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            stamped(
                RoutineExerciseEntity(routineID: routine, exerciseID: exercise, order: 0),
                id: id,
                updatedAt: twinOlder),
            stamped(
                RoutineExerciseEntity(routineID: routine, exerciseID: exercise, order: 3),
                id: id,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.routines.exercises(
            forRoutineID: routine, includingDeleted: false)
        #expect(read.map(\.order) == [3])
    }

    @Test("A slot's target groups return one row per id")
    func targetGroupsListThemOnce() async throws {
        let harness = try RepositoryHarness()
        let slot = UUID()
        let id = UUID()
        try harness.seed([
            stamped(
                RoutineTargetGroupEntity(
                    routineExerciseID: slot,
                    order: 0,
                    targetWeightGrams: 90_000,
                    targetReps: 8,
                    targetSets: 3),
                id: id,
                updatedAt: twinOlder),
            stamped(
                RoutineTargetGroupEntity(
                    routineExerciseID: slot,
                    order: 0,
                    targetWeightGrams: 90_000,
                    targetReps: 4,
                    targetSets: 3),
                id: id,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.routines.targetGroups(
            forRoutineExerciseID: slot, includingDeleted: false)
        #expect(read.map(\.targetReps) == [4])
    }

    @Test("An entry's planned groups return one row per id")
    func plannedTargetsListThemOnce() async throws {
        let harness = try RepositoryHarness()
        let entry = UUID()
        let id = UUID()
        try harness.seed([
            stamped(
                PlannedTargetGroupEntity(
                    exerciseEntryID: entry,
                    order: 0,
                    targetWeightGrams: 100_000,
                    targetReps: 8,
                    targetSets: 3),
                id: id,
                updatedAt: twinOlder),
            stamped(
                PlannedTargetGroupEntity(
                    exerciseEntryID: entry,
                    order: 0,
                    targetWeightGrams: 100_000,
                    targetReps: 5,
                    targetSets: 3),
                id: id,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.plannedTargets(
            forEntryID: entry, includingDeleted: false)
        #expect(read.map(\.targetReps) == [5])
    }

    @Test("A training-max configuration history returns one row per id")
    func configurationHistoryListsItOnce() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                trainingMaxRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, percentage: 0.9),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, percentage: 0.85),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.trainingMaxes.configurationHistory(
            forExerciseID: exercise, includingDeleted: false)
        #expect(read.map(\.percentage) == [0.85])
    }
}

// The four reads that pick one row out of a match set on a key of their own — the latest
// `effectiveFrom`, the latest `startedAt`, the flag — *after* the list read has run. Collapsing the
// pair first is what decides these: a loser carrying a later lookup key wins the second pick and
// answers with a row no resolved read would ever have handed over.
@Suite("A pick over a match set picks among resolved rows")
struct DuplicateIDMatchSetPickTests {
    @Test("A stale twin claiming a later start is not the current run")
    func theCurrentRunIsTheResolvedOne() async throws {
        let harness = try RepositoryHarness()
        let program = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                programRunRecord(
                    id: id, programID: program, startedAt: twinNewer, weekNumber: 1),
                as: ProgramRunEntity.self,
                updatedAt: twinOlder),
            twin(
                programRunRecord(
                    id: id, programID: program, startedAt: twinOlder, weekNumber: 4),
                as: ProgramRunEntity.self,
                updatedAt: twinNewer),
        ])

        // The loser started later, so a raw match set would hand it back; the resolved one holds
        // only the row rule 2 picked.
        #expect(try await harness.stack.programs.currentRun()?.weekNumber == 4)
    }

    @Test("A stale twin claiming a later effective date is not the configuration in force")
    func theConfigurationInForceIsTheResolvedOne() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                trainingMaxRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinNewer, percentage: 0.7),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, percentage: 0.85),
                as: TrainingMaxConfigEntity.self,
                updatedAt: twinNewer),
        ])

        let inForce = try await harness.stack.trainingMaxes.configuration(
            forExerciseID: exercise, on: Date.distantFuture)
        #expect(inForce?.percentage == 0.85)
    }

    @Test("A stale twin claiming a later effective date is not the training max in force")
    func theTrainingMaxInForceIsTheResolvedOne() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let id = UUID()
        try harness.seed([
            twin(
                trainingMaxHistoryRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinNewer, grams: 150_000),
                as: TrainingMaxHistoryEntity.self,
                updatedAt: twinOlder),
            twin(
                trainingMaxHistoryRecord(
                    id: id, exerciseID: exercise, effectiveFrom: twinOlder, grams: 185_000),
                as: TrainingMaxHistoryEntity.self,
                updatedAt: twinNewer),
        ])

        let inForce = try await harness.stack.trainingMaxes.trainingMax(
            forExerciseID: exercise, on: Date.distantFuture)
        #expect(inForce?.newWeight.grams == 185_000)
    }

    // This one turns on the delete filter rather than on a lookup key, because the flag is the
    // same on both halves: `defaultProfile` resolves the match set itself, so what only the
    // resolved read can do here is hide a pair whose winner was deleted.
    @Test("A deleted profile's live twin is not the default")
    func aDeletedDefaultDoesNotResurface() async throws {
        let harness = try RepositoryHarness()
        let id = UUID()
        let winner = markedProfile(id: id, name: "newer", updatedAt: twinNewer)
        winner.markDeleted(at: twinNewer)
        try harness.seed([markedProfile(id: id, name: "older", updatedAt: twinOlder), winner])

        #expect(try await harness.stack.equipment.defaultProfile() == nil)
    }
}

// The feed makes three reads of its own and each one is a resolved read (`FR-18.8.1`). This is the
// method that used to carry its own `Dictionary(grouping:)` + ``resolved(_:)`` over the entries and
// the sessions; that pass is gone and the reads do it, so all three need pinning here rather than
// in the per-table suite above.
@Suite("The exercise feed resolves each of its three reads")
struct DuplicateIDFeedTests {
    @Test("A deleted entry's live twin puts no sets in the feed")
    func theEntryReadResolves() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let session = UUID()
        let entry = UUID()
        let liveTwin = twin(
            entryRecord(id: entry, sessionID: session, exerciseID: exercise, order: 0),
            as: ExerciseEntryEntity.self,
            updatedAt: twinOlder)
        let deletedWinner = twin(
            entryRecord(id: entry, sessionID: session, exerciseID: exercise, order: 0),
            as: ExerciseEntryEntity.self,
            updatedAt: twinNewer)
        deletedWinner.markDeleted(at: twinNewer)
        try harness.seed([
            ExerciseEntity(record: exerciseRecord(id: exercise, name: "Back Squat")),
            WorkoutSessionEntity(record: sessionRecord(id: session)),
            liveTwin,
            deletedWinner,
            SetEntryEntity(record: setRecord(entryID: entry, grams: 100_000)),
        ])

        let read = try await harness.stack.workouts.sets(
            forExerciseID: exercise, includingDeleted: false)
        #expect(read.isEmpty)
    }

    @Test("A duplicated set appears in the feed once")
    func theSetReadResolves() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let session = UUID()
        let entry = UUID()
        let id = UUID()
        try harness.seed([
            ExerciseEntity(record: exerciseRecord(id: exercise, name: "Back Squat")),
            WorkoutSessionEntity(record: sessionRecord(id: session)),
            ExerciseEntryEntity(
                record: entryRecord(id: entry, sessionID: session, exerciseID: exercise)),
            twin(
                setRecord(id: id, entryID: entry, grams: 100_000),
                as: SetEntryEntity.self,
                updatedAt: twinOlder),
            twin(
                setRecord(id: id, entryID: entry, grams: 102_500),
                as: SetEntryEntity.self,
                updatedAt: twinNewer),
        ])

        let read = try await harness.stack.workouts.sets(
            forExerciseID: exercise, includingDeleted: false)
        #expect(read.map(\.weight.grams) == [102_500])
    }

    // The session read only feeds the ordering key, so this is what it looks like from outside: the
    // twins disagree about the day, and the feed's oldest-first order says which one was read.
    //
    // **The assertion is one answer; the probe that kills a raw read here is not.** A raw read
    // would collapse the pair by writing each row into a dictionary in fetch order, so *which*
    // twin survived would be the store's choice rather than rule 2's — and this fixture only
    // catches it because that order happens to leave the early twin last. Measured: seeding the
    // pair the other way round left the mutant green. The resolved read has no such freedom, which
    // is the whole point of the read owning the collapse.
    @Test("A duplicated session orders the feed by the resolved row's date")
    func theSessionReadResolves() async throws {
        let harness = try RepositoryHarness()
        let exercise = UUID()
        let duplicated = UUID()
        let other = UUID()
        let early = Date(timeIntervalSince1970: 1_500_000_000)
        let middle = Date(timeIntervalSince1970: 1_700_000_000)
        let late = Date(timeIntervalSince1970: 1_900_000_000)
        let firstEntry = UUID()
        let secondEntry = UUID()
        try harness.seed([
            ExerciseEntity(record: exerciseRecord(id: exercise, name: "Back Squat")),
            twin(
                sessionRecord(id: duplicated, date: early),
                as: WorkoutSessionEntity.self,
                updatedAt: twinOlder),
            twin(
                sessionRecord(id: duplicated, date: late),
                as: WorkoutSessionEntity.self,
                updatedAt: twinNewer),
            WorkoutSessionEntity(record: sessionRecord(id: other, date: middle)),
            ExerciseEntryEntity(
                record: entryRecord(
                    id: firstEntry, sessionID: duplicated, exerciseID: exercise)),
            ExerciseEntryEntity(
                record: entryRecord(id: secondEntry, sessionID: other, exerciseID: exercise)),
            SetEntryEntity(record: setRecord(entryID: firstEntry, grams: 111_000)),
            SetEntryEntity(record: setRecord(entryID: secondEntry, grams: 222_000)),
        ])

        let read = try await harness.stack.workouts.sets(
            forExerciseID: exercise, includingDeleted: false)
        #expect(read.map(\.weight.grams) == [222_000, 111_000])
    }
}
