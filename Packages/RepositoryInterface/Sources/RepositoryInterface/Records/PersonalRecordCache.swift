import Foundation
import PowerliftingCore

/// One cached N-rep max (`TR-0.3.9`, `G-1.5`).
///
/// **The one record with no repository behind it.** No Phase 0 requirement asks a repository to
/// read or write the cache, so none of the five protocols mentions this type; it exists because
/// `FR-1.11.3`'s backup covers every stored row and `TR-0.4.4`'s wire format is what a backup is
/// written in. A row nothing can export is a row a repair cannot see.
///
/// **A cached value is never the source of truth** (`G-1.4`): this is recomputed, and a restore that
/// reinstated a stale row would be reinstating an answer rather than the data behind it. Which is
/// why ``computationVersion`` travels with it — see `CachedDerivedEntity` for what that number does
/// and does not cover.
public struct PersonalRecordCache: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Exercise`` the record belongs to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The N this is the record for, **not** the reps the set was performed for: a 5-rep set holds
    /// the 1RM through the 5RM, so one ``sourceSetID`` legitimately appears on five rows at the same
    /// ``weight``. Unchecked here, as every range on a record is.
    public let repCount: Int

    /// The record weight. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The ``SetEntry`` holding the record.
    public let sourceSetID: UUID

    /// When the record was set, taken from the source set's session.
    public let achievedAt: Date

    /// The rules version that produced this row (`G-1.5`). Zero means none was recorded and matches
    /// no real version.
    public let computationVersion: Int

    /// Creates a cached record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        exerciseID: UUID,
        repCount: Int,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        computationVersion: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exerciseID = exerciseID
        self.repCount = repCount
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
        self.computationVersion = computationVersion
    }
}

// MARK: - Codable

extension PersonalRecordCache {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case exerciseID
        case repCount
        case weight
        case sourceSetID
        case achievedAt
        case computationVersion
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated, ``computationVersion``
    /// included — a zero means no version was recorded and is carried as one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            repCount: try container.decode(Int.self, forKey: .repCount),
            weight: try container.decode(Weight.self, forKey: .weight),
            sourceSetID: try container.decode(UUID.self, forKey: .sourceSetID),
            achievedAt: try container.decode(Date.self, forKey: .achievedAt),
            computationVersion: try container.decode(Int.self, forKey: .computationVersion)
        )
    }

    /// Writes the ten keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(repCount, forKey: .repCount)
        try container.encode(weight, forKey: .weight)
        try container.encode(sourceSetID, forKey: .sourceSetID)
        try container.encode(achievedAt, forKey: .achievedAt)
        try container.encode(computationVersion, forKey: .computationVersion)
    }
}
