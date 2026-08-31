import Foundation
import RepositoryInterface

/// `RoutineRepository` over dictionaries (`TR-0.4.2`).
///
/// The three levels join by `UUID` here exactly as they do in the store, so the cascade is written
/// rather than inherited — the same shape ``InMemoryWorkoutRepository`` uses.
struct InMemoryRoutineRepository: RoutineRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Routines by name then id.
    func routines(includingDeleted: Bool) async throws -> [Routine] {
        await store.allRoutines(includingDeleted: includingDeleted)
    }

    /// The routine carrying `id`, or `nil`.
    func routine(id: UUID, includingDeleted: Bool) async throws -> Routine? {
        await store.routine(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the routine.
    func save(_ routine: Routine) async throws {
        await store.saveRoutine(routine)
    }

    /// Soft-deletes the routine, its exercise slots and their target groups, in one write.
    func deleteRoutine(id: UUID) async throws {
        try await store.deleteRoutine(id: id)
    }

    /// The routine's exercise slots, by order then id.
    func exercises(forRoutineID routineID: UUID, includingDeleted: Bool) async throws -> [RoutineExercise] {
        await store.allRoutineExercises(forRoutineID: routineID, includingDeleted: includingDeleted)
    }

    /// The slot carrying `id`, or `nil`.
    func routineExercise(id: UUID, includingDeleted: Bool) async throws -> RoutineExercise? {
        await store.routineExercise(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the slot, refusing a routine or exercise that does not exist.
    func save(_ exercise: RoutineExercise) async throws {
        try await store.saveRoutineExercise(exercise)
    }

    /// Soft-deletes the slot and its target groups.
    func deleteRoutineExercise(id: UUID) async throws {
        try await store.deleteRoutineExercise(id: id)
    }

    /// The slot's target groups, by order then id.
    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) async throws -> [RoutineTargetGroup] {
        await store.allTargetGroups(forRoutineExerciseID: routineExerciseID, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the group, refusing a slot that does not exist.
    func save(_ group: RoutineTargetGroup) async throws {
        try await store.saveTargetGroup(group)
    }

    /// Soft-deletes the group. Nothing else moves.
    func deleteTargetGroup(id: UUID) async throws {
        try await store.deleteTargetGroup(id: id)
    }
}

extension InMemoryRepositoryStore {
    /// Routines by name then id.
    func allRoutines(includingDeleted: Bool) -> [Routine] {
        routines.values
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
    }

    /// The routine carrying `id`, subject to the flag.
    func routine(id: UUID, includingDeleted: Bool) -> Routine? {
        routines[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `routine`.
    func saveRoutine(_ routine: Routine) {
        upserted(routine, into: &routines, at: .now)
    }

    /// Soft-deletes the routine and everything under it, in one write.
    ///
    /// **The slots swept include already-deleted ones** — for their *groups*, not for themselves.
    /// See ``InMemoryWorkoutRepository/deleteSession(id:)`` for why.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live routine
    ///   carries `id`.
    func deleteRoutine(id: UUID) throws {
        let now = Date.now
        try softDelete(id: id, in: &routines, at: now)
        cascade(
            intoRoutineExerciseIDs: routineExercises.values.filter { $0.routineID == id }.map(\.id),
            at: now
        )
    }

    /// The routine's exercise slots, by order then id.
    func allRoutineExercises(forRoutineID routineID: UUID, includingDeleted: Bool) -> [RoutineExercise] {
        routineExercises.values
            .filter { $0.routineID == routineID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.order, $0.id.uuidString) }
    }

    /// The slot carrying `id`, subject to the flag.
    func routineExercise(id: UUID, includingDeleted: Bool) -> RoutineExercise? {
        routineExercises[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `exercise`, checking both of its join keys.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when either names no row.
    func saveRoutineExercise(_ exercise: RoutineExercise) throws {
        try requireReferenced(routines, id: exercise.routineID, from: exercise.id)
        try requireReferenced(exercises, id: exercise.exerciseID, from: exercise.id)
        upserted(exercise, into: &routineExercises, at: .now)
    }

    /// Soft-deletes the slot and its target groups.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live slot
    ///   carries `id`.
    func deleteRoutineExercise(id: UUID) throws {
        let now = Date.now
        guard let exercise = routineExercises[id], !exercise.isSoftDeleted else {
            throw RepositoryError.recordNotFound(id: id)
        }
        cascade(intoRoutineExerciseIDs: [id], at: now)
    }

    /// The slot's target groups, by order then id.
    func allTargetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) -> [RoutineTargetGroup] {
        routineTargetGroups.values
            .filter { $0.routineExerciseID == routineExerciseID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.order, $0.id.uuidString) }
    }

    /// Inserts or replaces `group`, refusing a slot that does not exist.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when `routineExerciseID` names no row.
    func saveTargetGroup(_ group: RoutineTargetGroup) throws {
        try requireReferenced(routineExercises, id: group.routineExerciseID, from: group.id)
        upserted(group, into: &routineTargetGroups, at: .now)
    }

    /// Soft-deletes the group.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live group
    ///   carries `id`.
    func deleteTargetGroup(id: UUID) throws {
        try softDelete(id: id, in: &routineTargetGroups, at: .now)
    }

    /// Soft-deletes the named slots and every live group hanging off them, without a save of its
    /// own.
    ///
    /// Shared by the two cascading deletes, the same reason
    /// ``InMemoryWorkoutRepository/cascade(intoEntryIDs:at:)`` is. A slot already deleted keeps the
    /// date it left the lifter's routine *and* its `updatedAt`, while its live groups are swept like
    /// any other.
    private func cascade(intoRoutineExerciseIDs exerciseIDs: [UUID], at now: Date) {
        for id in exerciseIDs {
            guard let exercise = routineExercises[id] else { continue }
            routineExercises[id] = sweeping(exercise, at: now)
        }

        let swept = Set(exerciseIDs)
        for (id, group) in routineTargetGroups where swept.contains(group.routineExerciseID) {
            routineTargetGroups[id] = sweeping(group, at: now)
        }
    }
}
