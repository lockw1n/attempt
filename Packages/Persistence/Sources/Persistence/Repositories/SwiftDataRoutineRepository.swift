import Foundation
import RepositoryInterface
import SwiftData

/// `RoutineRepository` over SwiftData (`TR-0.4.2`, `FR-15.2`).
///
/// Three levels joined by `UUID` columns, because `G-2.5` forbids relationships — so the cascade is
/// written here rather than inherited from the store, the same shape ``SwiftDataWorkoutRepository``
/// uses for sessions, entries and sets.
@ModelActor
actor SwiftDataRoutineRepository: RoutineRepository {
    func routines(includingDeleted: Bool) throws -> [Routine] {
        try modelContext.rows(RoutineEntity.self, includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
            .map(\.record)
    }

    func routine(id: UUID, includingDeleted: Bool) throws -> Routine? {
        try modelContext.row(RoutineEntity.self, id: id, includingDeleted: includingDeleted)?.record
    }

    func save(_ routine: Routine) throws {
        try modelContext.upsert(routine, as: RoutineEntity.self)
        try modelContext.saveStamped()
    }

    /// Soft-deletes the routine, its exercise slots and their target groups, in one write.
    ///
    /// **Every row carrying `id` is swept, not just the one a read would return** — see
    /// ``SwiftDataWorkoutRepository/deleteSession(id:)`` for why.
    func deleteRoutine(id: UUID) throws {
        let routines = try modelContext.rows(RoutineEntity.self, id: id, includingDeleted: false)
        guard !routines.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for routine in routines { routine.markDeleted(at: now) }

        // Deleted slots are swept in too — for their *groups*, not for themselves. A foreign row
        // can arrive with a slot already gone and a live group under it, and this promise is that a
        // deleted routine leaves no live group anywhere under it.
        let exercises = try modelContext.rows(
            RoutineExerciseEntity.self,
            matching: #Predicate { $0.routineID == id },
            includingDeleted: true
        )
        try cascade(into: exercises, at: now)
        try modelContext.saveStamped(at: now)
    }

    func exercises(forRoutineID routineID: UUID, includingDeleted: Bool) throws -> [RoutineExercise] {
        try modelContext.rows(
            RoutineExerciseEntity.self,
            matching: #Predicate { $0.routineID == routineID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func routineExercise(id: UUID, includingDeleted: Bool) throws -> RoutineExercise? {
        try modelContext.row(RoutineExerciseEntity.self, id: id, includingDeleted: includingDeleted)?
            .record
    }

    func save(_ exercise: RoutineExercise) throws {
        try modelContext.requireReferenced(RoutineEntity.self, id: exercise.routineID, from: exercise.id)
        try modelContext.requireReferenced(ExerciseEntity.self, id: exercise.exerciseID, from: exercise.id)
        try modelContext.upsert(exercise, as: RoutineExerciseEntity.self)
        try modelContext.saveStamped()
    }

    func deleteRoutineExercise(id: UUID) throws {
        let exercises = try modelContext.rows(
            RoutineExerciseEntity.self, id: id, includingDeleted: false)
        guard !exercises.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        try cascade(into: exercises, at: now)
        try modelContext.saveStamped(at: now)
    }

    func targetGroups(
        forRoutineExerciseID routineExerciseID: UUID, includingDeleted: Bool
    ) throws -> [RoutineTargetGroup] {
        try modelContext.rows(
            RoutineTargetGroupEntity.self,
            matching: #Predicate { $0.routineExerciseID == routineExerciseID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.order, $0.id.uuidString) }
        .map(\.record)
    }

    func save(_ group: RoutineTargetGroup) throws {
        try modelContext.requireReferenced(
            RoutineExerciseEntity.self, id: group.routineExerciseID, from: group.id)
        try modelContext.upsert(group, as: RoutineTargetGroupEntity.self)
        try modelContext.saveStamped()
    }

    func deleteTargetGroup(id: UUID) throws {
        let groups = try modelContext.rows(RoutineTargetGroupEntity.self, id: id, includingDeleted: false)
        guard !groups.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for group in groups { group.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }

    /// Soft-deletes `exercises` and every target group hanging off them, without saving.
    ///
    /// Shared by the two cascading deletes, for the reason `SwiftDataWorkoutRepository`'s own
    /// cascade is: "a deleted slot never leaves a live group" is one piece of code rather than an
    /// obligation on two. A slot already deleted keeps the date it was deleted on — re-stamping it
    /// would relabel when it left the lifter's routine — while its live groups are swept like any
    /// other.
    private func cascade(into exercises: [RoutineExerciseEntity], at now: Date) throws {
        for exercise in exercises where !exercise.isSoftDeleted { exercise.markDeleted(at: now) }

        let exerciseIDs = exercises.map(\.id)
        guard !exerciseIDs.isEmpty else { return }
        let groups = try modelContext.rows(
            RoutineTargetGroupEntity.self,
            matching: #Predicate { exerciseIDs.contains($0.routineExerciseID) },
            includingDeleted: false
        )
        for group in groups { group.markDeleted(at: now) }
    }
}
