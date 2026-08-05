/// Which *kind* of bar an exercise uses.
///
/// Chosen when creating a custom exercise (`FR-1.1.3`), stored on `ExerciseEntity` (`TR-0.3.1`),
/// required on every catalogue entry (`TR-0.5.1`).
///
/// **This is a category, not a mass.** How much a bar weighs is the equipment profile's
/// `barWeightGrams` / `collarWeightGrams` (`FR-1.4.2`, `TR-0.3.7`), which `PlateCalculator`
/// (`TR-0.2.7`) takes as input. A bar type is a property of the **exercise** and the same
/// everywhere; a bar weight is a property of the **gym**, which is why the user has several
/// profiles (`FR-1.4.3`). A 20 kg men's bar and a 15 kg women's bar are both ``standard``.
/// **Never derive a bar weight from a case below** — read it from the profile.
///
/// Unknown values decode to ``other``.
public enum BarType: String, Sendable, Hashable, Codable, CaseIterable {
    /// A straight Olympic bar — the competition lifts. Covers every mass and stiffness variant
    /// (men's, women's, power, deadlift); those differ in `barWeightGrams`, not in category.
    case standard

    /// A cambered curl bar with angled grips — EZ bar.
    case ezCurl

    /// A hex or trap bar, loaded from inside the frame.
    case trap

    /// A safety squat bar — yoked, with forward-set handles.
    case safetySquat

    /// A cambered bar, whose sleeves hang below the shoulder line.
    case cambered

    /// A Swiss, football or multi-grip bar — neutral grips at several widths.
    case swiss

    /// The exercise uses no bar at all: dumbbell, machine, cable and bodyweight work.
    ///
    /// Named `noBar` rather than `none` on purpose: `BarType.none` collides with `Optional.none`
    /// wherever the contextual type is `BarType?`, and Swift resolves that in favour of `Optional`
    /// with a warning — a build failure in consuming code under warnings-as-errors (`G-6.4`).
    case noBar

    /// A specialty bar the cases above do not name — axle, log, buffalo — and the landing place
    /// for a bar type from a newer app version.
    case other
}

extension BarType {
    /// Decodes a bar type, degrading an unrecognised spelling to ``other`` instead of throwing —
    /// same policy as ``Movement/init(from:)``, and specialty bars are the most open-ended of these
    /// vocabularies. A non-string value still throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = BarType(rawValue: raw) ?? .other
    }
}
