import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

/// `FR-16.8.1`: the list, and the editor over one program.
@MainActor
@Suite("Programs")
struct ProgramStateTests {
    /// A stack with two routines in it, which is what a program is built from.
    private func stackWithRoutines() async throws -> (InMemoryRepositoryStack, [UUID]) {
        let stack = InMemoryRepositoryStack()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var ids: [UUID] = []
        for name in ["Squat day", "Bench day"] {
            let id = UUID()
            ids.append(id)
            try await stack.routines.save(
                Routine(id: id, createdAt: now, updatedAt: now, deletedAt: nil, name: name))
        }
        return (stack, ids)
    }

    @Test("An empty library reads as ready with no programs")
    func anEmptyLibraryReadsAsReady() async throws {
        let state = ProgramListState(repository: InMemoryRepositoryStack().programs)

        await state.load()

        #expect(state.phase == .ready)
        #expect(state.programs.isEmpty)
    }

    @Test("A program is written under the trimmed name and its identifier is handed back")
    func aProgramIsWritten() async throws {
        let stack = InMemoryRepositoryStack()
        let state = ProgramListState(repository: stack.programs)

        let programID = await state.create(named: "  Course #2  ")

        let id = try #require(programID)
        #expect(state.commandFailure == nil)
        #expect(state.programs.map(\.name) == ["Course #2"])
        #expect(state.programs.map(\.id) == [id])
        #expect(state.programs.map(\.dayCount) == [0])
        #expect(state.programs.map(\.isCurrent) == [false])
    }

    @Test("A blank name writes nothing and says which field to fill in")
    func aBlankNameWritesNothing() async throws {
        let stack = InMemoryRepositoryStack()
        let state = ProgramListState(repository: stack.programs)

        #expect(await state.create(named: "   ") == nil)

        #expect(state.commandFailure == .nameRequired)
        #expect(try await stack.programs.programs(includingDeleted: false).isEmpty)
    }

    @Test("The list marks the one program in force")
    func theListMarksTheCurrentProgram() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let first = try #require(await list.create(named: "A"))
        let second = try #require(await list.create(named: "B"))
        let editor = ProgramEditorState(
            programID: second, repository: stack.programs, routines: stack.routines)
        await editor.load()
        await editor.addDay(routineID: routineIDs[0])
        await editor.makeCurrent()

        await list.load()

        #expect(list.programs.first(where: { $0.id == first })?.isCurrent == false)
        #expect(list.programs.first(where: { $0.id == second })?.isCurrent == true)
        #expect(list.programs.first(where: { $0.id == second })?.dayCount == 1)
    }

    @Test("The editor holds the name and the note as a draft until Save")
    func theEditorHoldsADraft() async throws {
        let (stack, _) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()

        editor.name = "Course #3"
        editor.notes = "deload in week 4"
        #expect(editor.hasUnsavedDetails)
        // A re-read before the save keeps what was typed.
        await editor.load()
        #expect(editor.name == "Course #3")

        await editor.saveDetails()

        #expect(!editor.hasUnsavedDetails)
        let stored = try #require(
            try await stack.programs.program(id: programID, includingDeleted: false))
        #expect(stored.name == "Course #3")
        #expect(stored.notes == "deload in week 4")
    }

    @Test("Days are appended, reordered and removed, and the orders stay dense")
    func daysAreOrdered() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()

        await editor.addDay(routineID: routineIDs[0])
        await editor.addDay(routineID: routineIDs[1])
        await editor.addDay(routineID: routineIDs[0])
        #expect(editor.days.map(\.routineID) == [routineIDs[0], routineIDs[1], routineIDs[0]])

        await editor.moveDay(at: 2, by: -1)
        #expect(editor.days.map(\.routineID) == [routineIDs[0], routineIDs[0], routineIDs[1]])

        await editor.removeDay(id: editor.days[0].id)
        #expect(editor.days.map(\.routineID) == [routineIDs[0], routineIDs[1]])
        let stored = try await stack.programs.days(
            forProgramID: programID, includingDeleted: false)
        #expect(stored.map(\.order) == [0, 1])
    }

    /// A new day's order is one past the last, not the count — a soft-deleted day still holds its
    /// order (`G-1.3`), and reusing it would put two days in one place.
    @Test("A day added after a removal takes an order no deleted day holds")
    func aNewDayDoesNotReuseADeletedOrder() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()
        await editor.addDay(routineID: routineIDs[0])
        await editor.addDay(routineID: routineIDs[1])
        // The *first* day goes: the renumber pulls the survivor down to order 0, and the
        // soft-deleted row keeps order 0 as well. The row count is now 2 and the highest order 0,
        // so "one past the last" and "the count" are different answers — which is what makes this
        // assertion able to fail. Removing the last day instead leaves them equal.
        await editor.removeDay(id: editor.days[0].id)

        await editor.addDay(routineID: routineIDs[1])

        let live = try await stack.programs.days(forProgramID: programID, includingDeleted: false)
        #expect(live.map(\.order) == [0, 1])
        #expect(editor.days.map(\.routineID) == [routineIDs[1], routineIDs[1]])
    }

    /// A write against a row nothing moved restamps `updatedAt`, which is `G-2.4`'s conflict key —
    /// so the renumber has to skip the days already at their position.
    @Test("Reordering leaves the days that did not move unwritten")
    func reorderingSkipsTheDaysThatDidNotMove() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()
        for _ in 0..<3 { await editor.addDay(routineID: routineIDs[0]) }
        let before = try await stack.programs.days(forProgramID: programID, includingDeleted: false)
        let untouched = try #require(before.last)

        // The first two swap; the third keeps the position it had.
        await editor.moveDay(at: 0, by: 1)

        let after = try await stack.programs.days(forProgramID: programID, includingDeleted: false)
        #expect(after.map(\.order) == [0, 1, 2])
        let stayed = try #require(after.first { $0.id == untouched.id })
        #expect(stayed.updatedAt == untouched.updatedAt)
        // And the pair that moved was written, so the assertion above is not vacuous.
        let moved = try #require(after.first { $0.id == before[0].id })
        #expect(moved.updatedAt != before[0].updatedAt)
    }

    /// The name is trimmed on the way in, at the third place one is typed.
    @Test("Saving the details trims the name and stores the note as typed")
    func savingTheDetailsTrimsTheName() async throws {
        let (stack, _) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()

        editor.name = "  Course #3  "
        editor.notes = "  deload in week 4  "
        await editor.saveDetails()

        let stored = try #require(
            try await stack.programs.program(id: programID, includingDeleted: false))
        #expect(stored.name == "Course #3")
        // The note is the lifter's prose and is stored as typed — only the name is trimmed.
        #expect(stored.notes == "  deload in week 4  ")
    }

    /// The day survives its routine (`FR-15.2.5`), and the editor is where that is answered.
    @Test("A day whose routine was archived keeps its row and loses only its name")
    func anArchivedRoutineLeavesTheDay() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()
        await editor.addDay(routineID: routineIDs[0])

        try await stack.routines.deleteRoutine(id: routineIDs[0])
        await editor.load()

        #expect(editor.days.count == 1)
        #expect(editor.days[0].routineID == routineIDs[0])
        #expect(editor.days[0].routineName == nil)
        // And it is no longer offered as a day to add.
        #expect(editor.choices.map(\.id) == [routineIDs[1]])
    }

    /// Making a program current resumes the pass it left rather than restarting it at week 1.
    @Test("Make current reopens the last run through the program")
    func makeCurrentReopensTheLastRun() async throws {
        let (stack, routineIDs) = try await stackWithRoutines()
        let list = ProgramListState(repository: stack.programs)
        let programID = try #require(await list.create(named: "Course #2"))
        let editor = ProgramEditorState(
            programID: programID, repository: stack.programs, routines: stack.routines)
        await editor.load()
        await editor.addDay(routineID: routineIDs[0])
        await editor.makeCurrent()
        let run = try #require(try await stack.programs.currentRun())
        try await stack.programs.save(
            ProgramRun(
                id: run.id,
                createdAt: run.createdAt,
                updatedAt: run.updatedAt,
                deletedAt: nil,
                programID: programID,
                startedAt: run.startedAt,
                endedAt: Date.now,
                weekNumber: 4,
                nextDayIndex: 1))
        await editor.load()
        #expect(!editor.isCurrent)

        await editor.makeCurrent()

        let resumed = try #require(try await stack.programs.currentRun())
        #expect(resumed.id == run.id)
        #expect(resumed.weekNumber == 4)
        #expect(resumed.nextDayIndex == 1)
        #expect(editor.isCurrent)
    }

    @Test("An identifier that resolves to nothing is the missing state, not a failure")
    func aMissingProgramIsItsOwnState() async throws {
        let editor = ProgramEditorState(
            programID: UUID(),
            repository: InMemoryRepositoryStack().programs,
            routines: InMemoryRepositoryStack().routines)

        await editor.load()

        #expect(editor.phase == .missing)
    }
}
