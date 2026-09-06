import Foundation
import PowerliftingCore

/// One change to an exercise's training max — the history `FR-15.1.4` keeps and `FR-16.7.2` writes.
///
/// **This is where the number lives, and it is the only place it lives.** ``TrainingMaxEntry`` says
/// how a training max is *derived*; this says what it *was*, from a date. A configuration carrying a
/// second copy of the value would be a copy that can disagree with the history, which `G-1.4` is
/// about — so the manual weight is a row here rather than a column there, and
/// `TrainingMaxEntry.configuration(manualWeight:)` is handed the value in force rather than holding
/// one.
///
/// **``oldWeight`` is not derivable from the row before it.** The preceding row is the one this
/// entry superseded *in this store*; a restored file, a soft-deleted row, or two entries sharing an
/// effective date all make "the previous row" a lookup with more than one answer, where
/// `FR-15.1.4`'s "old value" is a fact the change itself knew. It is `nil` on the first entry for an
/// exercise, which is a different statement from a change from zero.
///
/// **``reason`` is free text and is never a vocabulary.** `FR-16.7.2` names `coach` as the case that
/// prompted it, not as an enumeration to hold — a lifter annotating a change with why it happened is
/// writing prose, and a closed set would either refuse their sentence or silently file it under
/// *other*.
public struct TrainingMaxHistoryEntry: StoredRecord {
    /// See ``StoredRecord/id``.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The ``Exercise`` whose training max changed.
    public let exerciseID: UUID

    /// When this value takes effect — the day the number applies from, not the day it was typed.
    ///
    /// The author's plan file announces a training max per week, so this is that week's start.
    public let effectiveFrom: Date

    /// What the training max was before this change, or `nil` where there was none.
    public let oldWeight: Weight?

    /// What it becomes. Unvalidated, as the stored column is; `Weight` is signed on purpose and
    /// nothing here refuses a value the store already holds.
    public let newWeight: Weight

    /// Why it changed — `coach`, or whatever the lifter wrote. Empty where they wrote nothing.
    public let reason: String

    /// Creates a training-max history entry. No property is validated; see this type's note.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        exerciseID: UUID,
        effectiveFrom: Date,
        oldWeight: Weight?,
        newWeight: Weight,
        reason: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.exerciseID = exerciseID
        self.effectiveFrom = effectiveFrom
        self.oldWeight = oldWeight
        self.newWeight = newWeight
        self.reason = reason
    }
}

// MARK: - Codable

extension TrainingMaxHistoryEntry {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case exerciseID
        case effectiveFrom
        case oldWeight
        case newWeight
        case reason
    }

    /// Decodes the keyed shape on ``CodingKeys``.
    ///
    /// Nothing here resolves or repairs: there is no vocabulary column on this record, so rule 5
    /// applies to every key that is not ``oldWeight``, which is rule 3's omitted optional.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            exerciseID: try container.decode(UUID.self, forKey: .exerciseID),
            effectiveFrom: try container.decode(Date.self, forKey: .effectiveFrom),
            oldWeight: try container.decodeIfPresent(Weight.self, forKey: .oldWeight),
            newWeight: try container.decode(Weight.self, forKey: .newWeight),
            reason: try container.decode(String.self, forKey: .reason)
        )
    }

    /// Writes the nine keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(exerciseID, forKey: .exerciseID)
        try container.encode(effectiveFrom, forKey: .effectiveFrom)
        try container.encodeIfPresent(oldWeight, forKey: .oldWeight)
        try container.encode(newWeight, forKey: .newWeight)
        try container.encode(reason, forKey: .reason)
    }
}
