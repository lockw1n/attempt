import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("ProgramRepository over SwiftData")
struct ProgramRepositoryTests {
    private static let day = 86_400.0
    private static let base = Date(timeIntervalSince1970: 1_600_000_000)

    // MARK: - Programs and their days

    // `FR-16.8.1`'s ordered list, read back off a real store. Written out of order, so a read that
    // returned the fetch's own order rather than sorting on `order` fails here — and the assertion
    // is anchored to the routine ids rather than to a second read, which would agree just as
    // happily if both came back empty.
    @Test("A program's days come back in order, whatever order they were written in")
    func daysReadBackInOrder() async throws {
        let stack = try RepositoryHarness().stack
        let (program, routines) = try await Self.programWithDays(in: stack, dayCount: 3)

        let days = try await stack.programs.days(forProgramID: program.id, includingDeleted: false)

        #expect(days.map(\.order) == [0, 1, 2])
        #expect(days.map(\.routineID) == routines.map(\.id))
    }

    // `FR-16.8.1`'s several programs, one of which may be current. By name then id, which is
    // `RoutineRepository`'s order and for its reason.
    @Test("Programs list by name")
    func programsListByName() async throws {
        let stack = try RepositoryHarness().stack
        for name in ["Wave 3", "Block 1", "Peak"] {
            try await stack.programs.save(programRecord(name: name))
        }

        #expect(
            try await stack.programs.programs(includingDeleted: false).map(\.name)
                == ["Block 1", "Peak", "Wave 3"])
    }

    // Rule 3's cascade, one level down and one sideways: a deleted program leaves neither a live day
    // nor a live run. The run half is the one with teeth — without it `currentRun()` keeps handing
    // back a pass through a program that is gone.
    @Test("Deleting a program takes its days and its runs")
    func deletingAProgramCascades() async throws {
        let stack = try RepositoryHarness().stack
        let (program, _) = try await Self.programWithDays(in: stack, dayCount: 2)
        let run = programRunRecord(programID: program.id, startedAt: Self.base)
        try await stack.programs.startRun(run)

        try await stack.programs.deleteProgram(id: program.id)

        #expect(try await stack.programs.program(id: program.id, includingDeleted: false) == nil)
        #expect(
            try await stack.programs.days(forProgramID: program.id, includingDeleted: false)
                .isEmpty)
        #expect(try await stack.programs.currentRun() == nil)
        // Still there for a purge to find, which is what a soft delete is (`G-1.3`) — anchored to
        // the count rather than to non-emptiness so a cascade that dropped one row is visible.
        #expect(
            try await stack.programs.days(forProgramID: program.id, includingDeleted: true).count
                == 2)
        #expect(
            try await stack.programs.runs(forProgramID: program.id, includingDeleted: true).count
                == 1)
    }

    @Test("A day naming a program or a routine that does not exist is refused")
    func aDanglingDayIsRefused() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        let routine = routineRecord()
        try await stack.programs.save(program)
        try await stack.routines.save(routine)

        let noProgram = programDayRecord(programID: UUID(), routineID: routine.id)
        await #expect(throws: RepositoryError.self) { try await stack.programs.save(noProgram) }

        let noRoutine = programDayRecord(programID: program.id, routineID: UUID())
        await #expect(throws: RepositoryError.self) { try await stack.programs.save(noRoutine) }

        // The pair that should land, so the two refusals above are not passing over a save that
        // refuses everything.
        try await stack.programs.save(
            programDayRecord(programID: program.id, routineID: routine.id))
        #expect(
            try await stack.programs.days(forProgramID: program.id, includingDeleted: false).count
                == 1)
    }

    // The Scope's own case: `FR-15.2.5`'s archive is a soft delete, nothing sweeps the days naming
    // the routine, and the read has to hand the day back rather than refuse or crash. What is
    // asserted is the day's survival AND that the routine really is gone — a test that only checked
    // the first would pass over a fixture that never archived anything.
    @Test("A routine archived out from under a day leaves the day readable")
    func anArchivedRoutineLeavesItsDayIntact() async throws {
        let stack = try RepositoryHarness().stack
        let (program, routines) = try await Self.programWithDays(in: stack, dayCount: 2)

        try await stack.routines.deleteRoutine(id: routines[0].id)

        #expect(try await stack.routines.routine(id: routines[0].id, includingDeleted: false) == nil)
        let days = try await stack.programs.days(forProgramID: program.id, includingDeleted: false)
        #expect(days.count == 2)
        #expect(days.first?.routineID == routines[0].id)
    }

    // MARK: - Runs

    // The Done-when's own line, and the invariant `FR-16.8.1`'s "one may be current" rests on.
    // Anchored to the second run's id rather than to "there is a run", which a broken
    // implementation satisfies with either of them.
    @Test("Starting a second run ends the first, and does so across programs")
    func startingARunEndsTheOneBeforeIt() async throws {
        let stack = try RepositoryHarness().stack
        let first = programRecord(name: "Block 1")
        let second = programRecord(name: "Block 2")
        try await stack.programs.save(first)
        try await stack.programs.save(second)

        let opening = programRunRecord(programID: first.id, startedAt: Self.base)
        try await stack.programs.startRun(opening)
        #expect(try await stack.programs.currentRun()?.id == opening.id)

        // A second program's run, not the same program's — `FR-16.8.2` draws THE current program's
        // next day, so two open runs across two programs would leave that screen without an answer.
        let next = programRunRecord(
            programID: second.id, startedAt: Self.base + 7 * Self.day, weekNumber: 1, nextDayIndex: 0)
        try await stack.programs.startRun(next)

        #expect(try await stack.programs.currentRun()?.id == next.id)
        let closed = try await stack.programs.runs(forProgramID: first.id, includingDeleted: false)
        #expect(closed.count == 1)
        // Closed AT the new run's start, so the passes abut rather than overlap — a literal, not a
        // comparison against another read.
        #expect(closed.first?.endedAt == Self.base + 7 * Self.day)
    }

    // The other half of the pair: `save(_:)` is how a run advances, and it must NOT close anything.
    // Without this the two writes are indistinguishable and `FR-16.8.4`'s advance would end the run
    // it is advancing.
    @Test("Saving a run advances it and closes nothing")
    func savingARunClosesNothing() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        try await stack.programs.save(program)
        let run = programRunRecord(programID: program.id, startedAt: Self.base)
        try await stack.programs.startRun(run)

        let advanced = programRunRecord(
            id: run.id,
            programID: program.id,
            startedAt: Self.base,
            weekNumber: 3,
            nextDayIndex: 0)
        try await stack.programs.save(advanced)

        let current = try await stack.programs.currentRun()
        #expect(current?.id == run.id)
        #expect(current?.weekNumber == 3)
        #expect(current?.nextDayIndex == 0)
        #expect(current?.endedAt == nil)
    }

    // Rule 2's order with the lookup's key in front of it. Two open runs is not a state `startRun`
    // produces — it is what a restored file or a merge produces — so the rows are written through
    // `save(_:)`, which is the only writer that can make the pair.
    @Test("Two open runs resolve to the later start")
    func twoOpenRunsResolveToTheLaterStart() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        try await stack.programs.save(program)
        let older = programRunRecord(programID: program.id, startedAt: Self.base)
        let newer = programRunRecord(
            programID: program.id, startedAt: Self.base + Self.day, weekNumber: 3, nextDayIndex: 0)
        try await stack.programs.save(older)
        try await stack.programs.save(newer)

        #expect(try await stack.programs.currentRun()?.id == newer.id)
        // And the history lists them the way the lookup resolves them, so the run in force is on
        // top rather than under the pass it outranks.
        #expect(
            try await stack.programs.runs(forProgramID: program.id, includingDeleted: false)
                .map(\.id) == [newer.id, older.id])
    }

    @Test("A closed run is not the current one")
    func aClosedRunIsNotCurrent() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        try await stack.programs.save(program)
        let run = programRunRecord(
            programID: program.id, startedAt: Self.base, endedAt: Self.base + Self.day)
        try await stack.programs.save(run)

        #expect(try await stack.programs.currentRun() == nil)
        // The row is still there — anchored, so the nil above is the `endedAt` and not an empty
        // table.
        #expect(try await stack.programs.run(id: run.id, includingDeleted: false)?.id == run.id)
    }

    @Test("A run naming a program that does not exist is refused, by either writer")
    func aDanglingRunIsRefused() async throws {
        let stack = try RepositoryHarness().stack
        let stray = programRunRecord(programID: UUID())

        await #expect(throws: RepositoryError.self) { try await stack.programs.startRun(stray) }
        await #expect(throws: RepositoryError.self) { try await stack.programs.save(stray) }
        #expect(try await stack.programs.currentRun() == nil)
    }

    // MARK: - What a session records

    // `FR-16.8.3`'s three columns, read back off a real store rather than off the record that went
    // in — the two `Int`s are added after schema v1's declaration was written, so a mapping that
    // dropped either would leave every session claiming to belong to no program.
    //
    // **The week and the day are different numbers**, because a session stamped week 2 day 2 agrees
    // with a mapping that read either column into both.
    @Test("A session started from a program keeps its run, its week and its day")
    func aSessionCarriesItsProgramColumns() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        try await stack.programs.save(program)
        let run = programRunRecord(programID: program.id, startedAt: Self.base)
        try await stack.programs.startRun(run)

        let session = sessionRecord(
            date: Self.base, programRunID: run.id, weekNumber: 2, dayIndex: 1)
        try await stack.workouts.save(session)

        let stored = try await stack.workouts.session(id: session.id, includingDeleted: false)
        #expect(stored?.programRunID == run.id)
        #expect(stored?.weekNumber == 2)
        #expect(stored?.dayIndex == 1)
    }

    // The UPDATE half of the same mapping, which the insert above does not reach. `save` upserts,
    // so a session re-saved — finished, annotated, or written over by `FR-1.11.4`'s file-wins
    // restore — goes through `update(from:)` rather than the initialiser. A mapping that wrote the
    // two columns on the way in and dropped them there would stamp every session it minted and
    // lose both numbers on the first edit.
    //
    // **The second save MOVES both numbers**, because a re-save carrying what is already stored
    // agrees with an update that wrote neither — and it moves them to a pair that is neither the
    // first pair nor a transposition of it.
    @Test("Re-saving a session writes its week and its day through the update path")
    func aResavedSessionKeepsItsProgramColumns() async throws {
        let stack = try RepositoryHarness().stack
        let program = programRecord()
        try await stack.programs.save(program)
        let run = programRunRecord(programID: program.id, startedAt: Self.base)
        try await stack.programs.startRun(run)
        let session = sessionRecord(
            date: Self.base, programRunID: run.id, weekNumber: 2, dayIndex: 1)
        try await stack.workouts.save(session)

        try await stack.workouts.save(
            sessionRecord(
                id: session.id,
                date: Self.base,
                notes: "finished",
                programRunID: run.id,
                weekNumber: 3,
                dayIndex: 0))

        let stored = try await stack.workouts.session(id: session.id, includingDeleted: false)
        #expect(stored?.weekNumber == 3)
        #expect(stored?.dayIndex == 0)
        // The neighbouring column, so the two above are an update rather than a second row.
        #expect(stored?.notes == "finished")
        #expect(stored?.programRunID == run.id)
    }

    // `TR-15.3`'s posture applied to the plan: what a session was is a fact about the day it
    // happened. The program is edited in every way it can be after the session started — renamed, a
    // day reordered, a day removed, the run advanced — and none of it reaches the row.
    //
    // **The edits are asserted to have LANDED**, first, because a test whose edits silently failed
    // would prove nothing about the session at all.
    @Test("Editing a program afterwards never alters a session already started from it")
    func aProgramEditNeverReachesAStartedSession() async throws {
        let stack = try RepositoryHarness().stack
        let (program, routines) = try await Self.programWithDays(in: stack, dayCount: 2)
        let run = programRunRecord(programID: program.id, startedAt: Self.base)
        try await stack.programs.startRun(run)
        let session = sessionRecord(
            date: Self.base, programRunID: run.id, weekNumber: 2, dayIndex: 1)
        try await stack.workouts.save(session)

        // Rename the program.
        try await stack.programs.save(
            Program(
                id: program.id,
                createdAt: program.createdAt,
                updatedAt: program.updatedAt,
                deletedAt: nil,
                name: "Block 2",
                notes: "rewritten"))
        // Reorder its remaining day, and delete the one the session was started from.
        let days = try await stack.programs.days(forProgramID: program.id, includingDeleted: false)
        try await stack.programs.deleteDay(id: days[1].id)
        try await stack.programs.save(
            programDayRecord(
                id: days[0].id, programID: program.id, routineID: routines[0].id, order: 5))
        // Advance the run past the week the session belongs to.
        try await stack.programs.save(
            programRunRecord(
                id: run.id,
                programID: program.id,
                startedAt: Self.base,
                weekNumber: 3,
                nextDayIndex: 0))

        // The edits landed.
        #expect(
            try await stack.programs.program(id: program.id, includingDeleted: false)?.name
                == "Block 2")
        #expect(
            try await stack.programs.days(forProgramID: program.id, includingDeleted: false)
                .map(\.order) == [5])
        #expect(try await stack.programs.currentRun()?.weekNumber == 3)

        // And the session did not move.
        let stored = try await stack.workouts.session(id: session.id, includingDeleted: false)
        #expect(stored?.programRunID == run.id)
        #expect(stored?.weekNumber == 2)
        #expect(stored?.dayIndex == 1)
    }

    // MARK: - Fixture

    /// A program with `dayCount` days, each naming a routine of its own.
    ///
    /// **A routine per day rather than one shared between them**, because days all naming one
    /// routine agree with a read that returned any day's `routineID` for every day.
    ///
    /// - Parameters:
    ///   - stack: The store.
    ///   - dayCount: How many days.
    /// - Returns: The program and its routines, in day order.
    /// - Throws: Whatever a repository throws.
    private static func programWithDays(
        in stack: PersistenceStack,
        dayCount: Int
    ) async throws -> (Program, [Routine]) {
        let program = programRecord()
        try await stack.programs.save(program)

        var routines: [Routine] = []
        for index in 0..<dayCount {
            let routine = routineRecord(name: "Day \(index + 1)")
            try await stack.routines.save(routine)
            routines.append(routine)
        }
        // Written back to front, so a read that returned the fetch's own order is visible.
        for (index, routine) in routines.enumerated().reversed() {
            try await stack.programs.save(
                programDayRecord(programID: program.id, routineID: routine.id, order: index))
        }
        return (program, routines)
    }
}
