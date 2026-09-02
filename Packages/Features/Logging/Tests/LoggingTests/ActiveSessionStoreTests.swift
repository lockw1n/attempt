import Foundation
import Logging
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

/// The store's *shape*: what it adopts, what it writes, and the two writes it refuses. The session's
/// content is not here because it is not in the store yet.
@Suite("Active session store")
struct ActiveSessionStoreTests {
    @Test("Adopting a live session holds it")
    func adoptHoldsLiveSession() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let session = WorkoutSession.fixture()
        try await repository.save(session)
        let store = ActiveSessionStore.overWorkouts(repository)

        await store.adopt(sessionID: session.id)

        #expect(store.session?.id == session.id)
        #expect(store.failure == nil)
    }

    @Test("Adopting an unknown session holds nothing, and is not a failure")
    func adoptUnknownSessionIsNotAFailure() async {
        let store = ActiveSessionStore.overWorkouts(InMemoryRepositoryStack().workouts)

        await store.adopt(sessionID: UUID())

        #expect(store.session == nil)
        #expect(store.failure == nil)
    }

    @Test("Adopting a soft-deleted session holds nothing")
    func adoptDeletedSessionHoldsNothing() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let session = WorkoutSession.fixture()
        try await repository.save(session)
        try await repository.deleteSession(id: session.id)
        let store = ActiveSessionStore.overWorkouts(repository)

        await store.adopt(sessionID: session.id)

        #expect(store.session == nil)
        #expect(store.failure == nil)
    }

    @Test("An update writes through and republishes what the store kept")
    func updateWritesThrough() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let session = WorkoutSession.fixture()
        try await repository.save(session)
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: session.id)
        let adopted = try #require(store.session)

        await store.update(adopted.withNotes("touched"))

        let stored = try #require(await repository.session(id: session.id, includingDeleted: false))
        #expect(stored.notes == "touched")
        #expect(store.session == stored)
        // The published record is the store's, not the caller's: the save path stamps `updatedAt`.
        #expect(stored.updatedAt > adopted.updatedAt)
    }

    @Test("An update equal to the held session writes nothing")
    func unchangedUpdateIsNotWritten() async throws {
        let repository = InMemoryRepositoryStack().workouts
        try await repository.save(WorkoutSession.fixture())
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: WorkoutSession.fixture().id)
        let adopted = try #require(store.session)

        await store.update(adopted)

        // `updatedAt` and not a call count: the rule is about G-2.4's conflict key being restamped
        // by a write that moved nothing.
        let stored = try #require(await repository.session(id: adopted.id, includingDeleted: false))
        #expect(stored.updatedAt == adopted.updatedAt)
    }

    @Test("An update naming a different session writes nothing and changes nothing held")
    func foreignUpdateIsRefused() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let session = WorkoutSession.fixture()
        try await repository.save(session)
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: session.id)
        let foreign = WorkoutSession.fixture(id: UUID()).withNotes("elsewhere")

        await store.update(foreign)

        #expect(store.session?.id == session.id)
        #expect(store.session?.notes == session.notes)
        let written = try await repository.session(id: foreign.id, includingDeleted: false)
        #expect(written == nil)
    }

    @Test("A failed read is reported, and drops what was held")
    func failedReadIsReported() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session)
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: session.id)
        // Something has to be held for the drop to be the thing under test.
        try #require(store.session == session)

        await repository.failReads(with: failure)
        await store.adopt(sessionID: session.id)

        #expect(store.session == nil)
        #expect(store.failure == String(describing: failure))
    }

    @Test("A read that succeeds after one failed clears the diagnostic")
    func successfulReadClearsTheFailure() async {
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(
            row: session, readError: .recordNotFound(id: UUID()))
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: session.id)
        #expect(store.failure != nil)

        await repository.recoverReads()
        await store.adopt(sessionID: session.id)

        #expect(store.session == session)
        #expect(store.failure == nil)
    }

    @Test("A row that is gone after its own write is reported rather than silently emptying the store")
    func vanishedRowAfterWriteIsReported() async throws {
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session)
        let store = ActiveSessionStore.overWorkouts(repository)
        await store.adopt(sessionID: session.id)
        try #require(store.session == session)

        // The row is discarded elsewhere between the save and the re-read.
        await repository.forgetRow()
        await store.update(session.withNotes("touched"))

        #expect(store.failure == String(describing: RepositoryError.recordNotFound(id: session.id)))
        // Held rather than emptied: a screen mid-set has to keep rendering something, and it is
        // `adopt` that changes which session that is.
        #expect(store.session == session)
    }

    @Test("A failed write is reported, and leaves the held session alone")
    func failedWriteIsReported() async throws {
        let failure = RepositoryError.danglingReference(recordID: UUID(), referencing: UUID())
        let session = WorkoutSession.fixture()
        let store = ActiveSessionStore.overWorkouts(
            ScriptedWorkoutRepository(row: session, writeError: failure))
        await store.adopt(sessionID: session.id)

        await store.update(session.withNotes("touched"))

        #expect(store.failure == String(describing: failure))
        #expect(store.session == session)
    }
}

/// A `WorkoutRepository` that answers the four calls the store makes and refuses the rest.
///
/// The happy paths above run against `RepositoryFakes`, whose conformance suite says it behaves like
/// the real store. This one exists for the failures a faithful fake will not produce.
actor ScriptedWorkoutRepository: WorkoutRepository, PlannedTargetRepository {
    // TR-15.3's two members: no test here starts from a routine, so the plan is empty and a save
    // is refused the way this double refuses anything it was not written to answer.
    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] {
        []
    }
    func save(_ group: PlannedTargetGroup) async throws {
        throw RepositoryError.recordNotFound(id: group.id)
    }

    private var row: WorkoutSession?
    private var readError: RepositoryError?
    private let writeError: RepositoryError?
    private let deleteError: RepositoryError?

    init(
        row: WorkoutSession? = nil,
        readError: RepositoryError? = nil,
        writeError: RepositoryError? = nil,
        deleteError: RepositoryError? = nil
    ) {
        self.row = row
        self.readError = readError
        self.writeError = writeError
        self.deleteError = deleteError
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        if let readError { throw readError }
        return row?.id == id ? row : nil
    }

    /// Starts failing every read, so a test can fail one *after* the store has something to lose.
    func failReads(with error: RepositoryError) { readError = error }

    /// Stops failing reads, so the next one behaves.
    func recoverReads() { readError = nil }

    /// Drops the row without failing anything — a record discarded elsewhere, which a read then
    /// answers for with `nil` rather than with an error.
    func forgetRow() { row = nil }

    func save(_ session: WorkoutSession) async throws {
        if let writeError { throw writeError }
    }

    /// The one row, when it is dated inside `range` — the read `resume()` makes.
    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] {
        if let readError { throw readError }
        return [row].compactMap { $0 }.filter { range.contains($0.date) }
    }

    /// Soft-deletes the row by forgetting it, or fails when the test asked for a failed discard.
    func deleteSession(id: UUID) async throws {
        if let deleteError { throw deleteError }
        guard row?.id == id else { throw RepositoryError.recordNotFound(id: id) }
        row = nil
    }

    /// Refused, always — which is what makes this the fake a failed *exercise* read is written
    /// against. The store does call this one; see `SessionExercisesTests`.
    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] {
        throw unsupported
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw unsupported }

    func save(_ entry: ExerciseEntry) async throws { throw unsupported }

    func deleteExerciseEntry(id: UUID) async throws { throw unsupported }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] { throw unsupported }

    func save(_ set: SetEntry) async throws { throw unsupported }

    func deleteSet(id: UUID) async throws { throw unsupported }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw unsupported
    }

    /// Every call the store does not make. A stub that returned an empty answer instead would let a
    /// store that called one of these look like it worked.
    private var unsupported: RepositoryError { .recordNotFound(id: UUID()) }
}

extension WorkoutSession {
    /// A session with every field fixed, so a test asserts on what it set.
    static func fixture(
        id: UUID = UUID(uuidString: "33333333-3333-4333-8333-333333333333") ?? UUID()
    ) -> WorkoutSession {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return WorkoutSession(
            id: id,
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
    }

    /// The same session on another training day — the field the resume order keys off.
    func on(_ day: Date) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: day,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            bodyweight: bodyweight,
            programRunID: programRunID,
            scheduledWorkoutID: scheduledWorkoutID
        )
    }

    /// The same session with different notes — the one field these tests move.
    func withNotes(_ notes: String) -> WorkoutSession {
        WorkoutSession(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            date: date,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            bodyweight: bodyweight,
            programRunID: programRunID,
            scheduledWorkoutID: scheduledWorkoutID
        )
    }
}
