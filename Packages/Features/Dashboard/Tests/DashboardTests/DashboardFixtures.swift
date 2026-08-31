import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Dashboard

/// A store with a catalogue, a training history and a settings row, built through the front door.
///
/// The shape `DerivedValues`' own `TrainingLog` has, and for its reason: every row goes in through a
/// repository, so a fixture cannot express a state the app could not reach.
struct DashboardFixture {
    /// The fakes everything here is written to and read from.
    let repositories = InMemoryRepositoryStack()

    /// The app's one recompute actor, over those fakes, with "now" pinned.
    var records: PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: repositories.workouts,
            exercises: repositories.exercises,
            cache: repositories.personalRecords,
            now: { fixtureNow })
    }

    /// An exercise in the catalogue.
    @discardableResult
    func exercise(
        id: UUID = UUID(),
        named name: String,
        ukrainian: String? = nil,
        movement: Movement = .squat,
        equipment: Equipment = .barbell,
        parentExerciseID: UUID? = nil,
        isCustom: Bool = false,
        isArchived: Bool = false
    ) async throws -> UUID {
        try await repositories.exercises.save(
            Exercise(
                id: id,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: name,
                ukrainianName: ukrainian,
                movement: movement,
                parentExerciseID: parentExerciseID,
                equipment: equipment,
                laterality: .bilateral,
                barType: .standard,
                implementCount: 1,
                isCustom: isCustom,
                isArchived: isArchived,
                notes: "",
                manualE1RM: nil))
        return id
    }

    /// One session, and one entry per exercise given, with the sets each entry holds.
    ///
    /// - Parameters:
    ///   - date: The training day.
    ///   - entered: When the row was written, if that is not the training day (`FR-1.2.1`
    ///     backdates). Defaults to the training day, which is what a session logged the day it
    ///     happened looks like.
    ///   - isFinished: Whether it has an end — what `FR-1.9.2` reads to choose resume or repeat.
    ///   - exercises: The exercises trained, in order, each with its sets.
    /// - Returns: The session's id.
    @discardableResult
    func session(
        on date: Date,
        enteredOn entered: Date? = nil,
        isFinished: Bool = true,
        exercises: [(UUID, [LoggedSet])]
    ) async throws -> UUID {
        let sessionID = UUID()
        let written = entered ?? date
        try await repositories.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: written,
                updatedAt: written,
                deletedAt: nil,
                date: date,
                startedAt: date,
                endedAt: isFinished ? date.addingTimeInterval(3_600) : nil,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil))
        for (order, trained) in exercises.enumerated() {
            let entryID = UUID()
            try await repositories.workouts.save(
                ExerciseEntry(
                    id: entryID,
                    createdAt: date,
                    updatedAt: date,
                    deletedAt: nil,
                    sessionID: sessionID,
                    exerciseID: trained.0,
                    order: order,
                    notes: "note"))
            for (position, set) in trained.1.enumerated() {
                try await repositories.workouts.save(
                    SetEntry(
                        id: UUID(),
                        createdAt: date,
                        updatedAt: date,
                        deletedAt: nil,
                        entryID: entryID,
                        order: position,
                        weight: Weight(grams: set.grams),
                        reps: set.reps,
                        rpe: nil,
                        rir: nil,
                        isWarmup: set.isWarmup,
                        isCompleted: set.isCompleted,
                        targetWeight: nil,
                        targetReps: nil,
                        modifiers: [],
                        notes: "",
                        completedAt: date))
            }
        }
        return sessionID
    }

    /// Stores which exercises the dashboard tiles.
    func tile(_ exerciseIDs: [UUID]) async throws {
        let stored = try await repositories.settings.settings()
        try await repositories.settings.save(stored.tiling(exerciseIDs))
    }
}

/// One set as a fixture states it — the four columns anything here reads.
struct LoggedSet {
    /// The load, in grams (`G-1.1`).
    let grams: Int

    /// The repetitions performed.
    let reps: Int

    /// Whether it was a warmup rather than working.
    var isWarmup = false

    /// Whether it was completed. `false` is `FR-1.2.5`'s failed set.
    var isCompleted = true
}

/// The day every fixture is dated back from, and what a recomputer here is told "now" is.
nonisolated let fixtureNow = Date(timeIntervalSince1970: 1_700_000_000)

/// A fixed day, `weeks` before ``fixtureNow``.
nonisolated func weeksAgo(_ weeks: Int) -> Date {
    fixtureNow.addingTimeInterval(-Double(weeks) * 7 * 86_400)
}
