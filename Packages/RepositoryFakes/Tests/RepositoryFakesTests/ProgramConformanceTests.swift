import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Programs, their days and the runs through them (`FR-16.8`), against both implementations.
///
/// **A file of its own rather than cases in the five behavioural suites**, which is
/// ``RoutineConformanceTests``' shape and its reason: the three tables' interesting behaviour is
/// cross-row — a cascade, and an invariant over the whole run table — and cross-row behaviour is
/// what is written twice and therefore what drifts.
@Suite("Conformance — programs")
struct ProgramConformanceTests {
    @Test("A program's days round-trip in order, whatever order they were written in", arguments: Subject.all)
    func daysRoundTripInOrder(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let context = try await Self.programWithTwoDays(in: repositories)

        let days = try await repositories.programs.days(
            forProgramID: context.program.id, includingDeleted: false)

        #expect(days.map(\.order) == [0, 1])
        #expect(days.map(\.routineID) == context.routines.map(\.id))
        // Anchored to the note's own text rather than to another read: the notes column is what
        // separates a program from a routine, and nothing else in the row would notice it missing.
        #expect(
            try await repositories.programs.program(
                id: context.program.id, includingDeleted: false)?.notes == "14.09.25")
    }

    @Test("Programs list by name, then by id", arguments: Subject.all)
    func programsListByName(_ subject: Subject) async throws {
        let repositories = try subject.make()
        for name in ["Wave 3", "Block 1", "Peak"] {
            try await repositories.programs.save(programRecord(name: name))
        }

        #expect(
            try await repositories.programs.programs(includingDeleted: false).map(\.name)
                == ["Block 1", "Peak", "Wave 3"])
    }

    @Test("Deleting a program cascades to its days and its runs", arguments: Subject.all)
    func deletingAProgramCascades(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let context = try await Self.programWithTwoDays(in: repositories)
        try await repositories.programs.startRun(
            programRunRecord(programID: context.program.id))

        // A bystander program that must not be touched — a cascade keyed on the wrong column would
        // take it, and every assertion below would still pass without it.
        let bystander = programRecord(name: "Bench block")
        try await repositories.programs.save(bystander)
        let bystanderDay = programDayRecord(
            programID: bystander.id, routineID: context.routines[0].id)
        try await repositories.programs.save(bystanderDay)
        let bystanderRun = programRunRecord(
            programID: bystander.id, startedAt: fixtureCreatedAt - fixtureDay)
        try await repositories.programs.save(bystanderRun)

        try await repositories.programs.deleteProgram(id: context.program.id)

        #expect(
            try await repositories.programs.program(
                id: context.program.id, includingDeleted: false) == nil)
        #expect(
            try await repositories.programs.days(
                forProgramID: context.program.id, includingDeleted: false
            ).isEmpty)
        #expect(
            try await repositories.programs.runs(
                forProgramID: context.program.id, includingDeleted: false
            ).isEmpty)
        // Soft, not hard (`G-1.3`) — and counted, so a cascade that dropped one row is visible.
        #expect(
            try await repositories.programs.days(
                forProgramID: context.program.id, includingDeleted: true
            ).count == 2)
        #expect(
            try await repositories.programs.runs(
                forProgramID: context.program.id, includingDeleted: true
            ).count == 1)

        #expect(
            try await repositories.programs.days(
                forProgramID: bystander.id, includingDeleted: false
            ).map(\.id) == [bystanderDay.id])
        #expect(
            try await repositories.programs.runs(
                forProgramID: bystander.id, includingDeleted: false
            ).map(\.id) == [bystanderRun.id])
    }

    @Test("Deleting a day leaves its routine and its program alone", arguments: Subject.all)
    func deletingADayCascadesNowhere(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let context = try await Self.programWithTwoDays(in: repositories)
        let days = try await repositories.programs.days(
            forProgramID: context.program.id, includingDeleted: false)

        try await repositories.programs.deleteDay(id: days[0].id)

        #expect(
            try await repositories.programs.days(
                forProgramID: context.program.id, includingDeleted: false
            ).map(\.id)
                == [days[1].id])
        #expect(
            try await repositories.routines.routine(
                id: context.routines[0].id, includingDeleted: false)?.id == context.routines[0].id)
        #expect(
            try await repositories.programs.program(
                id: context.program.id, includingDeleted: false)?.id == context.program.id)
    }

    // The Done-when's invariant, and the one piece of cross-row behaviour written twice — so it is
    // exactly the thing this suite exists to hold together.
    @Test("Starting a run ends every other open run, across programs", arguments: Subject.all)
    func startingARunEndsTheOthers(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let first = programRecord(name: "Block 1")
        let second = programRecord(name: "Block 2")
        try await repositories.programs.save(first)
        try await repositories.programs.save(second)

        let opening = programRunRecord(programID: first.id, startedAt: fixtureCreatedAt)
        try await repositories.programs.startRun(opening)
        #expect(try await repositories.programs.currentRun()?.id == opening.id)

        let next = programRunRecord(
            programID: second.id,
            startedAt: fixtureCreatedAt + 7 * fixtureDay,
            weekNumber: 1,
            nextDayIndex: 0)
        try await repositories.programs.startRun(next)

        #expect(try await repositories.programs.currentRun()?.id == next.id)
        let closed = try await repositories.programs.runs(
            forProgramID: first.id, includingDeleted: false)
        #expect(closed.map(\.id) == [opening.id])
        // Closed AT the new run's start, so the passes abut — a literal rather than a second read.
        #expect(closed.first?.endedAt == fixtureCreatedAt + 7 * fixtureDay)
    }

    @Test("Saving a run advances it and closes nothing", arguments: Subject.all)
    func savingARunClosesNothing(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let program = programRecord()
        try await repositories.programs.save(program)
        let run = programRunRecord(programID: program.id)
        try await repositories.programs.startRun(run)

        try await repositories.programs.save(
            programRunRecord(
                id: run.id, programID: program.id, weekNumber: 3, nextDayIndex: 0))

        let current = try await repositories.programs.currentRun()
        #expect(current?.id == run.id)
        #expect(current?.weekNumber == 3)
        #expect(current?.nextDayIndex == 0)
        #expect(current?.endedAt == nil)
    }

    // `save(_:)`'s UPDATE half, which every case above reaches only on the insert: a run already
    // stored is re-saved when the lifter advances it, and when `FR-1.11.4`'s file-wins restore
    // writes over a row this store already holds. A write that carried the run's own columns in on
    // the way in and dropped them on the way back through would keep every run it minted and lose
    // the pass on the first advance.
    //
    // **All four of the run's own values move**, because a re-save carrying what is already stored
    // agrees with an update that wrote none of them.
    @Test("Re-saving a run writes its own four columns, not just its audit ones", arguments: Subject.all)
    func resavingARunWritesItsOwnColumns(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let program = programRecord()
        try await repositories.programs.save(program)
        let run = programRunRecord(programID: program.id)
        try await repositories.programs.startRun(run)

        try await repositories.programs.save(
            programRunRecord(
                id: run.id,
                programID: program.id,
                startedAt: fixtureCreatedAt + fixtureDay,
                endedAt: fixtureCreatedAt + 3 * fixtureDay,
                weekNumber: 5,
                nextDayIndex: 0))

        let stored = try await repositories.programs.run(id: run.id, includingDeleted: false)
        #expect(stored?.startedAt == fixtureCreatedAt + fixtureDay)
        #expect(stored?.endedAt == fixtureCreatedAt + 3 * fixtureDay)
        #expect(stored?.weekNumber == 5)
        #expect(stored?.nextDayIndex == 0)
        // The row was updated rather than duplicated, and the correction closed it.
        #expect(
            try await repositories.programs.runs(
                forProgramID: program.id, includingDeleted: false
            ).map(\.id) == [run.id])
        #expect(try await repositories.programs.currentRun() == nil)
    }

    @Test("A closed run is not the current one, and is still there", arguments: Subject.all)
    func aClosedRunIsNotCurrent(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let program = programRecord()
        try await repositories.programs.save(program)
        let run = programRunRecord(
            programID: program.id,
            startedAt: fixtureCreatedAt,
            endedAt: fixtureCreatedAt + fixtureDay)
        try await repositories.programs.save(run)

        #expect(try await repositories.programs.currentRun() == nil)
        #expect(
            try await repositories.programs.run(id: run.id, includingDeleted: false)?.id == run.id)
    }

    // Rule 2's order with the lookup's key in front of it. Two open runs is what a restored file
    // produces, not what `startRun` produces, so the pair goes in through `save(_:)`.
    @Test("Two open runs resolve to the later start", arguments: Subject.all)
    func twoOpenRunsResolveToTheLaterStart(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let program = programRecord()
        try await repositories.programs.save(program)
        let older = programRunRecord(programID: program.id, startedAt: fixtureCreatedAt)
        let newer = programRunRecord(
            programID: program.id,
            startedAt: fixtureCreatedAt + fixtureDay,
            weekNumber: 3,
            nextDayIndex: 0)
        try await repositories.programs.save(older)
        try await repositories.programs.save(newer)

        #expect(try await repositories.programs.currentRun()?.id == newer.id)
        #expect(
            try await repositories.programs.runs(forProgramID: program.id, includingDeleted: false)
                .map(\.id) == [newer.id, older.id])
    }

    // Rule 1's second paragraph: `currentRun()` takes no flag because it resolves to the row in
    // force, and a deleted run is one whose program the lifter deleted.
    @Test("A soft-deleted run is never the current one", arguments: Subject.all)
    func aDeletedRunIsNeverCurrent(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let program = programRecord()
        try await repositories.programs.save(program)
        let run = programRunRecord(programID: program.id)
        try await repositories.programs.startRun(run)
        #expect(try await repositories.programs.currentRun()?.id == run.id)

        try await repositories.programs.deleteRun(id: run.id)

        #expect(try await repositories.programs.currentRun() == nil)
        #expect(
            try await repositories.programs.runs(forProgramID: program.id, includingDeleted: true)
                .map(\.id) == [run.id])
    }

    @Test("A day or a run naming a row that does not exist is refused", arguments: Subject.all)
    func danglingReferencesAreRefused(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let context = try await Self.programWithTwoDays(in: repositories)

        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.save(
                programDayRecord(programID: UUID(), routineID: context.routines[0].id))
        }
        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.save(
                programDayRecord(programID: context.program.id, routineID: UUID()))
        }
        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.startRun(programRunRecord(programID: UUID()))
        }
        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.save(programRunRecord(programID: UUID()))
        }
        // The refusals above are not a save that refuses everything.
        #expect(
            try await repositories.programs.days(
                forProgramID: context.program.id, includingDeleted: false
            ).count == 2)
    }

    @Test("Deleting a program, a day or a run that is not there is refused", arguments: Subject.all)
    func deletingSomethingAbsentIsRefused(_ subject: Subject) async throws {
        let repositories = try subject.make()

        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.deleteProgram(id: UUID())
        }
        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.deleteDay(id: UUID())
        }
        await #expect(throws: RepositoryError.self) {
            try await repositories.programs.deleteRun(id: UUID())
        }
    }

    // Rule 7: the write path owns `updatedAt`, and honours `createdAt` only on a new row. Written
    // for the three tables at once because they are three conformances of one rule.
    @Test("A save stamps updatedAt and keeps the record's createdAt", arguments: Subject.all)
    func savesStampTheAuditColumns(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let context = try await Self.programWithTwoDays(in: repositories)
        let run = programRunRecord(programID: context.program.id)
        try await repositories.programs.startRun(run)

        let program = try await repositories.programs.program(
            id: context.program.id, includingDeleted: false)
        let day = try await repositories.programs.days(
            forProgramID: context.program.id, includingDeleted: false
        ).first
        let stored = try await repositories.programs.run(id: run.id, includingDeleted: false)

        #expect(program?.createdAt == fixtureCreatedAt)
        #expect(day?.createdAt == fixtureCreatedAt)
        #expect(stored?.createdAt == fixtureCreatedAt)
        // Anchored to the literal the record carried rather than to each other: three optionals
        // compared pairwise are satisfied by three nils.
        #expect(program?.updatedAt != fixtureUpdatedAt)
        #expect(day?.updatedAt != fixtureUpdatedAt)
        #expect(stored?.updatedAt != fixtureUpdatedAt)
        // And `startedAt` is not the audit path's to touch — it is the run's own column, anchored
        // to a literal that is NOT `fixtureCreatedAt`, so a write sourcing it from `createdAt`
        // fails here rather than agreeing.
        #expect(stored?.startedAt == fixtureCreatedAt - 7 * fixtureDay)
    }

    // MARK: - Fixture

    /// One program, two routines and a day naming each — the shape most cases here start from.
    ///
    /// **A routine per day**, because days all naming one routine agree with a read that returned
    /// any day's `routineID` for every day.
    ///
    /// - Parameter repositories: The subject.
    /// - Returns: The program and its routines, in day order.
    /// - Throws: Whatever a repository throws.
    private static func programWithTwoDays(
        in repositories: Repositories
    ) async throws -> ProgramContext {
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let program = programRecord()
        try await repositories.programs.save(program)

        var routines: [Routine] = []
        for index in 0..<2 {
            let routine = routineRecord(name: "Day \(index + 1)")
            try await repositories.routines.save(routine)
            routines.append(routine)
        }
        // Written back to front, so a read that trusted insertion order would still fail.
        for (index, routine) in routines.enumerated().reversed() {
            try await repositories.programs.save(
                programDayRecord(programID: program.id, routineID: routine.id, order: index))
        }
        return ProgramContext(program: program, routines: routines)
    }
}

/// What ``ProgramConformanceTests``' fixture writes — a type rather than a tuple, the lint rule's
/// call.
private struct ProgramContext {
    /// The program.
    let program: Program

    /// The routines its days name, in day order.
    let routines: [Routine]
}
