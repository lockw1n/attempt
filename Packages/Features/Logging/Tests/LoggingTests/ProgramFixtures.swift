import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

// `DOD-16.1`'s fixture: week #2 of the author's own plan file, as a program of three days over
// three routines, with a run in force. Every `FR-16.8` suite here starts from it.

/// The day every record in the fixture is stamped with, at file scope so the helpers below can be
/// called while the fixture is still initialising.
private let programFixtureDay = Date(timeIntervalSince1970: 1_700_000_000)

/// One target group as a suite compares it: which exercise, and the three numbers.
struct PrescribedTarget: Equatable {
    /// The catalogue exercise the slot names.
    let exerciseID: UUID

    /// The load, in grams, or `nil` where the target is blank.
    let grams: Int?

    /// Repetitions per set.
    let reps: Int

    /// How many sets.
    let sets: Int
}

/// A program of three days — squat, bench, deadlift — with a run open on week 2, day 0.
///
/// **Three days over three routines rather than one routine twice**, because the two things
/// `FR-16.8.4` has to get right are per-day: which session rebuilt which day, and which replaced
/// routine may be archived.
@MainActor
struct ProgramFixture {
    let stack = InMemoryRepositoryStack()

    let squat = UUID()
    let bench = UUID()
    let deadlift = UUID()

    let programID = UUID()
    let runID = UUID()

    /// The three routines, in day order.
    private(set) var routineIDs: [UUID] = []

    /// The three days, in order.
    private(set) var dayIDs: [UUID] = []

    let today = programFixtureDay

    /// The week the run opens on — `#2` of the plan file (`DOD-16.1`).
    static let week = 2

    /// The squat's training max, in grams — `DOD-16.1`'s 140 kg (`FR-15.1.4`, T-16.12).
    ///
    /// The third of the three things the exit criterion asks the app to hold, beside the program
    /// and the routines: a week of a plan file is a set of days *and* the number its loads are
    /// written against.
    static let trainingMaxGrams = 140_000

    init() async throws {
        for (id, name) in [(squat, "Back Squat"), (bench, "Bench Press"), (deadlift, "Deadlift")] {
            try await stack.exercises.save(
                Exercise(
                    id: id,
                    createdAt: today,
                    updatedAt: today,
                    deletedAt: nil,
                    name: name,
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
                    manualE1RM: nil))
        }
        try await stack.programs.save(
            Program(
                id: programID,
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                name: "Course #2",
                notes: ""))
        let plan = [("Squat day", squat), ("Bench day", bench), ("Pull day", deadlift)]
        for (index, spec) in plan.enumerated() {
            let routineID = try await writeRoutine(named: spec.0, exerciseID: spec.1)
            routineIDs.append(routineID)
            let dayID = UUID()
            dayIDs.append(dayID)
            try await stack.programs.save(
                ProgramDay(
                    id: dayID,
                    createdAt: today,
                    updatedAt: today,
                    deletedAt: nil,
                    programID: programID,
                    routineID: routineID,
                    order: index))
        }
        try await writeTrainingMax()
        try await stack.programs.startRun(
            ProgramRun(
                id: runID,
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                programID: programID,
                startedAt: today,
                endedAt: nil,
                weekNumber: Self.week,
                nextDayIndex: 0))
    }

    /// The squat's manual training max, configuration and history entry both (`FR-15.1.4`).
    ///
    /// Both rows, because they answer different questions: the configuration is *how* the number
    /// is arrived at and the history entry is the number in force from a date.
    private func writeTrainingMax() async throws {
        try await stack.trainingMaxes.saveConfiguration(
            TrainingMaxEntry(
                id: UUID(),
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                exerciseID: squat,
                source: .manual,
                sourceRepCount: nil,
                percentage: 1,
                roundingIncrement: Weight(grams: 2_500),
                roundingStrategy: .nearest,
                progressionIncrement: nil,
                effectiveFrom: today))
        try await stack.trainingMaxes.save(
            TrainingMaxHistoryEntry(
                id: UUID(),
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                exerciseID: squat,
                effectiveFrom: today,
                oldWeight: nil,
                newWeight: Weight(grams: Self.trainingMaxGrams),
                reason: ""))
    }

    /// A one-exercise routine prescribing 100 kg × 5 × 3.
    private func writeRoutine(named name: String, exerciseID: UUID) async throws -> UUID {
        let routineID = UUID()
        let slotID = UUID()
        try await stack.routines.save(
            Routine(
                id: routineID, createdAt: today, updatedAt: today, deletedAt: nil, name: name))
        try await stack.routines.save(
            RoutineExercise(
                id: slotID,
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                routineID: routineID,
                exerciseID: exerciseID,
                order: 0))
        try await stack.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                routineExerciseID: slotID,
                order: 0,
                targetWeight: Weight(grams: 100_000),
                targetReps: 5,
                targetSets: 3))
        return routineID
    }

    /// A store over the fixture's stack.
    ///
    /// - Parameter refusingRunSaves: Whether the cursor write refuses, for the tests that need
    ///   ``ActiveSessionStore/programAdvanceFailure`` to be reachable.
    /// - Returns: The store.
    func store(refusingRunSaves: Bool = false) -> ActiveSessionStore {
        guard refusingRunSaves else { return ActiveSessionStore.over(stack) }
        var programs = RefusingProgramRepository(wrapped: stack.programs)
        programs.refusesRunSave = true
        return ActiveSessionStore.over(stack, programs: programs)
    }

    /// Train's reading of the run in force, over the fixture's stack.
    ///
    /// - Parameter programs: The program store to read and write through, or `nil` for the
    ///   stack's own — a substitute is how a refused write is reached.
    /// - Returns: The state.
    func nextUpState(programs: (any ProgramRepository)? = nil) -> ProgramNextUpState {
        ProgramNextUpState(
            programs: programs ?? stack.programs,
            routines: stack.routines,
            workouts: stack.workouts)
    }

    /// Starts the program's day `index`, logs `sets` sets of `grams` × `reps`, and finishes.
    ///
    /// - Parameters:
    ///   - index: The day to train — its `ProgramDay.order`.
    ///   - store: The store to log through.
    ///   - grams: The load on every set, or `nil` to finish having logged nothing (a skipped day).
    ///   - reps: The repetitions on every set.
    ///   - sets: How many sets.
    /// - Returns: The finished session's identifier.
    @discardableResult
    func train(
        day index: Int, through store: ActiveSessionStore, grams: Int?, reps: Int = 5, sets: Int = 3
    ) async throws -> UUID {
        let nextUp = nextUpState()
        await nextUp.load()
        let reading = try #require(nextUp.nextUp)
        guard case .next(let order, let routineID, _) = reading.day else {
            Issue.record("day \(index) is not the next one up")
            throw CancellationError()
        }
        #expect(order == index)
        #expect(
            await store.start(
                on: today,
                in: ProgramSessionStamp(
                    runID: reading.runID, weekNumber: reading.weekNumber, dayIndex: order),
                fromRoutineID: routineID,
                using: stack.routines))
        let sessionID = try #require(store.session).id
        if let grams {
            let entryID = try #require(store.exercises.first).entry.id
            for _ in 0..<sets {
                await store.addSet(
                    toEntryID: entryID,
                    values: SetEntryValues(
                        weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false))
            }
        }
        await store.finish()
        return sessionID
    }

    /// Writes a finished session against `index`, with the identifier and start time given.
    ///
    /// **Written through the repository rather than through the store**, which is the point: the
    /// store mints its own identifier, and this is how a suite pins the one the repository's
    /// same-date tie-break would otherwise resolve on.
    ///
    /// - Parameters:
    ///   - id: The session's identifier.
    ///   - index: The `ProgramDay.order` it is stamped with.
    ///   - startedAt: When it was started. Its training day is the fixture's, whatever this is.
    ///   - grams: The load on its one set.
    /// - Throws: Whatever the repository throws.
    func logFinishedSession(id: UUID, day index: Int, startedAt: Date, grams: Int) async throws {
        try await stack.workouts.save(
            WorkoutSession(
                id: id,
                createdAt: startedAt,
                updatedAt: startedAt,
                deletedAt: nil,
                date: today,
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(3_600),
                notes: "",
                bodyweight: nil,
                programRunID: runID,
                scheduledWorkoutID: nil,
                weekNumber: Self.week,
                dayIndex: index))
        let entryID = UUID()
        try await stack.workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: startedAt,
                updatedAt: startedAt,
                deletedAt: nil,
                sessionID: id,
                exerciseID: squat,
                order: 0,
                notes: ""))
        try await stack.workouts.save(
            SetEntry(
                id: UUID(),
                createdAt: startedAt,
                updatedAt: startedAt,
                deletedAt: nil,
                entryID: entryID,
                order: 0,
                weight: Weight(grams: grams),
                reps: 5,
                rpe: nil,
                rir: nil,
                isWarmup: false,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: startedAt))
    }

    /// The targets one routine prescribes, flattened for comparison.
    func targets(ofRoutineID routineID: UUID) async throws -> [PrescribedTarget] {
        var flattened: [PrescribedTarget] = []
        for slot in try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false
        ) {
            for group in try await stack.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ) {
                flattened.append(
                    PrescribedTarget(
                        exerciseID: slot.exerciseID,
                        grams: group.targetWeight?.grams,
                        reps: group.targetReps,
                        sets: group.targetSets))
            }
        }
        return flattened
    }

    /// Which routine each day of the program names now, in day order.
    func currentRoutineIDs() async throws -> [UUID] {
        try await stack.programs.days(forProgramID: programID, includingDeleted: false)
            .map(\.routineID)
    }
}
