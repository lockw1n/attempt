import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// The two corrections `history.session` offers, over the repositories they write through
/// (`FR-18.7.4`, `FR-18.7.5`, `DOD-18.9`).
///
/// **Over ``PastSessionState`` rather than through ``ActiveSessionStore``, and that is the claim.**
/// The app has one workout store and whichever screen located a session *re-points* it
/// (``SessionLocator``), so a past session's delete issued through it would take down whatever the
/// Train tab is pointed at instead. This screen holds no store at all; ``theTrainTabsWorkoutIsUntouched()``
/// is the test that can see the difference.
@Suite("Correcting a past session")
struct PastSessionCorrectionTests {
    /// A record the cache holds for `exerciseID` at `reps`, or `nil`.
    ///
    /// - Parameters:
    ///   - past: The fixture whose cache to read.
    ///   - exerciseID: The lift.
    ///   - reps: Which cell.
    /// - Returns: The load, or `nil`.
    private func cached(
        _ past: PastSession, _ exerciseID: UUID, reps: Int
    ) async throws -> Weight? {
        try await past.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false
        ).first { $0.repCount == reps }?.weight
    }

    // MARK: - Delete workout (FR-18.7.5)

    @Test("Delete soft-deletes the session and cascades to its entries and sets — G-1.3")
    func deleteIsSoftAndCascades() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let set = try await past.logSet(at: 0, order: 0)
        await past.state.load()

        #expect(await past.state.delete())

        let workouts = past.repositories.workouts
        #expect(try await workouts.session(id: past.sessionID, includingDeleted: false) == nil)
        let stored = try #require(
            try await workouts.session(id: past.sessionID, includingDeleted: true))
        #expect(stored.deletedAt != nil)
        #expect(try await workouts.entry(id: past.entries[0].id, includingDeleted: false) == nil)
        #expect(
            try await workouts.sets(forEntryID: past.entries[0].id, includingDeleted: false)
                .isEmpty)
        // Including the deleted rows, the set is still there — a purge is what removes it, and
        // nothing here is one (`G-1.3`, `TR-1.14`).
        #expect(
            try await workouts.sets(forEntryID: past.entries[0].id, includingDeleted: true)
                .map(\.id) == [set.id])
    }

    @Test("A delete the store turns down keeps every row and reports beside them")
    func aRefusedDeleteKeepsTheSession() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0)
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)
        await state.load()
        await repository.refuseWrites()

        #expect(await state.delete() == false)

        #expect(state.writeFailure != nil)
        #expect(state.exercises.count == 1)
        #expect(
            try await past.repositories.workouts.session(
                id: past.sessionID, includingDeleted: false) != nil)
    }

    @Test("A record only the deleted session's sets held goes with it — G-1.4")
    func deleteTakesTheRecordsItHeld() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 140_000), reps: 3)
        await past.state.load()
        // The cache is written by `FR-1.6.4`'s trigger rather than by the set's own write, and this
        // fixture writes its sets straight into the store — so it is seeded here the way logging
        // the set would have seeded it. Without this the assertion below holds over a cache that
        // was empty all along and cannot fail.
        await past.recomputer.sessionDidChange(id: past.sessionID)
        #expect(try await cached(past, past.exercises[0].id, reps: 3) == Weight(grams: 140_000))

        #expect(await past.state.delete())

        // No settle point is needed and there is none to reach for: `delete()` awaits the
        // announcement rather than detaching it (`NFR-1.2` is the workout in progress' budget, not
        // this screen's).
        #expect(try await cached(past, past.exercises[0].id, reps: 3) == nil)
    }

    @Test("A second session on the same day is untouched")
    func aSiblingSessionSurvives() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let sibling = PastSession.session(id: UUID(), notes: "the other one")
        try await past.repositories.workouts.save(sibling)
        await past.state.load()

        #expect(await past.state.delete())

        #expect(
            try await past.repositories.workouts.session(id: sibling.id, includingDeleted: false)
                != nil)
    }

    @Test("The workout the Train tab is pointed at is untouched — OUT-17.3")
    func theTrainTabsWorkoutIsUntouched() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let free = freeWorkoutSession()
        try await past.repositories.workouts.save(free)
        let store = ActiveSessionStore.over(past.repositories)
        await store.resume()
        #expect(store.session?.id == free.id)
        await past.state.load()

        #expect(await past.state.delete())

        #expect(store.session?.id == free.id)
        #expect(
            try await past.repositories.workouts.session(id: free.id, includingDeleted: false)
                != nil)
    }

    @Test("A deleted planned day is no longer located by its stamp")
    func aDeletedPlannedDayLeavesItsSlotEmpty() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"], stamped: true)
        await past.state.load()
        let session = try #require(past.state.session)
        let locator = SessionLocator.day(
            runID: try #require(session.programRunID),
            week: try #require(session.weekNumber),
            dayIndex: try #require(session.dayIndex))
        #expect(try await locator.session(in: past.repositories.workouts)?.id == past.sessionID)

        #expect(await past.state.delete())

        #expect(try await locator.session(in: past.repositories.workouts) == nil)
    }

    @Test("A day of the current week deleted from History reads not started on Train again")
    func aDeletedDayOfTheCurrentWeekReadsNotStarted() async throws {
        let fixture = try await WeekFixture(days: 3, exercisesPerDay: 2)
        try await fixture.log(day: 1, done: 2)
        let logged = try #require(
            try await fixture.stack.workouts.sessions(
                forProgramRunID: fixture.runID, week: WeekFixture.week, includingDeleted: false
            ).first)
        let state = PastSession.state(sessionID: logged.id, over: fixture.stack)
        await state.load()

        #expect(await state.delete())

        let week = fixture.weekState()
        await week.load(openSession: nil)
        #expect(
            WeekFixture.days(of: week).map(\.progress)
                == [.notStarted, .notStarted, .notStarted])
    }

    // MARK: - Change date (FR-18.7.4)

    @Test("Change date moves the session and keeps every other column, the stamp included")
    func changeDateKeepsTheProgramStamp() async throws {
        let past = try await PastSession.logged(
            names: ["Back Squat"],
            notes: "felt good",
            stamped: true,
            bodyweight: Weight(grams: 82_500))
        await past.state.load()
        let before = try #require(past.state.session)
        let moved = PastSession.stamp - 3 * 86_400

        await past.state.changeDate(to: moved)

        let stored = try #require(
            try await past.repositories.workouts.session(
                id: past.sessionID, includingDeleted: false))
        #expect(stored.date == Calendar.current.startOfDay(for: moved))
        #expect(stored.programRunID == before.programRunID)
        #expect(stored.weekNumber == before.weekNumber)
        #expect(stored.dayIndex == before.dayIndex)
        #expect(stored.notes == "felt good")
        #expect(stored.startedAt == before.startedAt)
        #expect(stored.endedAt == before.endedAt)
        // The column the enumeration above was missing, and the only one of the three it was.
        // **Carried by the fixture rather than left at its default**: nothing in the shipping app
        // writes a session's bodyweight yet, so the `nil` every other fixture here holds would
        // have agreed with a rebuild that dropped it (measured — the drop survived the whole
        // package). `createdAt` and `deletedAt` are the other two, and they are deliberately not
        // asserted: `save(_:)` is an upsert that does not assign either on an existing row —
        // `WorkoutSessionEntity.update(from:)` names neither, and the in-memory store keeps
        // `existing?.createdAt` — so a rebuild cannot drop them and a test pinning them here is
        // one that cannot fail.
        #expect(stored.bodyweight == Weight(grams: 82_500))
        // The screen re-reads, which is what moves the title — the date *is* the title here.
        #expect(past.state.session?.date == stored.date)
    }

    /// `G-2.4`, and the ordinary way out of this sheet: it opens seeded on the session's own day,
    /// so **Done** with nothing moved is one tap. The write it would make assigns every column
    /// whatever it held, which restamps `updatedAt` — so a lifter who opened the picker and
    /// changed their mind would outrank a real edit made on another device.
    ///
    /// **The move has to happen first**, because the fixture's session is dated at an instant
    /// rather than at a start of day: a re-date to its own `date` would normalise it and *be* a
    /// change. What the second call is handed is what the screen holds after the first.
    @Test("A re-date to the day the session already holds writes nothing — G-2.4")
    func changeDateToTheDayItHoldsWritesNothing() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let counter = WorkoutWriteCounter(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: counter)
        await state.load()
        await state.changeDate(to: PastSession.stamp)
        let afterTheMove = await counter.sessionSaves
        let held = try #require(state.session).date

        await state.changeDate(to: held)

        #expect(afterTheMove == 1)
        #expect(await counter.sessionSaves == afterTheMove)
        #expect(state.session?.date == held)
    }

    @Test("Change date is one write, not a save and a restamp")
    func changeDateIsOneWrite() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let counter = WorkoutWriteCounter(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: counter)
        await state.load()

        await state.changeDate(to: PastSession.stamp - 86_400)

        #expect(await counter.sessionSaves == 1)
    }

    @Test("A re-date the store turns down leaves the day where it was")
    func aRefusedChangeDateKeepsTheDay() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)
        await state.load()
        await repository.refuseWrites()

        await state.changeDate(to: PastSession.stamp - 86_400)

        #expect(state.writeFailure != nil)
        #expect(state.session?.date == PastSession.stamp)
    }

    @Test("A re-date moves the record's date and nothing else about it")
    func changeDateMovesTheRecordsDate() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        try await past.logSet(at: 0, order: 0, weight: Weight(grams: 140_000), reps: 3)
        await past.state.load()
        await past.recomputer.sessionDidChange(id: past.sessionID)
        let moved = PastSession.stamp - 3 * 86_400

        await past.state.changeDate(to: moved)

        let record = try #require(
            try await past.repositories.personalRecords.personalRecords(
                forExerciseID: past.exercises[0].id, includingDeleted: false
            ).first { $0.repCount == 3 })
        #expect(record.weight == Weight(grams: 140_000))
        #expect(record.achievedAt == Calendar.current.startOfDay(for: moved))
    }

    // MARK: - The confirmation's count (FR-18.7.5)

    @Test("The question counts every logged set, warm-ups included")
    func theCountIncludesWarmups() async throws {
        let past = try await PastSession.logged(names: ["Back Squat", "Bench Press"])
        try await past.logSet(at: 0, order: 0, isWarmup: true)
        try await past.logSet(at: 0, order: 1)
        try await past.logSet(at: 1, order: 0)
        await past.state.load()

        #expect(past.state.loggedSetCount == 3)
    }

    @Test("A set already taken back is not counted — G-1.3")
    func theCountSkipsDeletedSets() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        let gone = try await past.logSet(at: 0, order: 0)
        try await past.logSet(at: 0, order: 1)
        try await past.repositories.workouts.deleteSet(id: gone.id)
        await past.state.load()

        #expect(past.state.loggedSetCount == 1)
    }

    @Test("A session nothing was logged into counts nothing, and is still deletable")
    func anEmptySessionStillAsks() async throws {
        let past = try await PastSession.logged(names: ["Back Squat"])
        await past.state.load()

        #expect(past.state.loggedSetCount == 0)
        #expect(await past.state.delete())
    }
}
