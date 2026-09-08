import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

/// The day every record in a week fixture is stamped with.
let weekFixtureDay = Date(timeIntervalSince1970: 1_700_000_000)

/// A program of `days` days, each a routine of `exercisesPerDay` slots prescribing 100 kg × 5 × 3,
/// with a run open on week 2 (`FR-17.8.1`).
///
/// **Its shape is a parameter rather than three fixtures**, because `DOD-17.12` is a claim about
/// two of them at once — two days and six — and a fixture per size is a fixture per size to keep in
/// step.
@MainActor
struct WeekFixture {
    let stack = InMemoryRepositoryStack()
    let programID = UUID()
    let runID = UUID()

    /// The week the run opens on.
    static let week = 2

    /// The routines the days name, in day order.
    private(set) var routineIDs: [UUID] = []

    /// The catalogue rows each day prescribes, in day order.
    private(set) var exerciseIDs: [[UUID]] = []

    /// Builds the program, its routines and the run.
    ///
    /// - Parameters:
    ///   - days: How many days the program has.
    ///   - exercisesPerDay: How many slots each day's routine carries.
    init(days: Int, exercisesPerDay: Int = 1) async throws {
        try await stack.programs.save(
            Program(
                id: programID,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                name: "Course #2",
                notes: ""))
        for index in 0..<days {
            let routineID = try await writeRoutine(day: index, slots: exercisesPerDay)
            routineIDs.append(routineID)
            try await stack.programs.save(
                ProgramDay(
                    id: UUID(),
                    createdAt: weekFixtureDay,
                    updatedAt: weekFixtureDay,
                    deletedAt: nil,
                    programID: programID,
                    routineID: routineID,
                    order: index))
        }
        try await stack.programs.startRun(
            ProgramRun(
                id: runID,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                programID: programID,
                startedAt: weekFixtureDay,
                endedAt: nil,
                weekNumber: Self.week,
                nextDayIndex: 0))
    }

    /// One day's routine, its slots and their targets.
    private mutating func writeRoutine(day index: Int, slots: Int) async throws -> UUID {
        let routineID = UUID()
        try await stack.routines.save(
            Routine(
                id: routineID,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                name: "Day \(index + 1)"))
        var ids: [UUID] = []
        for slot in 0..<slots {
            let exerciseID = UUID()
            ids.append(exerciseID)
            try await stack.exercises.save(
                Exercise(
                    id: exerciseID,
                    createdAt: weekFixtureDay,
                    updatedAt: weekFixtureDay,
                    deletedAt: nil,
                    name: "Lift \(index + 1)-\(slot + 1)",
                    ukrainianName: nil,
                    movement: .squat,
                    parentExerciseID: nil,
                    equipment: .barbell,
                    laterality: .bilateral,
                    barType: .standard,
                    implementCount: 1,
                    isCustom: false,
                    isArchived: false,
                    notes: ""))
            let slotID = UUID()
            try await stack.routines.save(
                RoutineExercise(
                    id: slotID,
                    createdAt: weekFixtureDay,
                    updatedAt: weekFixtureDay,
                    deletedAt: nil,
                    routineID: routineID,
                    exerciseID: exerciseID,
                    order: slot))
            try await stack.routines.save(
                RoutineTargetGroup(
                    id: UUID(),
                    createdAt: weekFixtureDay,
                    updatedAt: weekFixtureDay,
                    deletedAt: nil,
                    routineExerciseID: slotID,
                    order: 0,
                    targetWeight: Weight(grams: 100_000),
                    targetReps: 5,
                    targetSets: 3))
        }
        exerciseIDs.append(ids)
        return routineID
    }

    /// Writes a session stamped with the run, the week and `day`, with `done` of its exercises
    /// answered.
    ///
    /// - Parameters:
    ///   - day: The `ProgramDay.order` the session is stamped with.
    ///   - done: How many of the day's exercises are marked done (`FR-15.3.4`).
    ///   - date: The training day, so a done card's date is assertable.
    ///   - week: The week stamped on it, for the test that a foreign week is not this one's.
    /// - Returns: The session's identifier.
    @discardableResult
    func log(
        day: Int,
        done: Int,
        on date: Date = weekFixtureDay,
        week: Int = WeekFixture.week
    ) async throws -> UUID {
        let sessionID = UUID()
        try await stack.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                date: date,
                startedAt: date,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: runID,
                scheduledWorkoutID: nil,
                weekNumber: week,
                dayIndex: day))
        for (order, exerciseID) in exerciseIDs[day].enumerated() {
            try await stack.workouts.save(
                ExerciseEntry(
                    id: UUID(),
                    createdAt: date,
                    updatedAt: date,
                    deletedAt: nil,
                    sessionID: sessionID,
                    exerciseID: exerciseID,
                    order: order,
                    notes: "",
                    isMarkedDone: order < done))
        }
        return sessionID
    }

    /// Writes a session stamped with the run, the week and `day`, and **no entries at all**.
    ///
    /// The state a day is in the instant it is opened, before `T-17.11` writes a row into it. It
    /// cannot be reached through ``log(day:done:on:week:)``, which writes the day's plan out.
    ///
    /// - Parameters:
    ///   - day: The `ProgramDay.order` the session is stamped with.
    ///   - date: The training day.
    /// - Returns: The session's identifier.
    @discardableResult
    func logEmptySession(day: Int, on date: Date = weekFixtureDay) async throws -> UUID {
        let sessionID = UUID()
        try await stack.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                date: date,
                startedAt: date,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: runID,
                scheduledWorkoutID: nil,
                weekNumber: Self.week,
                dayIndex: day))
        return sessionID
    }

    /// The week, over the fixture's stack.
    ///
    /// - Parameter workouts: The workout store to read through, or `nil` for the stack's own — a
    ///   substitute is how `NFR-17.4`'s counting fake is reached.
    /// - Returns: The state.
    func weekState(workouts: (any WorkoutRepository)? = nil) -> WeekState {
        WeekState(
            programs: stack.programs,
            routines: stack.routines,
            workouts: workouts ?? stack.workouts,
            exercises: stack.exercises)
    }

    /// The day's session, as `T-17.11`'s commands wrote it.
    ///
    /// - Parameter day: The `ProgramDay.order`.
    /// - Returns: The session.
    /// - Throws: Whatever the repository throws, or a failure where no session was written.
    func session(day: Int) async throws -> WorkoutSession {
        let sessions = try await stack.workouts.sessions(
            forProgramRunID: runID, week: Self.week, includingDeleted: false)
        guard let session = sessions.first(where: { $0.dayIndex == day }) else {
            throw WeekFixtureFailure.noSession
        }
        return session
    }

    /// The first entry of a day's session, in the routine's own order.
    ///
    /// - Parameter day: The `ProgramDay.order`.
    /// - Returns: The entry's identifier.
    /// - Throws: Whatever the repository throws, or a failure where the session has no entries.
    func firstEntryID(day: Int) async throws -> UUID {
        let entries = try await stack.workouts.entries(
            forSessionID: try await session(day: day).id, includingDeleted: false)
        guard let first = entries.first else { throw WeekFixtureFailure.noEntries }
        return first.id
    }

    /// The sets logged against that entry.
    ///
    /// - Parameter day: The `ProgramDay.order`.
    /// - Returns: The sets, in order.
    /// - Throws: Whatever the repository throws.
    func setsOfFirstEntry(day: Int) async throws -> [SetEntry] {
        try await stack.workouts.sets(
            forEntryID: try await firstEntryID(day: day), includingDeleted: false)
    }

    /// A set nobody has attempted, as an import leaves one (`FR-16.4.1`).
    ///
    /// - Parameters:
    ///   - entryID: The exercise it belongs to.
    ///   - order: Its position.
    /// - Throws: Whatever the repository throws.
    func writePendingSet(entryID: UUID, order: Int) async throws {
        try await stack.workouts.save(
            SetEntry(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                entryID: entryID,
                order: order,
                weight: Weight(grams: 100_000),
                reps: 5,
                rpe: nil,
                rir: nil,
                isWarmup: false,
                isCompleted: false,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: nil))
    }

    /// Adds a slot to a day's routine prescribing reps and no load (`FR-15.2.2`).
    ///
    /// The row `FR-17.9.2`'s circle refuses, and the one `FR-17.9.9`'s **Log remaining** reports
    /// rather than answers.
    ///
    /// - Parameter day: The `ProgramDay.order` whose routine gains the slot.
    /// - Throws: Whatever the repository throws.
    func addOpenLoadSlot(day: Int) async throws {
        let exerciseID = UUID()
        try await stack.exercises.save(
            Exercise(
                id: exerciseID,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                name: "Ab Wheel",
                ukrainianName: nil,
                movement: .other,
                parentExerciseID: nil,
                equipment: .bodyweight,
                laterality: .bilateral,
                barType: .noBar,
                implementCount: 1,
                isCustom: false,
                isArchived: false,
                notes: ""))
        let slotID = UUID()
        let existing = try await stack.routines.exercises(
            forRoutineID: routineIDs[day], includingDeleted: false)
        try await stack.routines.save(
            RoutineExercise(
                id: slotID,
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                routineID: routineIDs[day],
                exerciseID: exerciseID,
                order: existing.count))
        try await stack.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                routineExerciseID: slotID,
                order: 0,
                targetWeight: nil,
                targetReps: 12,
                targetSets: 3))
    }

    /// A workout store over this fixture's stack.
    ///
    /// **A fresh one per call, so a test that needs the app's single store has to say so** by
    /// handing the same one to every ``DayStore`` it builds — which is the thing under test
    /// wherever a day and a free workout are both open (``SessionLocator``).
    func activeStore() -> ActiveSessionStore {
        .over(stack)
    }

    /// One day of the week, over the fixture's stack.
    ///
    /// - Parameters:
    ///   - dayIndex: The `ProgramDay.order` the route carried.
    ///   - runID: The run it carried — the fixture's own unless a test is asking for a stale stamp.
    ///   - week: The week it carried, likewise.
    ///   - store: The workout store to write through, or `nil` for a fresh one over this stack.
    /// - Returns: The store.
    func dayStore(
        dayIndex: Int,
        runID: UUID? = nil,
        week: Int = WeekFixture.week,
        store: ActiveSessionStore? = nil
    ) -> DayStore {
        DayStore(
            runID: runID ?? self.runID,
            week: week,
            dayIndex: dayIndex,
            store: store ?? activeStore(),
            programs: stack.programs,
            routines: stack.routines,
            exercises: stack.exercises)
    }

    /// The days the week read, or an empty list where it read no run.
    ///
    /// - Parameter state: The state, already loaded.
    /// - Returns: The cards.
    static func days(of state: WeekState) -> [WeekDayCard] {
        guard case .week(_, _, _, let days) = state.reading else { return [] }
        return days
    }
}

/// A free workout — no program, and still open (`FR-17.8.3`).
///
/// - Parameter endedAt: When it was finished, or `nil` while it is in progress.
/// - Returns: The session.
func freeWorkoutSession(endedAt: Date? = nil) -> WorkoutSession {
    WorkoutSession(
        id: UUID(),
        createdAt: weekFixtureDay,
        updatedAt: weekFixtureDay,
        deletedAt: nil,
        date: weekFixtureDay,
        startedAt: weekFixtureDay,
        endedAt: endedAt,
        notes: "",
        bodyweight: nil,
        programRunID: nil,
        scheduledWorkoutID: nil)
}

/// The states `T-17.11` needs that a plain week does not have — an open-load backoff, a warmup, and
/// a workout no program planned.
///
/// **An extension rather than three more members**, the struct being at `type_body_length`'s
/// ceiling: these are shapes a particular claim needs rather than part of what a week *is*.
extension WeekFixture {
    /// Adds a second target group to a day's **first** slot prescribing reps and no load.
    ///
    /// **A backoff on a row that already has a load**, which is the case
    /// ``DayRowCircle/isOffered(answer:plan:)``'s "every group has to name a load, not merely the
    /// first" exists for — and the one ``addOpenLoadSlot(day:)`` cannot produce, that adding a
    /// whole row instead.
    ///
    /// - Parameter day: The `ProgramDay.order` whose first slot gains the group.
    /// - Throws: Whatever the repository throws.
    func addOpenLoadBackoff(day: Int) async throws {
        let slots = try await stack.routines.exercises(
            forRoutineID: routineIDs[day], includingDeleted: false)
        guard let slot = slots.first else { throw WeekFixtureFailure.noEntries }
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)
        try await stack.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                routineExerciseID: slot.id,
                order: groups.count,
                targetWeight: nil,
                targetReps: 8,
                targetSets: 2))
    }

    /// A completed warmup set, as a lifter who warmed up and stopped leaves one.
    ///
    /// - Parameters:
    ///   - entryID: The exercise it belongs to.
    ///   - order: Its position.
    /// - Throws: Whatever the repository throws.
    func writeWarmupSet(entryID: UUID, order: Int) async throws {
        try await stack.workouts.save(
            SetEntry(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                entryID: entryID,
                order: order,
                weight: Weight(grams: 40_000),
                reps: 5,
                rpe: nil,
                rir: nil,
                isWarmup: true,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: weekFixtureDay))
    }

    /// A workout in progress that no program planned (`FR-17.8.3`).
    ///
    /// Written straight to the repository rather than through a store, so a test can have one open
    /// *beside* a day's session without either store having been pointed at it.
    ///
    /// - Returns: The session.
    /// - Throws: Whatever the repository throws.
    @discardableResult
    func writeFreeWorkout() async throws -> WorkoutSession {
        let session = WorkoutSession(
            id: UUID(),
            createdAt: weekFixtureDay,
            updatedAt: weekFixtureDay,
            deletedAt: nil,
            date: weekFixtureDay,
            startedAt: weekFixtureDay,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil,
            weekNumber: nil,
            dayIndex: nil)
        try await stack.workouts.save(session)
        return session
    }
}

/// What a fixture helper refuses with when the state a test asked about was never written.
///
/// An error rather than an `Issue.record` at the call site, so the helper composes with `try` in a
/// test that is asserting something else.
enum WeekFixtureFailure: Error {
    /// No session is stamped with that day.
    case noSession

    /// The day's session has no entries.
    case noEntries
}
