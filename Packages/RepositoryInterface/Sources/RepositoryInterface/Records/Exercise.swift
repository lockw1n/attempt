import Foundation
import PowerliftingCore

/// A movement the user can log against — seeded from the catalogue or authored by them
/// (`TR-0.3.1`).
///
/// The four vocabulary properties are already mapped: a stored spelling this version cannot read
/// has resolved to its fallback before a caller sees it, and never cost the row. **The original
/// spelling is not preserved**, unlike ``SetEntry/modifiers`` — a seed re-import re-supplies these
/// four (`TR-0.5.1`) and nothing re-supplies a modifier the user typed.
public struct Exercise: StoredRecord {
    /// Permanent once written: a seeded id lands in users' logged history, so regenerating one
    /// orphans every set logged against it.
    public let id: UUID

    /// See ``StoredRecord/createdAt``.
    public let createdAt: Date

    /// See ``StoredRecord/updatedAt``.
    public let updatedAt: Date

    /// See ``StoredRecord/deletedAt``.
    public let deletedAt: Date?

    /// The user-facing name. Renaming a built-in exercise does not break history (`FR-1.1.4`).
    public let name: String

    /// Which lift this is a form of.
    public let movement: Movement

    /// The exercise this one varies (`FR-1.1.7`), or `nil` for a root exercise.
    public let parentExerciseID: UUID?

    /// What it is performed with.
    public let equipment: Equipment

    /// Whether a rep loads both sides at once.
    public let laterality: Laterality

    /// The bar's *category*. Its mass belongs to the gym and lives on ``EquipmentProfile``.
    public let barType: BarType

    /// How many implements one rep loads at once, at least 1: a barbell, a machine and a goblet
    /// squat are all 1, a dumbbell pair is 2.
    ///
    /// The factor `FR-1.5.1`'s tonnage needs and that neither ``equipment`` nor ``laterality``
    /// supplies. **Unchecked here**: a stored zero arrives as a zero, because refusing it would
    /// cost the exercise for a field that only makes a volume number wrong. `ExerciseEntity` names
    /// the seed validator and this layer's mapping as where a zero is caught, and catching it is
    /// the mapping's rather than this property's.
    public let implementCount: Int

    /// Whether the user authored this exercise (`FR-1.1.3`) rather than the seed catalogue. It
    /// decides whether a re-import may overwrite the row.
    public let isCustom: Bool

    /// Hidden from pickers, still present in logged history (`FR-1.1.5`). Distinct from
    /// ``deletedAt``: `FR-1.1.5` forbids hard-deleting an exercise with logged sets, so archiving
    /// is how an exercise leaves the picker.
    public let isArchived: Bool

    /// Free-text notes (`FR-1.1.6`).
    public let notes: String

    /// Creates an exercise record. No property is validated; see this module's header.
    public init(
        id: UUID,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        name: String,
        movement: Movement,
        parentExerciseID: UUID?,
        equipment: Equipment,
        laterality: Laterality,
        barType: BarType,
        implementCount: Int,
        isCustom: Bool,
        isArchived: Bool,
        notes: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.name = name
        self.movement = movement
        self.parentExerciseID = parentExerciseID
        self.equipment = equipment
        self.laterality = laterality
        self.barType = barType
        self.implementCount = implementCount
        self.isCustom = isCustom
        self.isArchived = isArchived
        self.notes = notes
    }
}

// MARK: - Codable

extension Exercise {
    /// The wire format's keys, in the order they are written. See `RecordCoding.swift`.
    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case deletedAt
        case name
        case movement
        case parentExerciseID
        case equipment
        case laterality
        case barType
        case implementCount
        case isCustom
        case isArchived
        case notes
    }

    /// Decodes the keyed shape on ``CodingKeys``.
    ///
    /// All four vocabularies resolve rather than throw, ``laterality`` included — the domain type
    /// throws on an unrecognised spelling, and letting that reach here would cost the exercise, and
    /// with it every set logged against the row.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            deletedAt: try container.decodeIfPresent(Date.self, forKey: .deletedAt),
            name: try container.decode(String.self, forKey: .name),
            movement: try container.decodeVocabulary(
                Movement.self, forKey: .movement, or: RecordVocabulary.movement),
            parentExerciseID: try container.decodeIfPresent(UUID.self, forKey: .parentExerciseID),
            equipment: try container.decodeVocabulary(
                Equipment.self, forKey: .equipment, or: RecordVocabulary.equipment),
            laterality: try container.decodeVocabulary(
                Laterality.self, forKey: .laterality, or: RecordVocabulary.laterality),
            barType: try container.decodeVocabulary(
                BarType.self, forKey: .barType, or: RecordVocabulary.barType),
            implementCount: try container.decode(Int.self, forKey: .implementCount),
            isCustom: try container.decode(Bool.self, forKey: .isCustom),
            isArchived: try container.decode(Bool.self, forKey: .isArchived),
            notes: try container.decode(String.self, forKey: .notes)
        )
    }

    /// Writes the fourteen keys in declaration order.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encode(name, forKey: .name)
        try container.encodeVocabulary(movement, forKey: .movement)
        try container.encodeIfPresent(parentExerciseID, forKey: .parentExerciseID)
        try container.encodeVocabulary(equipment, forKey: .equipment)
        try container.encodeVocabulary(laterality, forKey: .laterality)
        try container.encodeVocabulary(barType, forKey: .barType)
        try container.encode(implementCount, forKey: .implementCount)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(notes, forKey: .notes)
    }
}
