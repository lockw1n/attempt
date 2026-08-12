import Foundation
import PowerliftingCore

/// One gym's bar, collars and plates (`TR-0.3.7`, `FR-1.4.2`, `FR-1.4.3`).
///
/// **The inventory is two positionally paired lists rather than a `PlateInventory`**, and that is
/// the refusal rule in this module's header at its sharpest. `PlateInventory` rejects a repeated
/// denomination rather than summing it and rejects a negative pair count, so embedding one would
/// make a profile that breaks either invariant unrepresentable — and the two lists are separate
/// CloudKit record fields, so a synced profile can arrive with one and not the other and disagree
/// in length. Refusing at the read would cost the profile and its name; dropping the offending
/// denomination would be worse still, because `PlateCalculator` would then propose a loading the
/// gym cannot make. The row comes back whole and the `PlateInventory` projection is where it
/// refuses (T-0.41).
public struct EquipmentProfile: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The user's name for this profile — "home gym", "the meet" (`FR-1.4.3`).
    public let name: String

    /// The bar's own mass.
    public let barWeight: Weight

    /// The mass of **one** collar, matching `PlateCalculator`, which loads
    /// `bar + 2 × collar + 2 × (per-side plates)`. Zero for a bar loaded without them.
    public let collarWeight: Weight

    /// The denominations stocked, heaviest first.
    ///
    /// Positionally paired with ``platePairCounts``: index *i* of each describes one denomination.
    /// A foreign row may break the pairing; see this type's note.
    public let plates: [Weight]

    /// How many **pairs** of each denomination in ``plates`` the gym has. Zero is legal.
    public let platePairCounts: [Int]

    /// Whether this is the profile the plate calculator reaches for by default.
    ///
    /// **Read-only through a save.** ``EquipmentRepository/makeDefault(profileID:)`` is the only
    /// writer, because "exactly one default" is a cross-row invariant and no single row's save can
    /// clear the others (`G-2.5` forbids a constraint that would).
    public let isDefault: Bool

    /// Creates a profile record. No property is validated; see this type's note.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        name: String,
        barWeight: Weight,
        collarWeight: Weight,
        plates: [Weight],
        platePairCounts: [Int],
        isDefault: Bool
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.name = name
        self.barWeight = barWeight
        self.collarWeight = collarWeight
        self.plates = plates
        self.platePairCounts = platePairCounts
        self.isDefault = isDefault
    }
}

// MARK: - Codable

extension EquipmentProfile {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    ///
    /// ``plates`` and ``platePairCounts`` are two arrays rather than one array of pairs, mirroring
    /// the two stored columns: a backup whose lists disagree in length has to say so, and one
    /// array of pairs could not carry that.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case name
        case barWeight
        case collarWeight
        case plates
        case platePairCounts
        case isDefault
    }

    /// Decodes the keyed shape on ``CodingKeys``. The two lists are not checked against each other;
    /// see ``EquipmentProfile/inventory()``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            name: try container.decode(String.self, forKey: .name),
            barWeight: try container.decode(Weight.self, forKey: .barWeight),
            collarWeight: try container.decode(Weight.self, forKey: .collarWeight),
            plates: try container.decode([Weight].self, forKey: .plates),
            platePairCounts: try container.decode([Int].self, forKey: .platePairCounts),
            isDefault: try container.decode(Bool.self, forKey: .isDefault)
        )
    }

    /// Writes the ten keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(name, forKey: .name)
        try container.encode(barWeight, forKey: .barWeight)
        try container.encode(collarWeight, forKey: .collarWeight)
        try container.encode(plates, forKey: .plates)
        try container.encode(platePairCounts, forKey: .platePairCounts)
        try container.encode(isDefault, forKey: .isDefault)
    }
}
