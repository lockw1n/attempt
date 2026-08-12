import Foundation
import PowerliftingCore

/// One training session (`TR-0.3.2`).
public struct WorkoutSession: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The training day this session belongs to, which is not necessarily when it was entered
    /// (`FR-1.2.1` backdates).
    ///
    /// **A correctness input rather than a display field.** It is the first key of the
    /// chronological order a personal-record computation depends on; see
    /// ``WorkoutRepository/sets(forExerciseID:includingDeleted:)``.
    public let date: Date

    /// When the session was started, if it was tracked live (`FR-1.2.11`).
    public let startedAt: Date?

    /// When the session was finished, if it was tracked live.
    public let endedAt: Date?

    /// Session-level notes (`FR-1.2.9`).
    public let notes: String

    /// Bodyweight recorded alongside the session, or `nil` if none was.
    ///
    /// Distinct from ``BodyweightEntry``, which is the log `FR-1.8.3` lists and exists on days with
    /// no training on them.
    public let bodyweight: Weight?

    /// A forward reference to a Phase 2 entity that does not exist yet. Nothing in Phase 0 reads or
    /// writes it (`OUT-0.3` defers the storage, not the field).
    public let programRunID: UUID?

    /// See ``programRunID``.
    public let scheduledWorkoutID: UUID?

    /// Creates a session record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        date: Date,
        startedAt: Date?,
        endedAt: Date?,
        notes: String,
        bodyweight: Weight?,
        programRunID: UUID?,
        scheduledWorkoutID: UUID?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.bodyweight = bodyweight
        self.programRunID = programRunID
        self.scheduledWorkoutID = scheduledWorkoutID
    }
}
