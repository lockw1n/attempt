import Foundation
import SwiftData

/// One target weight/rep/set group within a routine's exercise slot (`FR-15.2.1`'s amendment) — a
/// slot may carry more than one, e.g. `80×5×4` then `90×4×4` as a top set and a backoff.
///
/// **The payload is `Prescription`'s (`TR-0.2.10`), not a bare stored number**, and this slice
/// writes only its `.fixedWeight` payload column — see `RoutineTargetGroup.prescription` for the
/// projection. Adding a second `Prescription` case is a schema change: a discriminator column plus
/// that case's own payload columns, all optional, following ``TrainingMaxConfigEntity``'s split of
/// `sourceRawValue` from its per-source payload columns.
@Model
final class RoutineTargetGroupEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``RoutineExerciseEntity`` this group belongs to.
    var routineExerciseID: UUID = SchemaDefaults.unlinkedID

    /// Position within the slot, ascending — the top set before the backoff, for instance.
    var order: Int = 0

    /// The load on **one** implement, in grams (`G-1.1`) —
    /// ``PowerliftingCore/Prescription/fixedWeight(_:)``'s payload.
    var targetWeightGrams: Int = 0

    /// Reps prescribed per set in this group.
    var targetReps: Int = 0

    /// Sets prescribed in this group.
    var targetSets: Int = 0

    init(
        id: UUID = UUID(),
        routineExerciseID: UUID,
        order: Int,
        targetWeightGrams: Int,
        targetReps: Int,
        targetSets: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineExerciseID = routineExerciseID
        self.order = order
        self.targetWeightGrams = targetWeightGrams
        self.targetReps = targetReps
        self.targetSets = targetSets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
