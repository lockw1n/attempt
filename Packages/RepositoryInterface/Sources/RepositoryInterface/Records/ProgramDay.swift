import Foundation

/// One day of a program — a position, and the ``Routine`` trained at it (`FR-16.8.1`).
///
/// **It names a routine rather than holding one.** Two days may name the same routine, editing that
/// routine changes both, and `FR-16.8.5`'s "no weekday pinning" is this type declining to carry a
/// weekday at all: ``order`` is a position in the week's list and nothing more.
///
/// **A day may point at a routine the lifter has since archived.** `FR-15.2.5`'s archive is a soft
/// delete and nothing sweeps the days naming it, so the row survives its target — rule 4 of this
/// module's header, one level out: the dangling half costs that day, never the program. See
/// ``ProgramRepository/days(forProgramID:includingDeleted:)``.
public struct ProgramDay: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Program`` this day belongs to.
    ///
    /// A plain `UUID`: the schema declares no relationships (`G-2.5`), so nothing but a repository
    /// write enforces that the row exists.
    public let programID: UUID

    /// The ``Routine`` trained on this day.
    public let routineID: UUID

    /// Position within the program, ascending — the index `FR-16.8.3` records on a session.
    public let order: Int

    /// Creates a program-day record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        programID: UUID,
        routineID: UUID,
        order: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.programID = programID
        self.routineID = routineID
        self.order = order
    }
}

// MARK: - Codable

extension ProgramDay {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case programID
        case routineID
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
            programID: try container.decode(UUID.self, forKey: .programID),
            routineID: try container.decode(UUID.self, forKey: .routineID),
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
        try container.encode(programID, forKey: .programID)
        try container.encode(routineID, forKey: .routineID)
        try container.encode(order, forKey: .order)
    }
}
