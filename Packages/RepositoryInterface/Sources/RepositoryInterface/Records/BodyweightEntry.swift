import Foundation
import PowerliftingCore

/// One bodyweight reading (`TR-0.3.5`).
public struct BodyweightEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The day the reading is for, which is not necessarily when it was entered (`FR-1.8.1`).
    public let date: Date

    /// The reading. Signed by type; a real one is not.
    public let weight: Weight

    /// Where the reading came from — what `FR-1.8.2`'s de-duplication of HealthKit readings
    /// against manual ones keys on.
    public let source: BodyweightSource

    /// Creates a bodyweight record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        date: Date,
        weight: Weight,
        source: BodyweightSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.date = date
        self.weight = weight
        self.source = source
    }
}

// MARK: - Codable

extension BodyweightEntry {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case date
        case weight
        case source
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated; ``source`` resolves rather
    /// than throwing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            date: try container.decode(Date.self, forKey: .date),
            weight: try container.decode(Weight.self, forKey: .weight),
            source: try container.decodeVocabulary(
                BodyweightSource.self, forKey: .source, or: RecordVocabulary.bodyweightSource)
        )
    }

    /// Writes the seven keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(date, forKey: .date)
        try container.encode(weight, forKey: .weight)
        try container.encodeVocabulary(source, forKey: .source)
    }
}
