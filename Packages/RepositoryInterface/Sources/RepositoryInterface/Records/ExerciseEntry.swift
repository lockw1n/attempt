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

    /// Whether the lifter has said they are finished with this exercise (`FR-15.3.4`).
    ///
    /// **Stored rather than derived, and that is the requirement rather than a shortcut.** Whether
    /// every logged set is completed is a different question, already answered by counting them;
    /// this one is the lifter's own verdict, and the two disagree in both directions — three sets
    /// of a planned five can be enough for the day, and five completed sets need not end the
    /// exercise.
    ///
    /// **`true` with no working sets under it is an explicit skip**, which is a real outcome rather
    /// than an error state: the plan named an exercise and the lifter decided against it.
    ///
    /// **On the wire it is rule 7's**: a file written before the column existed reads `false` here
    /// rather than throwing, which is the same value the stored column backfills from.
    public let isMarkedDone: Bool

    /// Creates an entry record. No property is validated; see this module's header.
    ///
    /// ``isMarkedDone`` is the one parameter with a default, because it is the one column added
    /// after the record existed: `false` is what every row that predates it holds, and it is what
    /// every construction other than the check-off itself wants.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        sessionID: UUID,
        exerciseID: UUID,
        order: Int,
        notes: String,
        isMarkedDone: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.order = order
        self.notes = notes
        self.isMarkedDone = isMarkedDone
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
        case isMarkedDone
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
            notes: try container.decode(String.self, forKey: .notes),
            isMarkedDone: try container.decodeIfPresent(Bool.self, forKey: .isMarkedDone) ?? false
        )
    }

    /// Writes the nine keys in declaration order. ``isMarkedDone`` is written whatever it holds;
    /// only the *reading* of it tolerates absence, which is rule 7.
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
        try container.encode(isMarkedDone, forKey: .isMarkedDone)
    }
}
