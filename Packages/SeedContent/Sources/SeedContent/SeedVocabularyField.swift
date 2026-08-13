import PowerliftingCore

/// The four fields of ``SeedExercise`` whose values come from a closed vocabulary.
///
/// It exists so that every rule about vocabularies is written once and applied by walking
/// ``allCases``. A rule spelled out per field is how three of the four end up checked — and
/// `laterality` is the only one whose own `Decodable` throws, so a validator exercised on it alone
/// looks like it works.
public enum SeedVocabularyField: String, CaseIterable, Sendable {
    /// ``SeedExercise/movementRawValue``.
    case movement

    /// ``SeedExercise/equipmentRawValue``.
    case equipment

    /// ``SeedExercise/lateralityRawValue``.
    case laterality

    /// ``SeedExercise/barTypeRawValue``.
    case barType

    /// Every spelling this field accepts, derived from the domain type rather than listed.
    ///
    /// The validator's failure message quotes it, which is the only reason it is public: an author
    /// hand-writing JSON needs the list, and any copy of it written down would rot.
    public var acceptedValues: [String] {
        switch self {
        case .movement: Movement.allCases.map(\.rawValue)
        case .equipment: Equipment.allCases.map(\.rawValue)
        case .laterality: Laterality.allCases.map(\.rawValue)
        case .barType: BarType.allCases.map(\.rawValue)
        }
    }

    /// Whether the domain type recognises `rawValue`.
    ///
    /// `init?(rawValue:)` rather than a decode, and never a membership test against
    /// ``acceptedValues`` — the point is that the type answers.
    public func accepts(_ rawValue: String) -> Bool {
        switch self {
        case .movement: Movement(rawValue: rawValue) != nil
        case .equipment: Equipment(rawValue: rawValue) != nil
        case .laterality: Laterality(rawValue: rawValue) != nil
        case .barType: BarType(rawValue: rawValue) != nil
        }
    }
}
