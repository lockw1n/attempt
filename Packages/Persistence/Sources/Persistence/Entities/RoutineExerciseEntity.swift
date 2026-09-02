import Foundation
import SwiftData

/// One exercise slot within a routine — the target groups hang off this, not off the routine
/// (`FR-15.2.1`).
@Model
final class RoutineExerciseEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``RoutineEntity`` this slot belongs to.
    ///
    /// A plain `UUID` column, because the schema declares no relationships (`G-2.5`) — so nothing
    /// enforces that the row exists, and a reference to a missing routine is a repository concern.
    var routineID: UUID = SchemaDefaults.unlinkedID

    /// The ``ExerciseEntity`` prescribed. Seeded exercise ids are permanent for this reason: they
    /// are in a lifter's routines and regenerating one orphans every slot naming it.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// Position within the routine, ascending.
    ///
    /// Explicit for the same reason ``ExerciseEntryEntity/order`` is: SwiftData's array order is not
    /// a contract, and reading order off an unsorted fetch is a silent corruption rather than a
    /// visible one.
    var order: Int = 0

    init(
        id: UUID = UUID(),
        routineID: UUID,
        exerciseID: UUID,
        order: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.routineID = routineID
        self.exerciseID = exerciseID
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
