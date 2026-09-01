import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Routines

/// A catalogue exercise a routine can prescribe.
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
        notes: "",
        manualE1RM: nil)
}

/// A stack whose catalogue already holds `exercises`, since a routine slot the repository will
/// accept has to name a row that exists.
func seededStack(_ exercises: [Exercise]) async throws -> InMemoryRepositoryStack {
    let stack = InMemoryRepositoryStack()
    for exercise in exercises {
        try await stack.exercises.save(exercise)
    }
    return stack
}

/// An editor over `stack`, in the locale and unit every test here uses.
///
/// **`en_US_POSIX` and kilograms deliberately**: the draft parses in a locale, so a test that took
/// the machine's own would pass or fail on where it ran.
@MainActor
func editor(over stack: InMemoryRepositoryStack) -> RoutineEditorState {
    editor(over: stack, routines: stack.routines)
}

/// An editor over `stack` whose routines are read and written through `routines` instead of the
/// stack's own — the seam a failing repository is injected at.
@MainActor
func editor(
    over stack: InMemoryRepositoryStack, routines: any RoutineRepository
) -> RoutineEditorState {
    let state = RoutineEditorState(
        repository: routines, catalogue: stack.exercises, settings: stack.settings)
    state.locale = Locale(identifier: "en_US_POSIX")
    return state
}

/// Fills a slot's first group with something storable, for the tests that are about the slots
/// rather than about the numbers in them.
@MainActor
func fillFirstGroup(_ state: RoutineEditorState, slot index: Int) {
    state.updateGroup(at: 0, inSlotAt: index) { group in
        group.weightText = "100"
        group.repsText = "5"
        group.setsText = "3"
    }
}

/// A routine store that forwards to another and refuses a chosen call.
///
/// Failures the in-memory stack cannot produce on its own, and none of them reachable without one:
/// a read that fails and then succeeds, which is what `reload()` is for; a delete that fails
/// *after* an earlier delete in the same save has already landed, which is the partial write a
/// retry has to be able to finish; and, for `FR-15.2.5`, a refused routine write or routine
/// delete — the store saying no to a management command that asked for nothing unusual.
@MainActor
final class FlakyRoutineRepository: RoutineRepository {
    /// What a refused call throws.
    struct Refusal: Error {}

    /// The store every call that is not refused goes to.
    private let base: any RoutineRepository

    /// How many reads are still owed a refusal before one is let through.
    private var readsToRefuse: Int

    /// Which `deleteRoutineExercise(id:)` call to refuse, counting from one, or `nil` for none.
    private let slotDeleteToRefuse: Int?

    /// How many slot deletes have been asked for so far.
    private var slotDeletes = 0

    /// Whether `save(_ routine:)` refuses (`FR-15.2.5`).
    private let refusesRoutineSaves: Bool

    /// Whether `deleteRoutine(id:)` refuses (`FR-15.2.5`).
    private let refusesRoutineDeletes: Bool

    /// Whether `save(_ exercise:)` refuses (`FR-15.2.5`).
    ///
    /// The seam a *partial* duplicate is built at: the routine row lands and the first slot under
    /// it does not, which is the one failure that can leave a copy half-written.
    private let refusesSlotSaves: Bool

    /// Wraps `base`.
    ///
    /// - Parameters:
    ///   - base: The store the calls that are not refused go to.
    ///   - refusingReads: How many reads to refuse before letting one through.
    ///   - refusingSlotDelete: Which slot delete to refuse, counting from one.
    ///   - refusingRoutineSaves: Whether every routine write is refused.
    ///   - refusingRoutineDeletes: Whether every routine delete is refused.
    ///   - refusingSlotSaves: Whether every slot write is refused.
    init(
        _ base: any RoutineRepository,
        refusingReads: Int = 0,
        refusingSlotDelete: Int? = nil,
        refusingRoutineSaves: Bool = false,
        refusingRoutineDeletes: Bool = false,
        refusingSlotSaves: Bool = false
    ) {
        self.base = base
        readsToRefuse = refusingReads
        slotDeleteToRefuse = refusingSlotDelete
        refusesRoutineSaves = refusingRoutineSaves
        refusesRoutineDeletes = refusingRoutineDeletes
        refusesSlotSaves = refusingSlotSaves
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

    func deleteRoutine(id: UUID) async throws {
        if refusesRoutineDeletes { throw Refusal() }
        try await base.deleteRoutine(id: id)
    }

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

    func save(_ exercise: RoutineExercise) async throws {
        if refusesSlotSaves { throw Refusal() }
        try await base.save(exercise)
    }

    func deleteRoutineExercise(id: UUID) async throws {
        slotDeletes += 1
        if slotDeletes == slotDeleteToRefuse { throw Refusal() }
        try await base.deleteRoutineExercise(id: id)
    }

    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup] {
        try await base.targetGroups(
            forRoutineExerciseID: routineExerciseID, includingDeleted: includingDeleted)
    }

    func save(_ group: RoutineTargetGroup) async throws { try await base.save(group) }

    func deleteTargetGroup(id: UUID) async throws { try await base.deleteTargetGroup(id: id) }

    /// Refuses this read, if any refusals are left to spend.
    private func refuseARead() throws {
        guard readsToRefuse > 0 else { return }
        readsToRefuse -= 1
        throw Refusal()
    }
}
