import Foundation
import PowerliftingCore

/// One authored catalogue entry (`TR-0.5.1`).
///
/// The four vocabulary properties are the **raw spellings the file carries**, not resolved values —
/// see this module's header for why resolving them on decode would defeat the validator. The
/// `…RawValue` naming matches the stored entity's, so the two cannot be confused at a call site.
///
/// **Permanent once published:** ``id`` lands in users' logged history, so regenerating one orphans
/// every set logged against it.
public struct SeedExercise: Decodable, Equatable, Sendable {
    /// The exercise's stable identity.
    public let id: UUID

    /// The user-facing name. Renaming a built-in exercise does not break history (`FR-1.1.4`).
    public let name: String

    /// The Ukrainian name (`FR-1.14.2`), or absent for an entry the catalogue has not translated.
    ///
    /// Optional so a partly-translated catalogue is a shippable one: an entry with no Ukrainian name
    /// shows its English one, which is the same answer a store row with nothing in the column gives.
    public let ukrainianName: String?

    /// ``PowerliftingCore/Movement``'s raw value.
    public let movementRawValue: String

    /// The exercise this one varies (`FR-1.1.7`), or absent for a root exercise.
    public let parentExerciseID: UUID?

    /// ``PowerliftingCore/Equipment``'s raw value.
    public let equipmentRawValue: String

    /// ``PowerliftingCore/Laterality``'s raw value.
    public let lateralityRawValue: String

    /// ``PowerliftingCore/BarType``'s raw value. Required in the payload: an absent value would
    /// resolve to a category the author did not choose, and `noBar` is a real answer rather than a
    /// missing one.
    public let barTypeRawValue: String

    /// How many implements one rep loads at once, or absent for one — a barbell, a machine and a
    /// goblet squat all load one, a dumbbell pair loads two.
    ///
    /// Optional so that only the multi-implement entries have to say anything. The absent case is
    /// ``implements``.
    public let implementCount: Int?

    /// ``implementCount`` with the payload's implied value applied: one implement.
    public var implements: Int { implementCount ?? 1 }

    /// The raw spelling of one vocabulary field, for a caller walking
    /// ``SeedVocabularyField``'s `allCases`.
    public func rawValue(for field: SeedVocabularyField) -> String {
        switch field {
        case .movement: movementRawValue
        case .equipment: equipmentRawValue
        case .laterality: lateralityRawValue
        case .barType: barTypeRawValue
        }
    }

    /// The wire format's keys. The vocabulary keys are the bare field names; the `…RawValue`
    /// suffixes are a Swift-side distinction and must never reach the file.
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case ukrainianName
        case movementRawValue = "movement"
        case parentExerciseID
        case equipmentRawValue = "equipment"
        case lateralityRawValue = "laterality"
        case barTypeRawValue = "barType"
        case implementCount
    }

    /// Decodes one entry, refusing a key this version does not recognise.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.rejectUnrecognisedFields(from: decoder)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ukrainianName = try container.decodeIfPresent(String.self, forKey: .ukrainianName)
        movementRawValue = try container.decode(String.self, forKey: .movementRawValue)
        parentExerciseID = try container.decodeIfPresent(UUID.self, forKey: .parentExerciseID)
        equipmentRawValue = try container.decode(String.self, forKey: .equipmentRawValue)
        lateralityRawValue = try container.decode(String.self, forKey: .lateralityRawValue)
        barTypeRawValue = try container.decode(String.self, forKey: .barTypeRawValue)
        implementCount = try container.decodeIfPresent(Int.self, forKey: .implementCount)
    }
}
