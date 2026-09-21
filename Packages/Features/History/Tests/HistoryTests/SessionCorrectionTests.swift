import Foundation
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import History

/// What History's three readers show after a session is corrected from `history.session`
/// (`FR-18.7.4`, `FR-18.7.5`, `DOD-18.9`).
///
/// **The other half of a claim whose first half is `Logging`'s.** `PastSessionState` makes the two
/// writes — a soft delete, and the record rebuilt on another day with every other column carried
/// across — and `LoggingTests.PastSessionCorrectionTests` is what holds that those are the rows it
/// leaves in the store. What is asserted here is the half no test in that module can reach: that
/// the list, the calendar and the week each *follow* those rows. The two modules cannot import one
/// another (`TR-1.3`), so the seam between the halves is the store, which is where it should be.
///
/// **Nothing in this app invalidates on a write it did not make** — no `@Query`, no remote-change
/// observer — so every screen here is re-read explicitly, exactly as its `.task` does on the way
/// back from a pushed screen. A test that loaded once and asserted would be asserting about a read
/// that happened before the write.
@Suite("A session corrected from History")
struct SessionCorrectionTests {
    /// The day a fixture's session is logged on, and the two either side of it.
    private static let logged = TrainingLog.day(2026, 1, 7)
    private static let moved = TrainingLog.day(2026, 1, 5)

    /// `session` on another training day, every other column carried across — the row
    /// `ActiveSessionStore.dated(_:to:)` leaves in the store.
    ///
    /// - Parameters:
    ///   - session: The workout.
    ///   - day: Where it moves to.
    /// - Returns: The record.
    private func dated(_ session: WorkoutSession, to day: Date) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: day,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: session.notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }

    /// A log holding one session on ``logged``, with one exercise on it.
    ///
    /// - Returns: The fixture and the session.
    private func loggedOnTheWrongDay() async throws -> (log: TrainingLog, session: WorkoutSession) {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: Self.logged)
        try await log.entry(squat, in: session)
        return (log, session)
    }

    @Test("DOD-18.9: a workout logged on the wrong day reads under its new one on all three screens")
    func aReDatedSessionMovesEverywhere() async throws {
        let (log, session) = try await loggedOnTheWrongDay()
        let list = log.listState()
        let calendar = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        let week = log.weekState()
        for screen in [{ await list.load() }, { await calendar.load() }, { await week.load() }] {
            await screen()
        }
        // The screens agree about the wrong day first, so what follows is a move rather than an
        // arrangement that was always this way.
        #expect(list.summaries.map(\.date) == [Self.logged])
        #expect(calendar.trainingDays == [Self.logged])
        #expect(try #require(week.weeks.first).summaries.map(\.date) == [Self.logged])

        try await log.repositories.workouts.save(dated(session, to: Self.moved))

        await list.load()
        await calendar.load()
        await week.load()
        #expect(list.summaries.map(\.date) == [Self.moved])
        #expect(list.summaries.map(\.id) == [session.id])
        #expect(calendar.trainingDays == [Self.moved])
        #expect(try #require(week.weeks.first).summaries.map(\.date) == [Self.moved])
    }

    @Test("DOD-18.9: a deleted workout is gone from the list, the calendar and the week")
    func aDeletedSessionIsGoneEverywhere() async throws {
        let (log, session) = try await loggedOnTheWrongDay()
        // A second session, on another week, so what the readers answer after the delete is a row
        // they still have rather than an empty store — an assertion against an empty screen holds
        // whether the right row went or every row did.
        let kept = try await log.session(on: TrainingLog.day(2025, 12, 30))
        let list = log.listState()
        let calendar = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        let week = log.weekState()
        await list.load()
        await calendar.load()
        await week.load()
        #expect(list.summaries.count == 2)

        try await log.repositories.workouts.deleteSession(id: session.id)

        await list.load()
        await calendar.load()
        await week.load()
        #expect(list.summaries.map(\.id) == [kept.id])
        #expect(calendar.trainingDays == [TrainingLog.day(2025, 12, 30)])
        #expect(week.weeks.flatMap { $0.summaries.map(\.id) } == [kept.id])
    }

    @Test("A screen left un-refreshed still shows the deleted session — the re-read is the guarantee")
    func aScreenThatDoesNotReadAgainIsStale() async throws {
        let (log, session) = try await loggedOnTheWrongDay()
        let list = log.listState()
        await list.load()

        try await log.repositories.workouts.deleteSession(id: session.id)

        // No second `load()`. This is what `TR-1.5`'s "reaches it without revisiting" costs on a
        // screen that hears nothing: the row is still there until something reads again. It is
        // asserted rather than left implicit so that the two tests above are known to be testing
        // the re-read and not a store that notifies.
        #expect(list.summaries.map(\.id) == [session.id])

        await list.load()
        #expect(list.summaries.isEmpty)
    }
}
