import Foundation

/// One exercise performed within a session — the sets hang off this, not off the session
/// (`TR-0.3.3`).
public struct ExerciseEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``WorkoutSession`` this entry belongs to.
    ///
    /// A plain `UUID`: the schema declares no relationships (`G-2.5`), so nothing but a repository
    /// write enforces that the row exists.
    public let sessionID: UUID

    /// The ``Exercise`` performed.
    public let exerciseID: UUID

    /// Position within the session, ascending (`FR-1.2.2`). Zero-based, and the second key of the
    /// chronological order.
    public let order: Int

    /// Free-text notes.
    public let notes: String

    /// Creates an entry record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        sessionID: UUID,
        exerciseID: UUID,
        order: Int,
        notes: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.order = order
        self.notes = notes
    }
}
