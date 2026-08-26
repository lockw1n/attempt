import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

// A file of its own rather than more of `CalendarStateTests`, for the reason
// `SessionSnapshotFixtures` was split from the suite beside it: the two grow for different reasons
// — a read being added there, a selection shape being added here — and together they run into
// `file_length`.

/// What selecting a day does (`FR-1.5.3`) — the rows it opens, the taps that open nothing, and the
/// two ways an abandoned selection could publish over the one on screen.
///
/// A second suite rather than more of the first: the grid's own reads and the day section's are
/// separate surfaces with separate failures, and one suite holding both had outgrown what a reader
/// can hold in their head.
@MainActor
@Suite("Calendar day selection")
struct CalendarDaySelectionTests {
    @Test("Selecting a marked day shows that day's sessions, newest first")
    func selectingADayShowsItsSessions() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let morning = try await log.session(on: TrainingLog.day(2026, 1, 9, hour: 7))
        let evening = try await log.session(on: TrainingLog.day(2026, 1, 9, hour: 19))
        let squats = try await log.entry(squat, in: morning)
        try await log.set(in: squats, order: 0, kilograms: 60, reps: 5, isWarmup: true)
        try await log.set(in: squats, order: 1, kilograms: 100, reps: 5)
        try await log.entry(bench, in: evening)

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9, hour: 12))

        #expect(state.selectedDay == TrainingLog.day(2026, 1, 9))
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the day's rows, got \(state.day)")
            return
        }
        #expect(rows.map(\.id) == [evening.id, morning.id])
        #expect(rows.first?.exerciseNames == ["Bench Press"])
        // The warmup is in neither number, the same rule the list's rows follow.
        #expect(rows.last?.setCount == 1)
        #expect(rows.last?.tonnage == Weight(grams: 500_000))
    }

    @Test("Selecting a day with nothing on it opens nothing and names no session")
    func selectingAnEmptyDayIsInert() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        try await log.session(on: TrainingLog.day(2026, 1, 9))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))
        await state.select(TrainingLog.day(2026, 1, 10))

        #expect(state.selectedDay == nil)
        #expect(state.day == .none)
    }

    @Test("A day whose last session was deleted elsewhere closes on the next read")
    func aSelectionSurvivesOnlyWhileTheDayDoes() async throws {
        var log = TrainingLog()
        try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9))

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))
        #expect(state.selectedDay == TrainingLog.day(2026, 1, 9))

        try await log.repositories.workouts.deleteSession(id: session.id)
        await state.load()

        #expect(state.trainingDays.isEmpty)
        #expect(state.selectedDay == nil)
        #expect(state.day == .none)
    }

    @Test("A re-read keeps the open day, and takes whatever was logged into it since")
    func aReReadRefreshesTheOpenDay() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9))
        let squats = try await log.entry(squat, in: session)
        try await log.set(in: squats, order: 0, kilograms: 100, reps: 5)

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))

        // A set logged above this screen, then the re-read every return to it performs.
        try await log.set(in: squats, order: 1, kilograms: 100, reps: 5)
        await state.load()

        #expect(state.selectedDay == TrainingLog.day(2026, 1, 9))
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the day's rows, got \(state.day)")
            return
        }
        #expect(rows.first?.setCount == 2)
    }

    @Test("A slower selection does not publish over a newer one")
    func aStaleSelectionRefusesToPublish() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let ninth = try await log.session(on: TrainingLog.day(2026, 1, 9))
        let tenth = try await log.session(on: TrainingLog.day(2026, 1, 10))
        try await log.entry(squat, in: ninth)
        try await log.entry(bench, in: tenth)

        // The gate holds the ninth's entry read — the first one any selection makes — so the two
        // selections are ordered rather than raced.
        let gate = GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: 1)
        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20), workouts: gate)
        await state.load()

        let slow = Task { await state.select(TrainingLog.day(2026, 1, 9)) }
        await gate.arrival()
        await state.select(TrainingLog.day(2026, 1, 10))
        await gate.release()
        await slow.value

        #expect(state.selectedDay == TrainingLog.day(2026, 1, 10))
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the tenth's rows, got \(state.day)")
            return
        }
        #expect(rows.map(\.id) == [tenth.id])
    }

    @Test("A slower selection that fails does not report over a newer one that worked")
    func aStaleSelectionRefusesToReportItsFailure() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        try await log.entry(squat, in: try await log.session(on: TrainingLog.day(2026, 1, 9)))
        let tenth = try await log.session(on: TrainingLog.day(2026, 1, 10))
        try await log.entry(bench, in: tenth)

        let gate = GatedWorkoutRepository(
            wrapping: log.repositories.workouts, holdingRead: 1, failsHeldRead: true)
        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20), workouts: gate)
        await state.load()

        let slow = Task { await state.select(TrainingLog.day(2026, 1, 9)) }
        await gate.arrival()
        await state.select(TrainingLog.day(2026, 1, 10))
        await gate.release()
        await slow.value

        // The abandoned day's refusal is not the open day's error: reporting it would put a failure
        // under a heading whose rows are on screen and correct.
        #expect(state.selectedDay == TrainingLog.day(2026, 1, 10))
        guard case .loaded(let rows) = state.day else {
            Issue.record("expected the tenth's rows, got \(state.day)")
            return
        }
        #expect(rows.map(\.id) == [tenth.id])
    }

    @Test("Adopting another calendar closes an open day rather than showing another one's rows")
    func adoptingACalendarClosesTheSelection() async throws {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let session = try await log.session(on: TrainingLog.day(2026, 1, 9, hour: 12))
        try await log.entry(squat, in: session)

        let state = log.calendarState(today: TrainingLog.day(2026, 1, 20))
        await state.load()
        await state.select(TrainingLog.day(2026, 1, 9))
        #expect(state.selectedDay != nil)

        state.adopt(TrainingLog.oneHourBehind)

        #expect(state.selectedDay == nil)
        #expect(state.day == .none)
    }
}
