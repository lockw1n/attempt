import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

/// A session that is over, written straight into a store — what every past-session test starts from.
///
/// **Written rather than logged through ``ActiveSessionStore``**, and that is the point of it: this
/// screen's whole claim is that it needs no workout in progress, so a fixture that started one would
/// prove the opposite of what the tests are for.
struct PastSession {
    let repositories: InMemoryRepositoryStack
    let state: PastSessionState
    let sessionID: UUID
    let entries: [ExerciseEntry]
    let exercises: [Exercise]

    /// A fixed point in time, so nothing here depends on when the suite runs.
    static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// Seeds a finished session with `names.count` exercises and returns the state over it.
    ///
    /// - Parameters:
    ///   - names: The exercises performed, in entry order.
    ///   - notes: The session's own note (`FR-1.2.9`).
    /// - Returns: The fixture.
    static func logged(
        names: [String] = ["Back Squat", "Bench Press", "Deadlift"], notes: String = ""
    ) async throws -> PastSession {
        let repositories = InMemoryRepositoryStack()
        let sessionID = UUID()
        try await repositories.workouts.save(session(id: sessionID, notes: notes))
        var exercises: [Exercise] = []
        var entries: [ExerciseEntry] = []
        for (order, name) in names.enumerated() {
            let exercise = Exercise.row(named: name)
            try await repositories.exercises.save(exercise)
            let entry = ExerciseEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exercise.id,
                order: order,
                notes: ""
            )
            try await repositories.workouts.save(entry)
            exercises.append(exercise)
            entries.append(entry)
        }
        return PastSession(
            repositories: repositories,
            state: state(sessionID: sessionID, over: repositories),
            sessionID: sessionID,
            entries: entries,
            exercises: exercises
        )
    }

    /// A state over `repositories`, for a fixture that needs one built by hand.
    ///
    /// - Parameters:
    ///   - sessionID: The session it is about.
    ///   - repositories: What it reads.
    ///   - workouts: The workout repository to use, where it is not the stack's own — a double, say.
    /// - Returns: The state.
    static func state(
        sessionID: UUID,
        over repositories: InMemoryRepositoryStack,
        workouts: (any WorkoutRepository)? = nil
    ) -> PastSessionState {
        PastSessionState(
            sessionID: sessionID,
            workouts: workouts ?? repositories.workouts,
            catalogue: repositories.exercises,
            settings: repositories.settings
        )
    }

    /// A finished session on a fixed day.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - notes: Its note.
    /// - Returns: The record.
    static func session(id: UUID, notes: String) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: stamp.addingTimeInterval(3600),
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
    }

    /// Writes one set against the entry at `position`.
    ///
    /// - Parameters:
    ///   - position: Which exercise it belongs to.
    ///   - order: Its place among that exercise's sets.
    ///   - weight: The load.
    ///   - reps: The repetitions.
    ///   - isWarmup: Whether it is a warmup.
    ///   - isCompleted: Whether it was completed rather than failed.
    /// - Returns: The stored set.
    @discardableResult
    func logSet(
        at position: Int,
        order: Int,
        weight: Weight = Weight(grams: 100_000),
        reps: Int = 5,
        isWarmup: Bool = false,
        isCompleted: Bool = true
    ) async throws -> SetEntry {
        let set = SetEntry(
            id: UUID(),
            createdAt: Self.stamp,
            updatedAt: Self.stamp,
            deletedAt: nil,
            entryID: entries[position].id,
            order: order,
            weight: weight,
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
        try await repositories.workouts.save(set)
        return set
    }

    /// The sets stored against the entry at `position`, deleted ones included.
    ///
    /// - Parameter position: Which exercise to read.
    /// - Returns: Every row, whether or not it is soft-deleted.
    func storedSets(at position: Int) async throws -> [SetEntry] {
        try await repositories.workouts.sets(
            forEntryID: entries[position].id, includingDeleted: true)
    }
}

extension Exercise {
    /// A catalogue row with every field fixed but its name.
    ///
    /// - Parameter name: What it is called.
    /// - Returns: The row.
    static func row(named name: String) -> Exercise {
        // The same instant ``PastSession/stamp`` names, written again: this extension is nonisolated
        // and that property is not, the module compiling under `defaultIsolation(MainActor.self)`.
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return Exercise(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
    }
}

/// A workout repository that refuses everything, for the failed-read and failed-write states.
struct RefusingWorkoutRepository: WorkoutRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
    func save(_ entry: ExerciseEntry) async throws { throw failure }
    func deleteExerciseEntry(id: UUID) async throws { throw failure }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
    func save(_ set: SetEntry) async throws { throw failure }
    func deleteSet(id: UUID) async throws { throw failure }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
}
