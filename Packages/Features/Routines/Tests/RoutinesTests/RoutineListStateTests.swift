import Foundation
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

@MainActor
@Suite("Routine list")
struct RoutineListStateTests {
    @Test("An empty store is ready with nothing in it, not failed")
    func emptyStore() async {
        let state = RoutineListState(repository: InMemoryRepositoryStack().routines)
        await state.load()

        #expect(state.phase == .ready)
        #expect(state.routines.isEmpty)
    }

    @Test("Each row carries the routine's name and its exercise count")
    func rowsCarryTheirCounts() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let press = routineExerciseFixture(name: "Bench Press")
        let stack = try await seededStack([squat, press])
        let author = editor(over: stack)
        await author.open(.create, screen: UUID())
        author.name = "Two lifts"
        await author.addExercise(id: squat.id)
        await author.addExercise(id: press.id)
        for slot in 0...1 {
            author.updateGroup(at: 0, inSlotAt: slot) { group in
                group.weightText = "100"
                group.repsText = "5"
                group.setsText = "3"
            }
        }
        await author.save()

        let list = RoutineListState(repository: stack.routines)
        await list.load()

        #expect(list.phase == .ready)
        #expect(list.routines.map(\.name) == ["Two lifts"])
        #expect(list.routines.map(\.exerciseCount) == [2])
    }

    /// `FR-15.2.3`: a start that started nothing is reported, and the next one retires it.
    @Test("A start that did not start a workout is reported, and a fresh read retires it")
    func failedStartIsReportedThenRetired() async {
        let state = RoutineListState(repository: InMemoryRepositoryStack().routines)

        state.startDidFinish(.workoutInProgress)
        // Anchored to the case rather than to "is not nil": the two failures draw different
        // sentences, so a report that lost which one it was would still pass a nil check.
        #expect(state.startFailure == .workoutInProgress)

        state.startDidFinish(.started)
        #expect(state.startFailure == nil)

        state.startDidFinish(.workoutInProgress)
        await state.load()
        #expect(state.startFailure == nil)
    }

    /// The two failures are kept apart, which is the whole reason the outcome is not a `Bool`: a
    /// failed write names nothing the lifter can finish or discard.
    @Test("A failed write is reported as itself, not as a workout in progress")
    func failedStartWriteIsItsOwnFailure() {
        let state = RoutineListState(repository: InMemoryRepositoryStack().routines)

        state.startDidFinish(.writeFailed)

        #expect(state.startFailure == .writeFailed)
    }

    @Test("A failed read is a phase carrying the diagnostic, not an empty list")
    func failedRead() async {
        let state = RoutineListState(repository: RefusingRoutineRepository())
        await state.load()

        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(!diagnostic.isEmpty)
        #expect(state.routines.isEmpty)
    }
}

/// A repository whose every read throws — the one collaborator a failed-read test needs.
private struct RefusingRoutineRepository: RoutineRepository {
    /// What every call here throws.
    struct Refusal: Error {}

    func routines(includingDeleted: Bool) async throws -> [Routine] { throw Refusal() }

    func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? { throw Refusal() }

    func save(_ routine: Routine) async throws { throw Refusal() }

    func deleteRoutine(id: UUID) async throws { throw Refusal() }

    func exercises(
        forRoutineID routineID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineExercise] { throw Refusal() }

    func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? {
        throw Refusal()
    }

    func save(_ exercise: RoutineExercise) async throws { throw Refusal() }

    func deleteRoutineExercise(id: UUID) async throws { throw Refusal() }

    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup] { throw Refusal() }

    func save(_ group: RoutineTargetGroup) async throws { throw Refusal() }

    func deleteTargetGroup(id: UUID) async throws { throw Refusal() }
}
