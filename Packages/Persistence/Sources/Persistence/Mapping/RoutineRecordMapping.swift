import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData

// The three routine entities. See `RecordMapping.swift` for the three members' contract and for why
// `update(from:)` leaves the audit columns alone.

extension RoutineEntity: RecordMappable {
    /// This row as a record.
    var record: Routine {
        Routine(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            name: name
        )
    }

    /// A new row carrying `record`.
    convenience init(record: Routine) {
        self.init(
            id: record.id,
            name: record.name,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: Routine) {
        name = record.name
    }
}

extension RoutineExerciseEntity: RecordMappable {
    /// This row as a record.
    var record: RoutineExercise {
        RoutineExercise(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            routineID: routineID,
            exerciseID: exerciseID,
            order: order
        )
    }

    /// A new row carrying `record`.
    convenience init(record: RoutineExercise) {
        self.init(
            id: record.id,
            routineID: record.routineID,
            exerciseID: record.exerciseID,
            order: record.order,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: RoutineExercise) {
        routineID = record.routineID
        exerciseID = record.exerciseID
        order = record.order
    }
}

extension RoutineTargetGroupEntity: RecordMappable {
    /// This row as a record.
    var record: RoutineTargetGroup {
        RoutineTargetGroup(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            routineExerciseID: routineExerciseID,
            order: order,
            targetWeight: Weight(grams: targetWeightGrams),
            targetReps: targetReps,
            targetSets: targetSets
        )
    }

    /// A new row carrying `record`.
    convenience init(record: RoutineTargetGroup) {
        self.init(
            id: record.id,
            routineExerciseID: record.routineExerciseID,
            order: record.order,
            targetWeightGrams: record.targetWeight.grams,
            targetReps: record.targetReps,
            targetSets: record.targetSets,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    /// Overwrites this row from `record`.
    func update(from record: RoutineTargetGroup) {
        routineExerciseID = record.routineExerciseID
        order = record.order
        targetWeightGrams = record.targetWeight.grams
        targetReps = record.targetReps
        targetSets = record.targetSets
    }
}
