import Foundation

/// Routines, the exercise slots within them, and the target groups within those (`TR-0.4.1`,
/// `FR-15.2`).
///
/// Three levels rather than one nested tree, for the same reason ``WorkoutRepository`` is: the
/// schema declares no relationships (`G-2.5`) and a repository that returned a tree would be
/// inventing one. What it does own is the **order** of the slots within a routine and of the target
/// groups within a slot.
public protocol RoutineRepository: Sendable {
    /// Every routine (`FR-15.2.1`), by name then id.
    func routines(includingDeleted: Bool) async throws -> [Routine]

    /// One routine, or `nil` if no row carries that id.
    func routine(id: UUID, includingDeleted: Bool) async throws -> Routine?

    /// Inserts or replaces the routine, keyed on ``Routine/id``.
    func save(_ routine: Routine) async throws

    /// Soft-deletes the routine and, with it, its exercise slots and their target groups.
    ///
    /// The cascade is deliberate, matching ``WorkoutRepository/deleteSession(id:)``'s: nothing in the store performs
    /// it, so a routine deleted alone would leave its slots live and readable under a plan that no
    /// longer exists.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live routine carries that id.
    func deleteRoutine(id: UUID) async throws

    /// The exercise slots in one routine, in ``RoutineExercise/order``.
    func exercises(forRoutineID routineID: UUID, includingDeleted: Bool) async throws -> [RoutineExercise]

    /// One slot, or `nil` if no row carries that id.
    func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise?

    /// Inserts or replaces the slot, keyed on ``RoutineExercise/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the routine or the
    ///   exercise does not exist.
    func save(_ exercise: RoutineExercise) async throws

    /// Soft-deletes the slot and its target groups. See ``deleteRoutine(id:)`` for why it cascades.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live slot carries that id.
    func deleteRoutineExercise(id: UUID) async throws

    /// The target groups in one slot, in ``RoutineTargetGroup/order`` (`FR-15.2.1`'s amendment).
    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup]

    /// Inserts or replaces the group, keyed on ``RoutineTargetGroup/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the slot does not
    ///   exist.
    func save(_ group: RoutineTargetGroup) async throws

    /// Soft-deletes one target group. Nothing cascades from here.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live group carries that id.
    func deleteTargetGroup(id: UUID) async throws
}
