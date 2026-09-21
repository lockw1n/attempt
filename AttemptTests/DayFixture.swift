import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import SwiftUI

@testable import Attempt

/// One planned day, over the app's own composition, with every write to it counted.
///
/// **A program rather than a stub, because the screens have to work.** `DayView` is addressed by
/// `(runID, week, dayIndex)` and reads its plan through the program and the routine that day names
/// (`FR-15.2.1`); handed a stamp that resolves to nothing it draws the empty state, where "Done
/// wrote nothing" is a claim about a screen with nothing on it. One program, one day, one routine,
/// one exercise — the smallest shape that draws a circle.
///
/// **The repositories are `AppDependencies.preview`'s**, so what is under test is what
/// `RootTabView` composes; only the workout repository is wrapped, and only to count.
@MainActor
struct DayFixture {
    /// What the exercise the day prescribes is called.
    static let exerciseName = "Back Squat"

    /// What an unanswered row's circle reads — `logging.day.circle.action` in `en`.
    static let circle = "Log as planned"

    /// What the overflow menu reads — `logging.day.menu.action` in `en`. Named for the menu
    /// rather than for any item in it (`G-4.2`), which is why it is not "Reset day".
    static let menu = "Day options"

    /// The week the run is open on.
    static let week = 1

    /// The repositories the screens read through.
    let repositories: AppDependencies.Repositories

    /// The app-lifetime stores the screens are handed.
    let stores: AppDependencies.Stores

    /// Every write that reached storage.
    let writes = WriteCounter()

    /// The program run the day is stamped with.
    let runID = UUID()

    /// The workout store the screens write through — over the counting repository, not the app's.
    let store: ActiveSessionStore

    /// Opens the in-memory store and writes the day into it.
    init() async throws {
        guard case .open(let repositories, let stores) = AppDependencies.preview.state else {
            throw FixtureFailure.storeDidNotOpen
        }
        self.repositories = repositories
        self.stores = stores
        let counting = CountingWorkoutRepository(wrapped: repositories.workouts, writes: writes)
        store = ActiveSessionStore(
            repository: counting,
            catalogue: repositories.exercises,
            settings: repositories.settings,
            records: stores.records,
            trainingMaxes: repositories.trainingMaxes,
            programs: repositories.programs)
        try await writeTheProgram()
    }

    /// The day as `RootTabView` builds it.
    ///
    /// **Edit plan does nothing here, and a recorder would be worse than nothing** (`FR-18.7.2`).
    /// The real one sets the week editor's open day and pushes `Route.routines(.editWeek)`, and a
    /// hosted screen can be asked about neither. Session 1 gave this fixture a box for the days the
    /// closure was handed; review removed it, because **nothing here can make the closure run** —
    /// the command is on the toolbar's `⋯`, which on iOS 26.5 holds one `UIDeferredMenuElement`
    /// until it is opened, declines `accessibilityActivate()` and publishes an open menu's commands
    /// into another window. A capture that can never be filled reads as coverage from the outside.
    /// Which day is handed over is held by review and by `T-18.14`'s run on the simulator; what a
    /// host can see is whether the `⋯` is drawn at all, which is `DayMenuTests`.
    ///
    /// - Returns: The screen.
    func dayView() -> some View {
        DayView(
            runID: runID,
            week: Self.week,
            dayIndex: 0,
            store: store,
            vocabulary: stores.modifiers,
            equipment: stores.equipment,
            programs: repositories.programs,
            routines: repositories.routines,
            exercises: repositories.exercises,
            editPlan: { _ in })
    }

    /// A past session as `RootTabView` builds it.
    ///
    /// - Parameter sessionID: Which session.
    /// - Returns: The screen.
    func pastSessionView(sessionID: UUID) -> some View {
        PastSessionView(
            sessionID: sessionID,
            workouts: CountingWorkoutRepository(wrapped: repositories.workouts, writes: writes),
            catalogue: repositories.exercises,
            settings: repositories.settings,
            vocabulary: stores.modifiers,
            equipment: stores.equipment,
            records: stores.records,
            trainingMaxes: repositories.trainingMaxes)
    }

    /// The workout in progress as `RootTabView` builds it.
    ///
    /// - Returns: The screen.
    func activeSessionView() -> some View {
        ActiveSessionView(store: store, vocabulary: stores.modifiers, equipment: stores.equipment)
    }

    /// Starts a free workout — no program stamp, which is what makes it free (`FR-17.9.7`).
    func startAFreeWorkout() async throws {
        await store.start(on: .now)
        guard store.isActive else { throw FixtureFailure.noWorkout }
        await store.loadExercises()
    }

    /// Writes a finished free workout straight to storage, for the past session to read.
    ///
    /// **Written rather than logged**, because what is under test is a screen over a session that
    /// is over, and driving the live one to that state would be a second walk with its own ways to
    /// fail.
    ///
    /// - Returns: Its identifier.
    /// - Throws: Whatever the repository throws.
    func writeAFinishedFreeWorkout() async throws -> UUID {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionID = UUID()
        try await repositories.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                date: now,
                startedAt: now,
                endedAt: now,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil))
        let entryID = UUID()
        try await repositories.workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: "",
                isMarkedDone: true))
        try await repositories.workouts.save(
            SetEntry(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                entryID: entryID,
                order: 0,
                weight: Weight(grams: 100_000),
                reps: 5,
                rpe: nil,
                rir: nil,
                isWarmup: false,
                isCompleted: true,
                targetWeight: nil,
                targetReps: nil,
                modifiers: [],
                notes: "",
                completedAt: now))
        return sessionID
    }

    /// The catalogue row the day prescribes.
    private let exerciseID = UUID()

    /// The program, its one day, the routine that day names, and the run in force.
    private func writeTheProgram() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try await repositories.exercises.save(
            Exercise(
                id: exerciseID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                name: Self.exerciseName,
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
        let routineID = try await writeTheRoutine(at: now)
        let programID = UUID()
        try await repositories.programs.save(
            Program(
                id: programID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                name: "Course",
                notes: ""))
        try await repositories.programs.save(
            ProgramDay(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                programID: programID,
                routineID: routineID,
                order: 0))
        try await repositories.programs.startRun(
            ProgramRun(
                id: runID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                programID: programID,
                startedAt: now,
                endedAt: nil,
                weekNumber: Self.week,
                nextDayIndex: 0))
    }

    /// One exercise prescribing 100 kg × 5 × 3, which is what gives the row a circle to press.
    ///
    /// - Parameter now: The stamp every row carries.
    /// - Returns: The routine's identifier.
    private func writeTheRoutine(at now: Date) async throws -> UUID {
        let routineID = UUID()
        let slotID = UUID()
        try await repositories.routines.save(
            Routine(
                id: routineID, createdAt: now, updatedAt: now, deletedAt: nil, name: "Squat day"))
        try await repositories.routines.save(
            RoutineExercise(
                id: slotID,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                routineID: routineID,
                exerciseID: exerciseID,
                order: 0))
        try await repositories.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                routineExerciseID: slotID,
                order: 0,
                targetWeight: Weight(grams: 100_000),
                targetReps: 5,
                targetSets: 3))
        return routineID
    }

    /// What can be wrong before a screen is ever hosted.
    enum FixtureFailure: Error {
        /// The in-memory store did not open.
        case storeDidNotOpen

        /// `start(on:)` left no workout in progress.
        case noWorkout
    }
}
