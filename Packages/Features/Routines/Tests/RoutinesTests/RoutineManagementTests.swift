import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

@MainActor
@Suite("Routine management")
struct RoutineManagementTests {
    // MARK: - Duplicating (FR-15.2.5)

    @Test("A copy carries the content and none of the identifiers")
    func duplicateCopiesContent() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.duplicate(library.routineID)

        #expect(list.routines.count == 2)
        let copy = try #require(list.routines.first { $0.id != library.routineID })
        #expect(copy.name == "Push (copy)")
        #expect(copy.exerciseCount == 2)

        let original = try await library.slots(of: library.routineID)
        let copied = try await library.slots(of: copy.id)
        #expect(copied.map(\.exerciseID) == original.map(\.exerciseID))
        #expect(copied.map(\.order) == [0, 1])
        #expect(Set(copied.map(\.id)).isDisjoint(with: Set(original.map(\.id))))
    }

    @Test("A blank target stays blank in the copy, and a filled one keeps its load")
    func duplicateKeepsBlankTargets() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.duplicate(library.routineID)

        let copy = try #require(list.routines.first { $0.id != library.routineID })
        let slots = try await library.slots(of: copy.id)
        let first = try await library.groups(of: slots[0])
        let second = try await library.groups(of: slots[1])
        // The distinction FR-15.2.2 exists for, carried across: a load of nothing is not no load.
        #expect(first.map(\.targetWeight) == [Weight(grams: 100_000)])
        #expect(second.map(\.targetWeight) == [nil])
        #expect(second.map(\.targetReps) == [8])
        #expect(second.map(\.targetSets) == [2])
    }

    @Test("Editing the copy leaves the original alone")
    func copyIsIndependent() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()
        await list.duplicate(library.routineID)
        let copy = try #require(list.routines.first { $0.id != library.routineID })

        let editor = editor(over: library.stack)
        await editor.open(.edit(routineID: copy.id), screen: UUID())
        editor.removeSlot(at: 1)
        await editor.save()

        let original = try await library.slots(of: library.routineID)
        let copied = try await library.slots(of: copy.id)
        #expect(original.count == 2)
        #expect(copied.count == 1)
    }

    @Test("A routine that is already gone is not a failure — the read sweeps it off")
    func duplicateOfAMissingRoutine() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()
        try await library.stack.routines.deleteRoutine(id: library.routineID)

        await list.duplicate(library.routineID)

        #expect(list.managementFailure == nil)
        #expect(list.routines.isEmpty)
    }

    @Test("A refused write is reported and nothing is listed twice")
    func duplicateThatCannotBeWritten() async throws {
        let library = try await Library.authored()
        let store = FlakyRoutineRepository(library.stack.routines, refusingRoutineSaves: true)
        let list = RoutineListState(repository: store)
        await list.load()

        await list.duplicate(library.routineID)

        #expect(list.managementFailure == .writeFailed)
        #expect(list.routines.count == 1)
    }

    // MARK: - Renaming (FR-15.2.5)

    @Test("A rename retitles the routine and moves nothing under it")
    func renameKeepsTheContent() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.rename(library.routineID, to: "Upper body")

        #expect(list.routines.map(\.name) == ["Upper body"])
        #expect(list.routines.map(\.id) == [library.routineID])
        #expect(try await library.slots(of: library.routineID).count == 2)
        let stored = try #require(
            try await library.stack.routines.routine(
                id: library.routineID, includingDeleted: false))
        #expect(stored.createdAt == library.createdAt)
    }

    @Test("A rename is trimmed, exactly as the editor trims what it saves")
    func renameIsTrimmed() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.rename(library.routineID, to: "  Upper body \n")

        #expect(list.routines.map(\.name) == ["Upper body"])
    }

    @Test("A name of nothing but spaces is refused, and the stored name is untouched")
    func renameRefusesAnEmptyName() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.rename(library.routineID, to: "   ")

        #expect(list.managementFailure == .nameRequired)
        #expect(list.routines.map(\.name) == ["Push"])
    }

    @Test("A refused rename says so, and says the other thing than an empty name does")
    func renameThatCannotBeWritten() async throws {
        let library = try await Library.authored()
        let store = FlakyRoutineRepository(library.stack.routines, refusingRoutineSaves: true)
        let list = RoutineListState(repository: store)
        await list.load()

        await list.rename(library.routineID, to: "Upper body")

        #expect(list.managementFailure == .writeFailed)
        #expect(list.routines.map(\.name) == ["Push"])
    }

    // MARK: - Archiving (FR-15.2.5)

    @Test("An archived routine leaves the list and stays in the store")
    func archiveHidesTheRoutine() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.archive(library.routineID)

        #expect(list.routines.isEmpty)
        #expect(list.phase == .ready)
        let kept = try await library.stack.routines.routines(includingDeleted: true)
        #expect(kept.map(\.id) == [library.routineID])
        // The cascade the repository promises: no live slot is left under a routine that is gone.
        #expect(try await library.slots(of: library.routineID).isEmpty)
    }

    @Test("A workout already started from the routine keeps its plan")
    func archiveLeavesStartedSessionsAlone() async throws {
        let library = try await Library.authored()
        let planned = try await library.planSession()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()

        await list.archive(library.routineID)

        // TR-15.3: a session copies its targets when it starts, so nothing under it hangs off the
        // routine that is now archived.
        let kept = try await library.stack.workouts.plannedTargets(
            forEntryID: planned, includingDeleted: false)
        #expect(kept.map(\.targetReps) == [5])
    }

    @Test("A refused archive says so and the routine is still listed")
    func archiveThatCannotBeWritten() async throws {
        let library = try await Library.authored()
        let store = FlakyRoutineRepository(library.stack.routines, refusingRoutineDeletes: true)
        let list = RoutineListState(repository: store)
        await list.load()

        await list.archive(library.routineID)

        #expect(list.managementFailure == .writeFailed)
        #expect(list.routines.count == 1)
    }

    // MARK: - What a read retires

    @Test("A fresh read retires a management refusal, as it retires a start refusal")
    func readRetiresTheRefusal() async throws {
        let library = try await Library.authored()
        let list = RoutineListState(repository: library.stack.routines)
        await list.load()
        await list.rename(library.routineID, to: " ")
        #expect(list.managementFailure == .nameRequired)

        await list.load()

        #expect(list.managementFailure == nil)
    }
}

/// A store holding one authored routine, and the reads a management test checks it with.
///
/// **Authored through the editor rather than written by hand**, on `RoutineListStateTests`' rule:
/// the rows a duplicate copies have to be the rows the app actually writes.
@MainActor
private struct Library {
    /// Where everything lives.
    let stack: InMemoryRepositoryStack

    /// The routine under test.
    let routineID: UUID

    /// When it was written, for the rename that must not move it.
    let createdAt: Date

    /// Its two exercises, in slot order.
    let exercises: [Exercise]

    /// Authors **Push**: two exercises, the first prescribing 100 kg × 5 × 3 and the second a blank
    /// target of 8 × 2 (`FR-15.2.2`).
    ///
    /// - Returns: The fixture.
    static func authored() async throws -> Library {
        let bench = routineExerciseFixture(name: "Bench Press")
        let dip = routineExerciseFixture(name: "Dip")
        let stack = try await seededStack([bench, dip])
        let author = editor(over: stack)
        await author.open(.create, screen: UUID())
        author.name = "Push"
        await author.addExercise(id: bench.id)
        await author.addExercise(id: dip.id)
        author.updateGroup(at: 0, inSlotAt: 0) { group in
            group.weightText = "100"
            group.repsText = "5"
            group.setsText = "3"
        }
        author.updateGroup(at: 0, inSlotAt: 1) { group in
            group.weightText = ""
            group.repsText = "8"
            group.setsText = "2"
        }
        await author.save()

        let stored = try await stack.routines.routines(includingDeleted: false)
        guard let routine = stored.first else { throw RoutineFixtureError.nothingAuthored }
        return Library(
            stack: stack,
            routineID: routine.id,
            createdAt: routine.createdAt,
            exercises: [bench, dip])
    }

    /// The live slots of one routine, in order.
    ///
    /// - Parameter routineID: Which routine.
    /// - Returns: Its slots.
    func slots(of routineID: UUID) async throws -> [RoutineExercise] {
        try await stack.routines.exercises(forRoutineID: routineID, includingDeleted: false)
    }

    /// The live target groups of one slot, in order.
    ///
    /// - Parameter slot: Which slot.
    /// - Returns: Its groups.
    func groups(of slot: RoutineExercise) async throws -> [RoutineTargetGroup] {
        try await stack.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)
    }

    /// Writes a session carrying one entry and the target the routine prescribed for it, the way
    /// `FR-15.2.3`'s start does (`TR-15.3`).
    ///
    /// - Returns: The entry the target hangs off.
    func planSession() async throws -> UUID {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            date: now,
            startedAt: now,
            endedAt: now,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil)
        try await stack.workouts.save(session)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercises[0].id,
            order: 0,
            notes: "")
        try await stack.workouts.save(entry)
        try await stack.workouts.save(
            PlannedTargetGroup(
                id: UUID(),
                createdAt: now,
                updatedAt: now,
                deletedAt: nil,
                exerciseEntryID: entry.id,
                order: 0,
                targetWeight: Weight(grams: 100_000),
                targetReps: 5,
                targetSets: 3))
        return entry.id
    }
}

/// What a fixture that could not set itself up throws.
private enum RoutineFixtureError: Error {
    /// The editor saved nothing.
    case nothingAuthored
}
