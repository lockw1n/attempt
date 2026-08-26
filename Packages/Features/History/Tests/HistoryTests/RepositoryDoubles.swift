import Foundation
import PowerliftingCore
import RepositoryInterface

@testable import History

/// A workout repository that refuses everything, for the failed-read state.
struct FailingWorkoutRepository: WorkoutRepository {
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

/// A repository that answers normally until it has summarised `limit` sessions, then refuses.
///
/// It counts `entries(forSessionID:)`, which is the first call a summary makes, so the cut falls
/// between two rows rather than halfway through one.
///
/// **An actor, and it has to be one** (`G-6.4`): `WorkoutRepository` refines `Sendable`, so a class
/// with a mutable counter can conform only through `@unchecked Sendable` — an assertion no reader
/// can check — and an isolated conformance is refused outright for a `Sendable` protocol.
actor FlakyWorkoutRepository: WorkoutRepository {
    private let wrapped: any WorkoutRepository
    private let limit: Int
    private var summarised = 0

    init(wrapping wrapped: any WorkoutRepository, failingAfter limit: Int) {
        self.wrapped = wrapped
        self.limit = limit
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        guard summarised < limit else { throw RepositoryError.recordNotFound(id: sessionID) }
        summarised += 1
        return try await wrapped.entries(
            forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

/// A repository that stops one session's entry read until a test lets it go.
///
/// The rendezvous is what makes the concurrency cases deterministic rather than timing-dependent:
/// ``arrival()`` returns once the held read is suspended *inside* the gate, so a test knows exactly
/// where one caller is standing before it starts a second. ``entryReads`` is the other half — the
/// duplicate-work cases assert work not done, because the rows come out right either way.
///
/// **An actor for ``FlakyWorkoutRepository``'s reason** (`G-6.4`), which is also what makes the
/// rendezvous' own state safe to touch from the test while a read is suspended in it.
actor GatedWorkoutRepository: WorkoutRepository {
    /// How many entry reads have been answered.
    private(set) var entryReads = 0

    private let wrapped: any WorkoutRepository
    private let held: Int
    private var hasHeld = false
    private var arrived: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// - Parameters:
    ///   - wrapped: What the reads are answered from.
    ///   - held: Which entry read to suspend, counting from one. **Counted rather than named by
    ///     session**, so that a change to the list's order — a re-sort, a filter, a broken
    ///     de-duplication — fails these tests on their assertions instead of deadlocking the suite
    ///     on a read that never arrives.
    init(wrapping wrapped: any WorkoutRepository, holdingRead held: Int) {
        self.wrapped = wrapped
        self.held = held
    }

    /// Suspends until the held read has reached the gate.
    func arrival() async {
        guard !hasHeld else { return }
        await withCheckedContinuation { arrived = $0 }
    }

    /// Lets the held read continue.
    func release() {
        waiting?.resume()
        waiting = nil
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        entryReads += 1
        if entryReads == held, !hasHeld {
            hasHeld = true
            await withCheckedContinuation { continuation in
                waiting = continuation
                arrived?.resume()
                arrived = nil
            }
        }
        return try await wrapped.entries(
            forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

/// A catalogue holding a soft-deleted row, which no local write can produce.
///
/// `save` drops `deletedAt` on the way in and `ExerciseRepository` has no delete, so the only way a
/// deleted exercise reaches a store is a sync or a restore. This models that store, honouring
/// `includingDeleted:` over the rows it was handed and refusing everything else.
struct ForeignCatalogue: ExerciseRepository {
    let held: [Exercise]

    init(holding held: [Exercise]) {
        self.held = held
    }

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        includingDeleted ? held : held.filter { $0.deletedAt == nil }
    }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        try await exercises(includingDeleted: includingDeleted).first { $0.id == id }
    }

    func save(_ exercise: Exercise) async throws {
        throw RepositoryError.recordNotFound(id: exercise.id)
    }
    func trainingMax(
        forExerciseID exerciseID: UUID, on date: Date
    ) async throws -> TrainingMaxEntry? { nil }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] { [] }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {
        throw RepositoryError.recordNotFound(id: entry.id)
    }
}
