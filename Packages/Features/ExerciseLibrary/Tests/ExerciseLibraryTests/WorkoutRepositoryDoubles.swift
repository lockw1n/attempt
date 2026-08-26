import Foundation
import PowerliftingCore
import RepositoryInterface

/// The workout stores `ExerciseHistoryStateTests` needs and `RepositoryFakes` deliberately does not
/// have: one that counts, one that refuses on command, and one that can be stopped mid-read.
///
/// **Actors rather than `@unchecked Sendable` classes** (`G-6.4`): each holds mutable state that a
/// `@MainActor` test drives across `await`s, and the isolation is the thing making that safe rather
/// than a comment claiming it is.

/// A `SettingsRepository` that refuses, so the unit fallback is assertable.
actor RefusingSettingsRepository: SettingsRepository {
    func settings() async throws -> UserSettings { throw RepositoryError.recordNotFound(id: UUID()) }
    func save(_ settings: UserSettings) async throws {
        throw RepositoryError.recordNotFound(id: UUID())
    }
}

/// Counts the per-session reads, which is what makes "the walk stops early" an assertion rather than
/// a claim in a doc comment.
actor CountingWorkoutRepository: WorkoutRepository {
    private let wrapped: any WorkoutRepository
    private(set) var sessionsRead = 0

    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] {
        sessionsRead += 1
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
}

/// A store whose per-session read can be switched off, so an extension can be made to fail without
/// the first page failing too.
actor FlakyWorkoutRepository: WorkoutRepository {
    private let wrapped: any WorkoutRepository
    private var refusingEntries = false
    private var refusingSets = false

    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    func refuseEntries(_ refusing: Bool) {
        refusingEntries = refusing
    }

    func refuseSets(_ refusing: Bool) {
        refusingSets = refusing
    }

    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] {
        if refusingEntries { throw RepositoryError.recordNotFound(id: sessionID) }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        if refusingSets { throw RepositoryError.recordNotFound(id: exerciseID) }
        return try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
}

/// A store whose per-session read can be stopped mid-flight, so an extension can be overtaken by a
/// fresh read deterministically rather than by racing two tasks and hoping.
actor GatedWorkoutRepository: WorkoutRepository {
    private let wrapped: any WorkoutRepository
    private var gateNext = false
    private var held: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?
    private var hasArrived = false

    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// Stops the next per-session read, and only that one.
    func gateNextEntriesRead() {
        gateNext = true
        hasArrived = false
    }

    /// Suspends until that read has arrived and is being held.
    ///
    /// The flag is checked first: a read that arrived before this call would otherwise leave nothing
    /// to resume the waiter, and the test would hang rather than fail.
    func waitForArrival() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets it go.
    func release() {
        held?.resume()
        held = nil
    }

    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] {
        if gateNext {
            gateNext = false
            await withCheckedContinuation { continuation in
                held = continuation
                hasArrived = true
                arrival?.resume()
                arrival = nil
            }
        }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
}
