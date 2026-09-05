import Foundation
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-16.8.2`: which of the four answers Train's card draws.
@MainActor
@Suite("The program in force, as Train reads it")
struct ProgramNextUpStateTests {
    @Test("With no run open, there is nothing to draw and it is not an empty state")
    func noRunDrawsNothing() async throws {
        let stack = InMemoryRepositoryStack()
        let state = ProgramNextUpState(
            programs: stack.programs, routines: stack.routines, workouts: stack.workouts)

        await state.load()

        #expect(state.phase == .ready)
        #expect(state.nextUp == nil)
    }

    @Test("The card names the program, the week and the day's routine")
    func theCardNamesTheDay() async throws {
        let fixture = try await ProgramFixture()
        let state = fixture.nextUpState()

        await state.load()

        let reading = try #require(state.nextUp)
        #expect(reading.runID == fixture.runID)
        #expect(reading.programName == "Course #2")
        #expect(reading.weekNumber == 2)
        #expect(reading.day == .next(index: 0, routineID: fixture.routineIDs[0], name: "Squat day"))
        #expect(reading.spendsAccent)
    }

    /// `FR-15.2.5`'s archive reaching a program day: the repository returns the row intact and the
    /// caller is where the dangling half is answered.
    @Test("A day whose routine has been archived is its own answer, not a missing day")
    func anArchivedRoutineIsItsOwnAnswer() async throws {
        let fixture = try await ProgramFixture()
        try await fixture.stack.routines.deleteRoutine(id: fixture.routineIDs[0])
        let state = fixture.nextUpState()

        await state.load()

        #expect(state.nextUp?.day == .archivedRoutine(index: 0))
        // It offers no Start, so it does not spend the screen's accent.
        #expect(state.nextUp?.spendsAccent == false)
    }

    @Test("A program with no days says so")
    func aProgramWithNoDaysSaysSo() async throws {
        let fixture = try await ProgramFixture()
        for dayID in fixture.dayIDs {
            try await fixture.stack.programs.deleteDay(id: dayID)
        }
        let state = fixture.nextUpState()

        await state.load()

        #expect(state.nextUp?.day == .noDays)
        #expect(state.nextUp?.spendsAccent == false)
    }

    /// The cursor is a `ProgramDay.order`, not a position: a day removed from the middle leaves a
    /// gap, and the day to train is the first one at or past the cursor.
    @Test("A gap in the orders does not skip the day after it")
    func aGapDoesNotSkipADay() async throws {
        let fixture = try await ProgramFixture()
        try await fixture.stack.programs.deleteDay(id: fixture.dayIDs[0])
        let state = fixture.nextUpState()

        await state.load()

        guard case .next(let index, let routineID, _)? = state.nextUp?.day else {
            Issue.record("expected the second day to be next")
            return
        }
        #expect(index == 1)
        #expect(routineID == fixture.routineIDs[1])
    }

    @Test("A cursor past the last day is a finished week")
    func aCursorPastTheLastDayIsAFinishedWeek() async throws {
        let fixture = try await ProgramFixture()
        let run = try #require(try await fixture.stack.programs.currentRun())
        try await fixture.stack.programs.save(run.movedTo(nextDayIndex: 3))
        let state = fixture.nextUpState()

        await state.load()

        #expect(state.nextUp?.day == .weekComplete)
        #expect(state.nextUp?.spendsAccent == true)
    }

    @Test("A read that failed carries the diagnostic and draws no card")
    func aFailedReadDrawsNoCard() async throws {
        let stack = InMemoryRepositoryStack()
        let state = ProgramNextUpState(
            programs: UnreadablePrograms(),
            routines: stack.routines,
            workouts: stack.workouts)

        await state.load()

        #expect(state.nextUp == nil)
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed read")
            return
        }
        #expect(!diagnostic.isEmpty)
    }
}

/// A program repository whose every read refuses — the only way to reach ``ProgramNextUpState``'s
/// failed phase, the fakes being incapable of failing.
private struct UnreadablePrograms: ProgramRepository {
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func programs(includingDeleted: Bool) async throws -> [Program] { throw failure }
    func program(id: UUID, includingDeleted: Bool) async throws -> Program? { throw failure }
    func save(_ program: Program) async throws { throw failure }
    func deleteProgram(id: UUID) async throws { throw failure }
    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
        throw failure
    }
    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? { throw failure }
    func save(_ day: ProgramDay) async throws { throw failure }
    func deleteDay(id: UUID) async throws { throw failure }
    func currentRun() async throws -> ProgramRun? { throw failure }
    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
        throw failure
    }
    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? { throw failure }
    func startRun(_ run: ProgramRun) async throws { throw failure }
    func save(_ run: ProgramRun) async throws { throw failure }
    func deleteRun(id: UUID) async throws { throw failure }
}
