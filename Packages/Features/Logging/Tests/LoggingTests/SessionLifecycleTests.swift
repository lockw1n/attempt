import Foundation
import Logging
import RepositoryFakes
import RepositoryInterface
import Testing

/// The lifecycle the store owns: starting a workout, finding one left in progress, finishing it and
/// discarding it (`FR-1.2.1`, `FR-1.2.11`, `FR-1.2.12`, `NFR-1.8`, `G-1.3`).
///
/// The happy paths run against `RepositoryFakes`, whose conformance suite says it behaves like the
/// real store; the failures run against `ScriptedWorkoutRepository`, which a faithful fake will not
/// produce.
@Suite("Session lifecycle")
struct SessionLifecycleTests {
    // MARK: - Starting (FR-1.2.1, NFR-1.8)

    @Test("Starting writes the workout through before it is held")
    func startWritesThrough() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.start(on: .now)

        let held = try #require(store.session)
        // The row is in the store, not just in memory: NFR-1.8's whole claim is that a force-quit
        // before the first set still leaves a workout.
        let stored = try #require(await repository.session(id: held.id, includingDeleted: false))
        #expect(stored == held)
        #expect(stored.endedAt == nil)
        #expect(stored.startedAt != nil)
        #expect(store.failure == nil)
        #expect(store.isActive)
        #expect(store.hasCheckedForSession)
    }

    @Test("A backdated workout is dated to the start of that day, and started now")
    func startNormalisesTheDay() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        let calendar = Calendar.current
        let day = try #require(calendar.date(byAdding: .day, value: -3, to: .now))

        await store.start(on: day)

        let held = try #require(store.session)
        #expect(held.date == calendar.startOfDay(for: day))
        #expect(calendar.isDate(held.date, inSameDayAs: day))
        // The day moved and the moment did not: `startedAt` is when the app began tracking, which
        // is now whichever day the workout counts as.
        let startedAt = try #require(held.startedAt)
        #expect(startedAt > held.date)
        #expect(calendar.isDateInToday(startedAt))
    }

    @Test("A second workout is refused while one is in progress")
    func startRefusesASecondWorkout() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.start(on: .now)
        let first = try #require(store.session)

        await store.start(on: try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now)))

        #expect(store.session?.id == first.id)
        let all = try await repository.sessions(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        #expect(all.count == 1)
    }

    // MARK: - Resuming (FR-1.2.11)

    @Test("A workout started before the app died is resumed by a store that never saw it")
    func unfinishedWorkoutSurvivesARelaunch() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let before = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await before.start(on: .now)
        let started = try #require(before.session)

        // A second store over the same rows is what a relaunch is: nothing carries over but storage.
        let after = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        #expect(!after.hasCheckedForSession)
        await after.resume()

        #expect(after.session == started)
        #expect(after.failure == nil)
        #expect(after.hasCheckedForSession)
    }

    @Test("A finished workout is not resumed")
    func finishedWorkoutIsNotResumed() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let before = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await before.start(on: .now)
        await before.finish()

        let after = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await after.resume()

        #expect(after.session == nil)
        #expect(after.failure == nil)
        // The read ran and answered "none" — which is not the same fact as "nothing has looked".
        #expect(after.hasCheckedForSession)
    }

    @Test("A discarded workout is not resumed")
    func discardedWorkoutIsNotResumed() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let before = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await before.start(on: .now)
        await before.discard()

        let after = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await after.resume()

        #expect(after.session == nil)
        #expect(after.failure == nil)
    }

    @Test("The newest unfinished workout is the one resumed")
    func resumeTakesTheNewestUnfinishedWorkout() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let calendar = Calendar.current
        let older = WorkoutSession.fixture(id: UUID())
            .on(try #require(calendar.date(byAdding: .day, value: -9, to: .now)))
        let newer = WorkoutSession.fixture(id: UUID())
            .on(try #require(calendar.date(byAdding: .day, value: -2, to: .now)))
        try await repository.save(older)
        try await repository.save(newer)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.resume()

        #expect(store.session?.id == newer.id)
    }

    @Test("A workout already held is kept, and nothing is read")
    func resumeKeepsAHeldWorkout() async throws {
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.adopt(sessionID: session.id)
        try #require(store.session == session)

        // Every read from here fails. A resume that read anything would report it.
        await repository.failReads(with: .recordNotFound(id: session.id))
        await store.resume()

        #expect(store.session == session)
        #expect(store.failure == nil)
        #expect(store.hasCheckedForSession)
    }

    // MARK: - Finishing (FR-1.2.11)

    @Test("Finishing stamps the end and releases the workout, keeping the row")
    func finishStampsTheEnd() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.start(on: .now)
        let started = try #require(store.session)

        await store.finish()

        #expect(store.session == nil)
        #expect(!store.isActive)
        #expect(store.failure == nil)
        let stored = try #require(await repository.session(id: started.id, includingDeleted: false))
        #expect(stored.endedAt != nil)
        #expect(stored.deletedAt == nil)
    }

    @Test("Finishing nothing writes nothing")
    func finishWithNoWorkoutDoesNothing() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.finish()

        #expect(store.session == nil)
        #expect(store.failure == nil)
        let all = try await repository.sessions(
            in: Date.distantPast...Date.distantFuture, includingDeleted: true)
        #expect(all.isEmpty)
    }

    // MARK: - Discarding (FR-1.2.12, G-1.3)

    @Test("Discarding soft-deletes the workout rather than removing it")
    func discardIsSoft() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.start(on: .now)
        let started = try #require(store.session)

        await store.discard()

        #expect(store.session == nil)
        #expect(store.failure == nil)
        #expect(try await repository.session(id: started.id, includingDeleted: false) == nil)
        // G-1.3: the row is still there, stamped. Only an explicit purge removes one.
        let row = try #require(await repository.session(id: started.id, includingDeleted: true))
        #expect(row.deletedAt != nil)
    }

    @Test("Discarding nothing writes nothing")
    func discardWithNoWorkoutDoesNothing() async throws {
        let repository = InMemoryRepositoryStack().workouts
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.discard()

        #expect(store.session == nil)
        #expect(store.failure == nil)
    }

    // MARK: - Failures

    @Test("A start that cannot be written is reported and holds nothing")
    func failedStartIsReported() async {
        let failure = RepositoryError.danglingReference(recordID: UUID(), referencing: UUID())
        let repository = ScriptedWorkoutRepository(writeError: failure)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.start(on: .now)

        #expect(store.session == nil)
        #expect(!store.isActive)
        #expect(store.failure == String(describing: failure))
        // The screen has to leave the loading state even though the start failed.
        #expect(store.hasCheckedForSession)
    }

    @Test("A resume that cannot be read is reported, and the screen is told the read is over")
    func failedResumeIsReported() async {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let repository = ScriptedWorkoutRepository(readError: failure)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)

        await store.resume()

        #expect(store.session == nil)
        #expect(store.failure == String(describing: failure))
        #expect(store.hasCheckedForSession)
    }

    @Test("A resume that succeeds after one failed clears the diagnostic")
    func resumeRecovers() async throws {
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session, readError: .recordNotFound(id: UUID()))
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.resume()
        #expect(store.failure != nil)

        await repository.recoverReads()
        await store.resume()

        #expect(store.session == session)
        #expect(store.failure == nil)
    }

    @Test("A finish that cannot be written keeps the workout on screen")
    func failedFinishKeepsTheWorkout() async throws {
        let failure = RepositoryError.danglingReference(recordID: UUID(), referencing: UUID())
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session, writeError: failure)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.adopt(sessionID: session.id)
        try #require(store.session == session)

        await store.finish()

        #expect(store.session == session)
        #expect(store.isActive)
        #expect(store.failure == String(describing: failure))
    }

    @Test("A discard that cannot be written keeps the workout on screen")
    func failedDiscardKeepsTheWorkout() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let session = WorkoutSession.fixture()
        let repository = ScriptedWorkoutRepository(row: session, deleteError: failure)
        let store = ActiveSessionStore(repository: repository, catalogue: InMemoryRepositoryStack().exercises)
        await store.adopt(sessionID: session.id)
        try #require(store.session == session)

        await store.discard()

        #expect(store.session == session)
        #expect(store.failure == String(describing: failure))
    }
}
