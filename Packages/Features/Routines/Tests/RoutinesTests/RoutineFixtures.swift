import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Routines

/// A catalogue exercise a day can prescribe.
func routineExerciseFixture(name: String) -> Exercise {
    Exercise(
        id: UUID(),
        createdAt: .now,
        updatedAt: .now,
        deletedAt: nil,
        name: name,
        ukrainianName: nil,
        movement: .squat,
        parentExerciseID: nil,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        implementCount: 1,
        isCustom: true,
        isArchived: false,
        notes: "")
}

/// A stack whose catalogue already holds `exercises`, since a slot the repository will accept has
/// to name a row that exists.
func seededStack(_ exercises: [Exercise]) async throws -> InMemoryRepositoryStack {
    let stack = InMemoryRepositoryStack()
    for exercise in exercises {
        try await stack.exercises.save(exercise)
    }
    return stack
}

/// A week editor over `stack`, in the locale and unit every test here uses.
///
/// **`en_US_POSIX` and kilograms deliberately**: the draft parses in a locale, so a test that took
/// the machine's own would pass or fail on where it ran.
@MainActor
func weekEditor(over stack: InMemoryRepositoryStack) -> WeekEditorState {
    weekEditor(over: stack, routines: stack.routines, programs: stack.programs)
}

/// A week editor over `stack` whose routines or programs are read and written through another
/// store — the seam a failing repository is injected at.
@MainActor
func weekEditor(
    over stack: InMemoryRepositoryStack,
    routines: any RoutineRepository,
    programs: any ProgramRepository
) -> WeekEditorState {
    let state = WeekEditorState(
        programs: programs,
        routines: routines,
        catalogue: stack.exercises,
        settings: stack.settings)
    state.locale = Locale(identifier: "en_US_POSIX")
    return state
}

/// Opens `state` on a fresh screen, which is how every test here reads.
@MainActor
func opened(_ state: WeekEditorState) async -> WeekEditorState {
    await state.open(screen: UUID())
    return state
}

/// Fills a target group with something storable, for the tests that are about the rows rather than
/// about the numbers in them.
@MainActor
func fillTarget(
    _ state: WeekEditorState,
    day: Int = 0,
    slot: Int = 0,
    group: Int = 0,
    weight: String = "100",
    reps: String = "5",
    sets: String = "3"
) async {
    state.editTarget(group, inSlot: slot, inDayAt: day) { draft in
        draft.weightText = weight
        draft.repsText = reps
        draft.setsText = sets
    }
    await state.commitTarget(group, inSlot: slot, inDayAt: day)
}

/// A routine store that forwards to another and refuses a chosen kind of call.
///
/// Failures the in-memory stack cannot produce on its own: a read that fails and then succeeds,
/// which is what `reload()` is for, and a refused write on a command that asked for nothing
/// unusual.
@MainActor
final class FlakyRoutineRepository: RoutineRepository {
    /// What a refused call throws.
    struct Refusal: Error {}

    /// The store every call that is not refused goes to.
    private let base: any RoutineRepository

    /// How many reads are still owed a refusal before one is let through.
    private var readsToRefuse: Int

    /// Whether `save(_ routine:)` refuses.
    private let refusesRoutineSaves: Bool

    /// Whether `save(_ group:)` refuses — the seam a write-through target failure is made at.
    private let refusesTargetSaves: Bool

    /// Wraps `base`.
    ///
    /// - Parameters:
    ///   - base: The store the calls that are not refused go to.
    ///   - refusingReads: How many reads to refuse before letting one through.
    ///   - refusingRoutineSaves: Whether every routine write is refused.
    ///   - refusingTargetSaves: Whether every target write is refused.
    init(
        _ base: any RoutineRepository,
        refusingReads: Int = 0,
        refusingRoutineSaves: Bool = false,
        refusingTargetSaves: Bool = false
    ) {
        self.base = base
        readsToRefuse = refusingReads
        refusesRoutineSaves = refusingRoutineSaves
        refusesTargetSaves = refusingTargetSaves
    }

    func routines(includingDeleted: Bool) async throws -> [Routine] {
        try refuseARead()
        return try await base.routines(includingDeleted: includingDeleted)
    }

    func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? {
        try refuseARead()
        return try await base.routine(id: id, includingDeleted: includingDeleted)
    }

    func save(_ routine: Routine) async throws {
        if refusesRoutineSaves { throw Refusal() }
        try await base.save(routine)
    }

    func deleteRoutine(id: UUID) async throws { try await base.deleteRoutine(id: id) }

    func exercises(
        forRoutineID routineID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineExercise] {
        try refuseARead()
        return try await base.exercises(
            forRoutineID: routineID, includingDeleted: includingDeleted)
    }

    func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? {
        try await base.routineExercise(id: id, includingDeleted: includingDeleted)
    }

    func save(_ exercise: RoutineExercise) async throws { try await base.save(exercise) }

    func deleteRoutineExercise(id: UUID) async throws {
        try await base.deleteRoutineExercise(id: id)
    }

    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup] {
        try await base.targetGroups(
            forRoutineExerciseID: routineExerciseID, includingDeleted: includingDeleted)
    }

    func save(_ group: RoutineTargetGroup) async throws {
        if refusesTargetSaves { throw Refusal() }
        try await base.save(group)
    }

    func deleteTargetGroup(id: UUID) async throws { try await base.deleteTargetGroup(id: id) }

    /// Refuses this read, if any refusals are left to spend.
    private func refuseARead() throws {
        guard readsToRefuse > 0 else { return }
        readsToRefuse -= 1
        throw Refusal()
    }
}

/// A program store that forwards to another and refuses every day write.
///
/// The seam the week's own write-through failures are made at — a store that will not take a day is
/// what ``Routines/WeekEditorState/writeFailed`` reports.
@MainActor
final class FlakyProgramRepository: ProgramRepository {
    /// What a refused call throws.
    struct Refusal: Error {}

    /// The store every call that is not refused goes to.
    private let base: any ProgramRepository

    /// Whether `save(_ day:)` refuses.
    private let refusesDaySaves: Bool

    /// Wraps `base`.
    ///
    /// - Parameters:
    ///   - base: The store the calls that are not refused go to.
    ///   - refusingDaySaves: Whether every day write is refused.
    init(_ base: any ProgramRepository, refusingDaySaves: Bool = false) {
        self.base = base
        refusesDaySaves = refusingDaySaves
    }

    func programs(includingDeleted: Bool) async throws -> [Program] {
        try await base.programs(includingDeleted: includingDeleted)
    }

    func program(id: UUID, includingDeleted: Bool) async throws -> Program? {
        try await base.program(id: id, includingDeleted: includingDeleted)
    }

    func save(_ program: Program) async throws { try await base.save(program) }

    func deleteProgram(id: UUID) async throws { try await base.deleteProgram(id: id) }

    func days(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramDay] {
        try await base.days(forProgramID: programID, includingDeleted: includingDeleted)
    }

    func programDay(id: UUID, includingDeleted: Bool) async throws -> ProgramDay? {
        try await base.programDay(id: id, includingDeleted: includingDeleted)
    }

    func save(_ day: ProgramDay) async throws {
        if refusesDaySaves { throw Refusal() }
        try await base.save(day)
    }

    func deleteDay(id: UUID) async throws { try await base.deleteDay(id: id) }

    func currentRun() async throws -> ProgramRun? { try await base.currentRun() }

    func runs(forProgramID programID: UUID, includingDeleted: Bool) async throws -> [ProgramRun] {
        try await base.runs(forProgramID: programID, includingDeleted: includingDeleted)
    }

    func run(id: UUID, includingDeleted: Bool) async throws -> ProgramRun? {
        try await base.run(id: id, includingDeleted: includingDeleted)
    }

    func startRun(_ run: ProgramRun) async throws { try await base.startRun(run) }

    func save(_ run: ProgramRun) async throws { try await base.save(run) }

    func deleteRun(id: UUID) async throws { try await base.deleteRun(id: id) }
}
