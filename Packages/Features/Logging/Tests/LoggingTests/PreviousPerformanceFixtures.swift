import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

// The history `PreviousPerformanceTests` reads back, and the one failure a faithful fake will not
// produce. A file of its own so neither it nor the suite beside it runs into `file_length` — the
// two grow for different reasons, a case being added and a fixture shape being added.

/// One set to be written into a past session: which kind it was, and whether it landed.
///
/// A value rather than the `Bool` this started as, `G-1.8` being two columns and the strip reading
/// both of them.
struct PastSet {
    /// Whether it was a warmup rather than work.
    var isWarmup = false

    /// Whether it was completed. `false` is `FR-1.2.5`'s failed set.
    var isCompleted = true
}

/// Sessions logged before the one in progress — what `FR-1.2.10` reads back.
enum History {
    /// One past workout with one exercise in it.
    ///
    /// - Parameters:
    ///   - day: The training day.
    ///   - exercise: The catalogue row performed.
    ///   - kilos: The load, in whole kilograms.
    ///   - sets: One per set logged. One completed working set by default.
    ///   - repositories: Where it is written.
    static func workout(
        on day: Date,
        exercise: UUID,
        kilos: Int,
        sets: [PastSet] = [PastSet()],
        in repositories: InMemoryRepositoryStack
    ) async throws {
        let session = try await session(on: day, in: repositories)
        try await entry(
            for: exercise, in: session, order: 0, kilos: kilos, sets: sets, in: repositories)
    }

    /// One finished past session, with nothing in it yet.
    ///
    /// Finished, which is what makes it a *past* session: nothing would resume it.
    ///
    /// - Parameters:
    ///   - day: The training day.
    ///   - startedAt: When it was started, where a test needs two sessions inside one day told
    ///     apart. The day itself by default.
    ///   - id: Its identifier, where a test needs the repository's `(date, id)` order pinned rather
    ///     than left to a fresh `UUID`.
    ///   - repositories: Where it is written.
    /// - Returns: The session.
    @discardableResult
    static func session(
        on day: Date,
        startedAt: Date? = nil,
        id: UUID = UUID(),
        in repositories: InMemoryRepositoryStack
    ) async throws -> WorkoutSession {
        let session = WorkoutSession(
            id: id,
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            date: day,
            startedAt: startedAt ?? day,
            endedAt: day.addingTimeInterval(3600),
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        return session
    }

    /// One exercise performed in a past session, with a single set logged against it.
    ///
    /// - Parameters:
    ///   - exercise: The catalogue row performed.
    ///   - session: The workout it was performed in.
    ///   - order: Its place in that workout.
    ///   - kilos: The load, in whole kilograms.
    ///   - sets: One per set logged. An entry carrying no completed working set is a ramp or a
    ///     bad day and no performance, which is two of the cases above.
    ///   - repositories: Where it is written.
    static func entry(
        for exercise: UUID,
        in session: WorkoutSession,
        order: Int,
        kilos: Int,
        sets: [PastSet] = [PastSet()],
        in repositories: InMemoryRepositoryStack
    ) async throws {
        let day = session.date
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise,
            order: order,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        for (position, set) in sets.enumerated() {
            try await repositories.workouts.save(
                SetEntry(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    entryID: entry.id,
                    order: position,
                    weight: Weight(grams: kilos * 1_000),
                    reps: 5,
                    rpe: nil,
                    rir: nil,
                    isWarmup: set.isWarmup,
                    isCompleted: set.isCompleted,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: day
                ))
        }
    }
}

/// A repository that answers everything but the list of sessions, which it refuses.
///
/// The one failure this suite needs and a faithful fake will not produce: the workout in progress
/// still reads, so the cards are on screen when the history behind them is not.
actor UnreadableHistory: WorkoutRepository {
    private let base: any WorkoutRepository
    private let error: RepositoryError

    init(base: any WorkoutRepository, error: RepositoryError) {
        self.base = base
        self.error = error
    }

    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw error
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await base.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws { try await base.save(session) }

    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }

    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await base.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws { try await base.save(entry) }

    func deleteExerciseEntry(id: UUID) async throws { try await base.deleteExerciseEntry(id: id) }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await base.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func save(_ set: SetEntry) async throws { try await base.save(set) }

    func deleteSet(id: UUID) async throws { try await base.deleteSet(id: id) }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await base.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

extension Date {
    /// A fixed training day, so a comparison in these tests is between two constants.
    static func weeksAgo(_ weeks: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 - Double(weeks) * 604_800)
    }
}
