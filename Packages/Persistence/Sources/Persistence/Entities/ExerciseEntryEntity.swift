import Foundation
import SwiftData

/// One exercise performed within a session — the sets hang off this, not off the session
/// (`TR-0.3.3`).
@Model
final class ExerciseEntryEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``WorkoutSessionEntity`` this entry belongs to.
    ///
    /// A plain `UUID` column, because the schema declares no relationships (`G-2.5`) — so nothing
    /// enforces that the row exists, and a reference to a missing session is a repository concern.
    var sessionID: UUID = SchemaDefaults.unlinkedID

    /// The ``ExerciseEntity`` performed. Seeded exercise ids are permanent for this reason: they are
    /// in users' logged history and regenerating one orphans every set logged against it.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// Position within the session, ascending.
    ///
    /// Explicit because SwiftData's array order is not a contract, and reading order off a fetch
    /// that did not sort is a silent corruption rather than a visible one.
    var order: Int = 0

    var notes: String = ""

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        order: Int,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.order = order
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
