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
///
/// **A row is one cell of `FR-16.2.1`'s scheme table**, keyed by ``repCount`` *and* ``setCount``
/// together. `FR-1.6.1`'s N-rep max is the `setCount == 1` column of it, which is why a reader that
/// only wants rep maxes filters rather than reading a different table.
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

    /// How many consecutive sets the scheme asks for — the `× 4` (`FR-16.2.1`, `TR-16.1`).
    ///
    /// One for a row written before the column existed, and one for every `FR-1.6.1` rep max.
    /// Unchecked, as ``repCount`` is.
    public let setCount: Int

    /// The record weight. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The ``SetEntry`` holding the record — the record-setting run's **first** set.
    ///
    /// **The first, not the set that completed the scheme**, and the choice is what keeps one run
    /// one event. Which set completes a scheme depends on the cell — two sets complete a two-set
    /// scheme and five a five-set one — so dating each cell from its own completing set would give
    /// one run up to sixty identities and split `FR-1.6.5`'s feed into sixty rows of the same
    /// performance. Every cell a run establishes therefore names the run's first set, which is
    /// `SetGroup`'s own identity, and grouping the cache's rows on it recovers the run.
    ///
    /// **The run's other set ids are not stored**, deliberately: `TR-16.1` adds two columns and a
    /// list column would be a third whose members are already reachable — a reader holding the
    /// entry's sets recovers the run from this id and ``setCount``.
    public let sourceSetID: UUID

    /// When the record was set, taken from the source set's session.
    public let achievedAt: Date

    /// The load this record beat at this scheme, or `nil` for a baseline — the first time the
    /// scheme was ever performed for this exercise (`FR-16.2.3`, `TR-16.1`).
    ///
    /// **Optional rather than zero**, because `Weight` is signed and a beaten load of zero is a real
    /// one; `FR-16.3.4` hides baselines by default, so the two have to be distinguishable.
    public let previousWeight: Weight?

    /// The rules version that produced this row (`G-1.5`). Zero means none was recorded and matches
    /// no real version.
    public let computationVersion: Int

    /// The cell this row is the record for.
    public var scheme: RecordScheme { RecordScheme(reps: repCount, sets: setCount) }

    /// Creates a cached record. No property is validated; see this module's header.
    ///
    /// ``setCount`` and ``previousWeight`` default to the `FR-1.6.1` rep max's own values — one set,
    /// no beaten load — so a caller that predates `FR-16.2` states the same row it always did.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        exerciseID: UUID,
        repCount: Int,
        setCount: Int = 1,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        previousWeight: Weight? = nil,
        computationVersion: Int
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exerciseID = exerciseID
        self.repCount = repCount
        self.setCount = setCount
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
        self.previousWeight = previousWeight
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
        case setCount
        case weight
        case sourceSetID
        case achievedAt
        case previousWeight
        case computationVersion
    }

    /// Decodes the keyed shape on ``CodingKeys``. Nothing is validated, ``computationVersion``
    /// included — a zero means no version was recorded and is carried as one.
    ///
    /// **An absent ``setCount`` decodes as one and an absent ``previousWeight`` as a baseline**, so
    /// a file written before `TR-16.1` reads back as the rep-max table it was.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            repCount: try container.decode(Int.self, forKey: .repCount),
            setCount: try container.decodeIfPresent(Int.self, forKey: .setCount) ?? 1,
            weight: try container.decode(Weight.self, forKey: .weight),
            sourceSetID: try container.decode(UUID.self, forKey: .sourceSetID),
            achievedAt: try container.decode(Date.self, forKey: .achievedAt),
            previousWeight: try container.decodeIfPresent(Weight.self, forKey: .previousWeight),
            computationVersion: try container.decode(Int.self, forKey: .computationVersion)
        )
    }

    /// Writes the keys in declaration order — twelve, or eleven for a baseline, which writes no
    /// ``previousWeight``.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(repCount, forKey: .repCount)
        try container.encode(setCount, forKey: .setCount)
        try container.encode(weight, forKey: .weight)
        try container.encode(sourceSetID, forKey: .sourceSetID)
        try container.encode(achievedAt, forKey: .achievedAt)
        try container.encodeIfPresent(previousWeight, forKey: .previousWeight)
        try container.encode(computationVersion, forKey: .computationVersion)
    }
}
