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

// MARK: - Codable

extension ExerciseEntry {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case sessionID
        case exerciseID
        case order
        case notes
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            order: try container.decode(Int.self, forKey: .order),
            notes: try container.decode(String.self, forKey: .notes)
        )
    }

    /// Writes the eight keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(order, forKey: .order)
        try container.encode(notes, forKey: .notes)
    }
}
