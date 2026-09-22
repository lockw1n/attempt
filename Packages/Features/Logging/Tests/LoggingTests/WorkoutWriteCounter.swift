import Foundation
import PowerliftingCore
import RepositoryInterface

@testable import Logging

/// A workout repository that forwards everything and counts what a command cost.
///
/// **A count is the only instrument there is for "one write, not two"** (`FR-18.7.1`,
/// `T-18.14`). The obvious cheaper one — reading `updatedAt` back and asking whether the create
/// restamped it — cannot work here: every fake and the real store alike stamp `updatedAt` from
/// the clock on *every* save, the first one included, so a row created and a row created then
/// moved are indistinguishable by their own columns. What separates them is how many times the
/// repository was asked.
///
/// **Session saves and entry reads, and no other call**, because those are the two halves of the
/// claim: `DayStore.changeDate(to:)` on an untouched day is one write and one reload, and
/// ``DayStore/reload()`` is `ActiveSessionStore.loadExercises()`, whose one read per call is the
/// session's entries.
///
/// **An actor** for ``FailableWorkoutRepository``'s reason (`G-6.4`): `WorkoutRepository` refines
/// `Sendable`, so a class holding counters would have to be `@unchecked`.
actor WorkoutWriteCounter: WorkoutRepository, PlannedTargetRepository {
    /// How many times a ``RepositoryInterface/WorkoutSession`` has been stored.
    private(set) var sessionSaves = 0

    /// How many times a session's entries have been read — one per reload.
    private(set) var entryReads = 0

    /// What every call is forwarded to.
    private let wrapped: any WorkoutRepository & PlannedTargetRepository

    /// Builds the counter over a real repository.
    ///
    /// - Parameter wrapped: What answers every call.
    init(wrapping wrapped: any WorkoutRepository & PlannedTargetRepository) {
        self.wrapped = wrapped
    }

    func save(_ session: WorkoutSession) async throws {
        sessionSaves += 1
        try await wrapped.save(session)
    }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        entryReads += 1
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(
            forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
    }
    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        try await wrapped.plannedTargets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ group: PlannedTargetGroup) async throws { try await wrapped.save(group) }
}
