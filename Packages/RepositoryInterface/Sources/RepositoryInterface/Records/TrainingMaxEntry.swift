import Foundation
import PowerliftingCore

/// How one exercise's training max is computed, from a given date (`TR-0.3.6`, `FR-1.5.1.1`).
///
/// One entry in the history `FR-1.5.1.4` keeps, not a mutable setting: a change appends a row, and
/// a lookup reads the latest row effective on or before the date it asks about.
///
/// **The number itself is not here.** A manual training max is a ``TrainingMaxHistoryEntry``, and
/// this record says only that the source *is* manual — a value stored beside the history is a value
/// that can disagree with it (`G-1.4`). ``configuration(manualWeight:)`` is handed the one in force.
///
/// **The remaining payload column is not paired with ``source`` by anything.** A `.percentOfRepMax`
/// entry with no ``sourceRepCount`` is representable and is what a defaulted foreign row looks like;
/// it is returned intact here and refuses when something asks to interpret it.
///
/// **``percentage`` and the two rounding properties are written whatever the source, and their
/// values disclose nothing.** A manual training max is the weight the user entered with neither
/// applied (`FR-1.5.1.5`), but they are the *dormant configuration* its one-tap "recalculate from
/// e1RM" resumes with, so they are not residue to be reset. Ask ``source``.
public struct TrainingMaxEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Exercise`` this configures.
    public let exerciseID: UUID

    /// Which of `FR-1.5.1.1`'s three sources the number comes from, and the only property that says
    /// which of the others took part in it.
    public let source: TrainingMaxSourceKind

    /// The N of a "% of best N-rep max" source, or `nil` for the other two. Within 1…10 when the
    /// source is `.percentOfRepMax`; unchecked here.
    public let sourceRepCount: Int?

    /// The fraction of the source weight to take, as a **ratio**: `0.9` is 90%, not `90`.
    ///
    /// Unvalidated, as the stored column is: `TrainingMaxConfiguration` rejects a non-positive or
    /// non-finite ratio, which is what makes a foreign row refuse to map rather than map wrongly.
    public let percentage: Double

    /// The loadable step the scaled weight is snapped to. At least one gram to map to a
    /// `RoundingRule`; unchecked here.
    public let roundingIncrement: Weight

    /// The direction half of the same rule.
    public let roundingStrategy: RoundingStrategy

    /// The step added on successful block completion (`FR-1.5.1.3`), or `nil` for no automatic
    /// progression. Negative is a configured deload rather than a mistake.
    ///
    /// **Not the rounding increment**, and mistaking the two inflates every training max by one
    /// step per read: this one is carried by a resolution and never applied by it.
    public let progressionIncrement: Weight?

    /// When this configuration takes effect.
    public let effectiveFrom: Date

    /// Creates a training-max history entry. No property is validated; see this type's note.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        exerciseID: UUID,
        source: TrainingMaxSourceKind,
        sourceRepCount: Int?,
        percentage: Double,
        roundingIncrement: Weight,
        roundingStrategy: RoundingStrategy,
        progressionIncrement: Weight?,
        effectiveFrom: Date
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exerciseID = exerciseID
        self.source = source
        self.sourceRepCount = sourceRepCount
        self.percentage = percentage
        self.roundingIncrement = roundingIncrement
        self.roundingStrategy = roundingStrategy
        self.progressionIncrement = progressionIncrement
        self.effectiveFrom = effectiveFrom
    }
}

// MARK: - Codable

extension TrainingMaxEntry {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case exerciseID
        case source
        case sourceRepCount
        case percentage
        case roundingIncrement
        case roundingStrategy
        case progressionIncrement
        case effectiveFrom
    }

    /// Decodes the keyed shape on ``CodingKeys``.
    ///
    /// ``source`` and ``roundingStrategy`` resolve rather than throw, and ``sourceRepCount`` is not
    /// checked against ``source`` — a `.percentOfRepMax` entry with none decodes, and refuses at
    /// ``TrainingMaxEntry/configuration(manualWeight:)``.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            source: try container.decodeVocabulary(
                TrainingMaxSourceKind.self, forKey: .source, or: RecordVocabulary.trainingMaxSource),
            sourceRepCount: try container.decodeIfPresent(Int.self, forKey: .sourceRepCount),
            percentage: try container.decode(Double.self, forKey: .percentage),
            roundingIncrement: try container.decode(Weight.self, forKey: .roundingIncrement),
            roundingStrategy: try container.decodeVocabulary(
                RoundingStrategy.self, forKey: .roundingStrategy, or: RecordVocabulary.roundingStrategy),
            progressionIncrement: try container.decodeIfPresent(Weight.self, forKey: .progressionIncrement),
            effectiveFrom: try container.decode(Date.self, forKey: .effectiveFrom)
        )
    }

    /// Writes the twelve keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encodeVocabulary(source, forKey: .source)
        try container.encodeIfPresent(sourceRepCount, forKey: .sourceRepCount)
        try container.encode(percentage, forKey: .percentage)
        try container.encode(roundingIncrement, forKey: .roundingIncrement)
        try container.encodeVocabulary(roundingStrategy, forKey: .roundingStrategy)
        try container.encodeIfPresent(progressionIncrement, forKey: .progressionIncrement)
        try container.encode(effectiveFrom, forKey: .effectiveFrom)
    }
}
