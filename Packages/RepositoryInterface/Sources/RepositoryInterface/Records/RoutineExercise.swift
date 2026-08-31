import Foundation

/// One exercise slot within a routine — the target groups hang off this, not off the routine
/// (`FR-15.2.1`).
public struct RoutineExercise: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Routine`` this slot belongs to.
    ///
    /// A plain `UUID`: the schema declares no relationships (`G-2.5`), so nothing but a repository
    /// write enforces that the row exists.
    public let routineID: UUID

    /// The ``Exercise`` prescribed.
    public let exerciseID: UUID

    /// Position within the routine, ascending.
    public let order: Int

    /// Creates a routine-exercise record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        routineID: UUID,
        exerciseID: UUID,
        order: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.routineID = routineID
        self.exerciseID = exerciseID
        self.order = order
    }
}

// MARK: - Codable

extension RoutineExercise {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case routineID
        case exerciseID
        case order
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            routineID: try container.decode(UUID.self, forKey: .routineID),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            order: try container.decode(Int.self, forKey: .order)
        )
    }

    /// Writes the seven keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(routineID, forKey: .routineID)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(order, forKey: .order)
    }
}
