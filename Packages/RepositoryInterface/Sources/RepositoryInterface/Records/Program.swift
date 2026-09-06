import Foundation

/// A named, ordered list of routines with a note — one week's plan (`FR-16.8.1`).
///
/// **The days hang off this, not the other way round**, the split every parent table in this module
/// uses. A program holds no weights and no prescriptions: each day names a ``Routine``, and the
/// loads are that routine's target groups.
///
/// **It is the thin precursor of `FR-2.1`, shaped so Phase 2 is an addition rather than a move.** A
/// week is a counter on the run rather than a row, and a block is nothing at all yet — so a
/// `ProgramWeekEntity` can be inserted between this and ``ProgramDay`` later without ``ProgramDay``
/// losing its ``ProgramDay/routineID``.
public struct Program: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The program's own name, as the lifter titled it.
    public let name: String

    /// The lifter's note on the program. Empty where they wrote none.
    public let notes: String

    /// Creates a program record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        name: String,
        notes: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.name = name
        self.notes = notes
    }
}

// MARK: - Codable

extension Program {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case name
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
            name: try container.decode(String.self, forKey: .name),
            notes: try container.decode(String.self, forKey: .notes)
        )
    }

    /// Writes the six keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(name, forKey: .name)
        try container.encode(notes, forKey: .notes)
    }
}
