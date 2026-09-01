import Foundation
import SwiftData

/// One target weight/rep/set group planned for an exercise in a session (`TR-15.3`) — the routine's
/// target as it stood when the workout was started.
///
/// **A copy of a routine's group rather than a pointer at one**, which is `TR-15.3`'s whole
/// requirement: a routine edited next week must not change what a session logged last week was told
/// to lift, and a stored routine identifier would answer that question with today's numbers. There
/// is deliberately no column naming the ``RoutineTargetGroupEntity`` this was taken from.
///
/// **The weight column holds an already-resolved number**, not a prescription: the routine's
/// ``PowerliftingCore/Prescription`` was resolved on the way in. That is the same one-payload-column
/// shape ``RoutineTargetGroupEntity`` has, for a different reason — there the enum has one reachable
/// case, here the enum is gone by the time a row is written.
@Model
final class PlannedTargetGroupEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ExerciseEntryEntity`` this group was planned for.
    var exerciseEntryID: UUID = SchemaDefaults.unlinkedID

    /// Position within the exercise, ascending — the top set before the backoff, for instance.
    var order: Int = 0

    /// The resolved load on **one** implement, in grams (`G-1.1`), or `nil` where the plan named
    /// no weight (`FR-15.2.2`).
    ///
    /// **Optional so that blank is a value rather than a zero**, exactly as
    /// ``RoutineTargetGroupEntity/targetWeightGrams`` is: a lifter who planned `5×5` without
    /// deciding the load has not planned an empty bar.
    var targetWeightGrams: Int?

    /// Reps prescribed per set in this group.
    var targetReps: Int = 0

    /// Sets prescribed in this group.
    var targetSets: Int = 0

    init(
        id: UUID = UUID(),
        exerciseEntryID: UUID,
        order: Int,
        targetWeightGrams: Int?,
        targetReps: Int,
        targetSets: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseEntryID = exerciseEntryID
        self.order = order
        self.targetWeightGrams = targetWeightGrams
        self.targetReps = targetReps
        self.targetSets = targetSets
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
