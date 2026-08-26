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
        let exercise = Self.exercise(named: name, archived: archived)
        try await repositories.exercises.save(exercise)
        catalogue.append(exercise)
        return exercise
    }

    /// One exercise as a value, written to nothing.
    ///
    /// A repository's `save` is keyed on the identifier, so two rows sharing one is a shape no store
    /// here will hold — and `G-2.5` is what says a real one may. This is how a test builds the pair.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - name: What it is called.
    ///   - archived: Whether it has been retired (`FR-1.1.5`).
    ///   - deleted: Whether it has been soft-deleted (`G-1.3`). Honoured only by a double that
    ///     models a foreign store: a repository's `save` drops `deletedAt` on the way in, and
    ///     `ExerciseRepository` has no delete, so no local write produces this.
    /// - Returns: The value.
    static func exercise(
        id: UUID = UUID(), named name: String, archived: Bool = false, deleted: Bool = false
    ) -> Exercise {
        Exercise(
            id: id,
            createdAt: epoch,
            updatedAt: epoch,
            deletedAt: deleted ? epoch : nil,
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
    }

    /// Writes one session.
    ///
    /// - Parameters:
    ///   - day: How many days before the fixture's epoch it was trained. Larger is older.
    ///   - notes: The session note (`FR-1.2.9`).
    ///   - isFinished: Whether it was ever ended. `false` leaves `endedAt` null — a workout still
    ///     being logged, which the list carries like any other.
    /// - Returns: The record.
    @discardableResult
    func session(
        daysAgo day: Int, notes: String = "", isFinished: Bool = true
    ) async throws -> WorkoutSession {
        let session = Self.session(daysAgo: day, notes: notes, isFinished: isFinished)
        try await repositories.workouts.save(session)
        return session
    }

    /// One session as a value, written to nothing — ``exercise(id:named:archived:deleted:)``'s
    /// reason, one level up.
    ///
    /// - Parameters:
    ///   - id: Its identifier.
    ///   - day: How many days before the fixture's epoch it was trained. Larger is older.
    ///   - notes: The session note (`FR-1.2.9`).
    ///   - isFinished: Whether it was ever ended.
    /// - Returns: The value.
    static func session(
        id: UUID = UUID(), daysAgo day: Int, notes: String = "", isFinished: Bool = true
    ) -> WorkoutSession {
        let date = epoch.addingTimeInterval(-Double(day) * 86_400)
        return WorkoutSession(
            id: id,
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            date: date,
            startedAt: date,
            endedAt: isFinished ? date.addingTimeInterval(3_600) : nil,
            notes: notes,
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
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
