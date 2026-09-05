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

    /// The ``ProgramRun/weekNumber`` this session was started under, or `nil` where it was not
    /// started from a program (`FR-16.8.3`).
    ///
    /// **Written once, at start, and never again.** A program edited afterwards — days reordered, a
    /// routine swapped, the week advanced — cannot reach this row, which is `TR-15.3`'s posture
    /// applied to the plan rather than to the targets: what a session was is a fact about the day it
    /// happened, not a view of the program as it stands now.
    public let weekNumber: Int?

    /// The ``ProgramDay/order`` this session was started from. See ``weekNumber``.
    public let dayIndex: Int?

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
        scheduledWorkoutID: UUID?,
        weekNumber: Int? = nil,
        dayIndex: Int? = nil
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
        self.weekNumber = weekNumber
        self.dayIndex = dayIndex
    }
}

// MARK: - Codable

extension WorkoutSession {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case date
        case startedAt
        case endedAt
        case notes
        case bodyweight
        case programRunID
        case scheduledWorkoutID
        case weekNumber
        case dayIndex
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            date: try container.decode(Date.self, forKey: .date),
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            endedAt: try container.decodeIfPresent(Date.self, forKey: .endedAt),
            notes: try container.decode(String.self, forKey: .notes),
            bodyweight: try container.decodeIfPresent(Weight.self, forKey: .bodyweight),
            programRunID: try container.decodeIfPresent(UUID.self, forKey: .programRunID),
            scheduledWorkoutID: try container.decodeIfPresent(
                UUID.self, forKey: .scheduledWorkoutID),
            weekNumber: try container.decodeIfPresent(Int.self, forKey: .weekNumber),
            dayIndex: try container.decodeIfPresent(Int.self, forKey: .dayIndex)
        )
    }

    /// Writes the thirteen keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(endedAt, forKey: .endedAt)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(bodyweight, forKey: .bodyweight)
        try container.encodeIfPresent(programRunID, forKey: .programRunID)
        try container.encodeIfPresent(scheduledWorkoutID, forKey: .scheduledWorkoutID)
        try container.encodeIfPresent(weekNumber, forKey: .weekNumber)
        try container.encodeIfPresent(dayIndex, forKey: .dayIndex)
    }
}
