import PowerliftingCore

/// What an unreadable vocabulary spelling becomes — the whole of rule 4 in this module's header, as
/// eleven columns' worth of constants and the one function that applies them.
///
/// **This is the second home of these values and the duplication is deliberate.** `Persistence`'s
/// `SchemaDefaults` holds what an *absent* column contains; this holds what an *unreadable* value
/// resolves to. They coincide by argument rather than by identity — the arguments are recorded once,
/// against the schema defaults, and are not restated here — so each may be changed without the
/// other. `Persistence` asserts the coincidence rather than sharing the constants, which is what
/// makes a divergence a decision somebody has to write down.
///
/// **Both the stored mapping and ``Codable`` read these**, so a row that arrives from a newer
/// version through the store and the same row arriving through a backup file resolve identically.
/// A second copy in either path is how those two drift.
///
/// **Three of the ten already degrade on their own, and they still route through here.** `Movement`,
/// `Equipment` and `BarType` each hand-write a lenient `init(from:)` in `PowerliftingCore`, decided
/// for the seed catalogue rather than for storage — so decoding those three through the plain
/// `Codable` conformance would give the same answer today. Going through this table anyway is what
/// keeps all ten resolving in one place and makes a divergence between the two policies visible;
/// `RecordVocabularyAgreementTests` is what would notice one.
///
/// **Nothing here preserves the original spelling.** A restore into an empty store therefore writes
/// the fallback, not what it read — see ``Exercise`` for why that is acceptable for the four
/// catalogue vocabularies and why `SetEntry/modifiers` is the exception that is not routed through
/// this type at all.
public enum RecordVocabulary {
    /// One vocabulary's fallback, and whether that fallback claims anything.
    ///
    /// **``isUnknownMarker`` exists because a write path needs it, and getting it wrong is a
    /// user-visible bug rather than a nicety.** Only three of the ten fallbacks are cases meaning
    /// *"this version does not recognise the stored spelling"*; the other seven are ordinary answers
    /// a user can also pick deliberately. A mapping that treats the two alike cannot tell "the
    /// caller left this column alone" from "the caller chose this value", and so makes the value
    /// unreachable — see `Persistence`'s `preservingRawValue(_:stored:fallback:)`, which is the only
    /// thing that reads this flag.
    public struct Fallback<T>: Sendable where T: RawRepresentable & Equatable & Sendable, T.RawValue == String {
        /// The value an unrecognised spelling resolves to.
        public let value: T

        /// Whether ``value`` is a case that claims nothing — `Movement.other` and its two siblings —
        /// rather than a real answer a user could also have chosen.
        public let isUnknownMarker: Bool

        /// Private so the ten constants below are the only instances: a vocabulary's fallback is a
        /// decision with an argument behind it, not something a call site supplies.
        fileprivate init(_ value: T, isUnknownMarker: Bool) {
            self.value = value
            self.isUnknownMarker = isUnknownMarker
        }
    }

    /// An unreadable `Movement`.
    public static let movement = Fallback(Movement.other, isUnknownMarker: true)

    /// An unreadable `Equipment`.
    public static let equipment = Fallback(Equipment.other, isUnknownMarker: true)

    /// An unreadable `Laterality`.
    ///
    /// The type has no unknown case, so this is a real answer rather than a marker — a user can pick
    /// bilateral, and their pick has to win over a spelling this version cannot read.
    public static let laterality = Fallback(Laterality.bilateral, isUnknownMarker: false)

    /// An unreadable `BarType`.
    public static let barType = Fallback(BarType.other, isUnknownMarker: true)

    /// An unreadable ``BodyweightSource``.
    public static let bodyweightSource = Fallback(BodyweightSource.manual, isUnknownMarker: false)

    /// An unreadable ``TrainingMaxSourceKind``.
    public static let trainingMaxSource = Fallback(TrainingMaxSourceKind.manual, isUnknownMarker: false)

    /// An unreadable `RoundingStrategy`, on either of the two columns that carry one.
    public static let roundingStrategy = Fallback(RoundingStrategy.nearest, isUnknownMarker: false)

    /// An unreadable `MassUnit`.
    public static let displayUnit = Fallback(MassUnit.kilograms, isUnknownMarker: false)

    /// An unreadable `E1RMFormulaID`.
    public static let e1RMFormula = Fallback(E1RMFormulaID.defaultFormula, isUnknownMarker: false)

    /// An unreadable ``ThemePreference``.
    ///
    /// `.system` expresses no preference but is still one of the three a user picks, so it is not a
    /// marker: a user choosing "System" has to be able to make that stick.
    public static let theme = Fallback(ThemePreference.system, isUnknownMarker: false)

    /// `raw` as a `T`, or the fallback's value when this version does not recognise the spelling.
    ///
    /// Total on purpose: it is the reason no read in this module can fail on a vocabulary column,
    /// and it is written once so that a tenth vocabulary cannot acquire a tenth policy.
    ///
    /// - Parameters:
    ///   - raw: The stored or decoded spelling. Any string, including one no version has used.
    ///   - fallback: The constant from this type belonging to `T`.
    /// - Returns: The recognised value, or `fallback.value`.
    public static func resolve<T>(_ raw: String, or fallback: Fallback<T>) -> T {
        T(rawValue: raw) ?? fallback.value
    }
}
