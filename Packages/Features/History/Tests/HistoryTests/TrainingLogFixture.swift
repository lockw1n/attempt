import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import History

/// A store with training in it, written through the real fakes rather than handed to the state.
///
/// **Written, not stubbed.** The session list's whole job is to read three levels joined by `UUID`
/// columns and reduce them to four numbers; a fake that returned what a test handed it would agree
/// with any arithmetic at all, including the wrong one.
struct TrainingLog {
    /// The five fakes over one store.
    let repositories: InMemoryRepositoryStack

    /// The exercises the entries name, in the order they were seeded.
    private(set) var catalogue: [Exercise] = []

    /// A store with an empty catalogue and nothing logged.
    init() {
        repositories = InMemoryRepositoryStack()
    }

    /// Adds an exercise to the catalogue.
    ///
    /// - Parameters:
    ///   - name: What it is called — the string a summary line shows.
    ///   - archived: Whether it has been retired (`FR-1.1.5`).
    /// - Returns: The record.
    @discardableResult
    mutating func exercise(named name: String, archived: Bool = false) async throws -> Exercise {
        let exercise = Exercise(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            name: name,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: true,
            isArchived: archived,
            notes: ""
        )
        try await repositories.exercises.save(exercise)
        catalogue.append(exercise)
        return exercise
    }

    /// Writes one session.
    ///
    /// - Parameters:
    ///   - day: How many days before the fixture's epoch it was trained. Larger is older.
    ///   - notes: The session note (`FR-1.2.9`).
    /// - Returns: The record.
    @discardableResult
    func session(daysAgo day: Int, notes: String = "") async throws -> WorkoutSession {
        let date = Self.epoch.addingTimeInterval(-Double(day) * 86_400)
        let session = WorkoutSession(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            date: date,
            startedAt: date,
            endedAt: date.addingTimeInterval(3_600),
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        return session
    }

    /// Adds one exercise to a session.
    ///
    /// - Parameters:
    ///   - exercise: What was performed.
    ///   - session: The session it was performed in.
    ///   - order: Its position within that session.
    /// - Returns: The entry, which is what sets are logged against.
    @discardableResult
    func entry(
        _ exercise: Exercise, in session: WorkoutSession, order: Int = 0
    ) async throws -> ExerciseEntry {
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: session.date,
            updatedAt: session.date,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise.id,
            order: order,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        return entry
    }

    /// Logs one set against an entry.
    ///
    /// - Parameters:
    ///   - entry: What it was performed under.
    ///   - order: Its position within that entry.
    ///   - kilograms: The load on one implement, in whole kilograms.
    ///   - reps: Repetitions performed.
    ///   - isWarmup: Whether it was a warmup (`G-1.8`).
    ///   - isCompleted: Whether it was actually performed (`G-1.8`).
    /// - Returns: The record.
    @discardableResult
    func set(
        in entry: ExerciseEntry,
        order: Int = 0,
        kilograms: Int,
        reps: Int,
        isWarmup: Bool = false,
        isCompleted: Bool = true
    ) async throws -> SetEntry {
        let set = SetEntry(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            entryID: entry.id,
            order: order,
            weight: Weight(grams: kilograms * 1_000),
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

    /// The state under test, over this store.
    ///
    /// - Returns: A fresh state that has read nothing yet.
    func listState() -> SessionListState {
        SessionListState(
            workouts: repositories.workouts,
            exercises: repositories.exercises,
            settings: repositories.settings
        )
    }

    /// The fixture's "now" — a fixed instant, so no assertion here depends on the day it runs.
    static let epoch = Date(timeIntervalSince1970: 1_700_000_000)
}
