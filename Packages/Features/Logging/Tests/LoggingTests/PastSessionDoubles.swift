import Foundation
import PowerliftingCore
import RepositoryInterface

@testable import Logging

// The workout repositories the past-session suites inject, split from `PastSessionFixtures.swift`
// at SwiftLint's file ceiling. Each answers `PlannedTargetRepository` too, because a past day reads
// what was planned for it (`FR-15.3.1`) and a double that could not would be a screen with no plan
// on any row.

/// A workout repository that answers from a real one until it is told to refuse.
///
/// **Two switches rather than a second refusing double**, and the reason is what the refusals are
/// claimed to do. Both ``PastSessionState/phase``'s failed case and ``PastSessionState/writeFailure``
/// are assertions about rows that were *on screen first* — one costs the screen them, the other
/// leaves every one exactly as it was. A double that refuses from the start cannot tell those apart
/// from a screen that never had rows at all, which is true of an empty state either way.
///
/// **An actor** (`G-6.4`): `WorkoutRepository` refines `Sendable`, which leaves a class holding
/// switches the choice between `@unchecked Sendable` and an isolated conformance the compiler
/// refuses for a `Sendable` protocol. The switches are flipped through methods for the same reason.
actor FailableWorkoutRepository: WorkoutRepository, PlannedTargetRepository {
    /// Whether reads are turned down from here on.
    private var refusesReads = false

    /// Whether writes are, and deletions with them.
    private var refusesWrites = false

    /// Whether the session's *entry* read is, on its own.
    ///
    /// The one call ``PastSessionState`` makes on the way to rebuilding its rows and
    /// ``LoggedSetWriter`` never makes at all — so this refuses the re-read behind a correction
    /// while letting the correction itself through, which is the only way to reach the case where
    /// a change is stored and the screen cannot show it.
    private var refusesEntryReads = false

    /// Starts refusing every read.
    func refuseReads() { refusesReads = true }

    /// Starts or stops refusing every write.
    ///
    /// - Parameter refuses: Whether writes are turned down from here on.
    func refuseWrites(_ refuses: Bool = true) { refusesWrites = refuses }

    /// Starts refusing the entry read alone — see ``refusesEntryReads``.
    func refuseEntryReads() { refusesEntryReads = true }

    /// What the reads are answered from while they are allowed.
    private let wrapped: any WorkoutRepository & PlannedTargetRepository

    /// What a refusal raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    /// Builds the double over a real repository.
    ///
    /// - Parameter wrapped: What answers while nothing is refused.
    init(wrapping wrapped: any WorkoutRepository & PlannedTargetRepository) {
        self.wrapped = wrapped
    }

    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        if refusesReads { throw failure }
        return try await wrapped.plannedTargets(
            forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ group: PlannedTargetGroup) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(group)
    }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        if refusesReads { throw failure }
        return try await wrapped.sessions(forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
    }
    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        if refusesReads { throw failure }
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        if refusesReads { throw failure }
        return try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        if refusesReads || refusesEntryReads { throw failure }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        if refusesReads { throw failure }
        return try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        if refusesReads { throw failure }
        return try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(session)
    }
    /// Honours ``refuseReads()`` but **not** `refusesEntryReads`, which is about the entries-of-a-
    /// session read specifically. This one is the recompute's, and it is not what that flag is for.
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        if refusesReads { throw failure }
        return try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(entry)
    }
    func save(_ set: SetEntry) async throws {
        if refusesWrites { throw failure }
        try await wrapped.save(set)
    }
    func deleteSession(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteSession(id: id)
    }
    func deleteExerciseEntry(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func deleteSet(id: UUID) async throws {
        if refusesWrites { throw failure }
        try await wrapped.deleteSet(id: id)
    }
}

/// A workout repository that stops one entry read until a test lets it go, counting them all.
///
/// `SessionListPagingTests`' gate, narrowed to the one read this screen makes per load: the
/// rendezvous is what makes the in-flight guard testable rather than a race — ``arrival()`` returns
/// once the held read is suspended *inside* the gate, so a second `load()` is issued at a moment
/// when the first is provably still out. ``entryReads`` is the assertion, because a refused load
/// and a load whose result is discarded look identical from the outside.
///
/// **An actor for ``FailableWorkoutRepository``'s reason** (`G-6.4`), which is also what makes the
/// rendezvous' own state safe to touch from the test while a read is suspended in it.
actor GatedWorkoutRepository: WorkoutRepository, PlannedTargetRepository {
    /// How many entry reads have been answered.
    private(set) var entryReads = 0

    private let wrapped: any WorkoutRepository & PlannedTargetRepository
    private var hasHeld = false
    private var arrived: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Builds the gate over a real repository. The first entry read is the one held.
    ///
    /// - Parameter wrapped: What the reads are answered from.
    init(wrapping wrapped: any WorkoutRepository & PlannedTargetRepository) {
        self.wrapped = wrapped
    }

    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        try await wrapped.plannedTargets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ group: PlannedTargetGroup) async throws { try await wrapped.save(group) }

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
        if !hasHeld {
            hasHeld = true
            await withCheckedContinuation { continuation in
                waiting = continuation
                arrived?.resume()
                arrived = nil
            }
        }
        return try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
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
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws { try await wrapped.deleteExerciseEntry(id: id) }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

/// A workout repository that refuses everything, for the failed-read and failed-write states.
struct RefusingWorkoutRepository: WorkoutRepository, PlannedTargetRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw failure
    }
    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw failure }
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
    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] { throw failure }
    func save(_ group: PlannedTargetGroup) async throws { throw failure }
}
