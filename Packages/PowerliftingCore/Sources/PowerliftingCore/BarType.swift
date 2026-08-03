/// Which *kind* of bar an exercise uses.
///
/// Chosen when creating a custom exercise (`FR-1.1.3`), stored on `ExerciseEntity`
/// (`TR-0.3.1`), required on every catalogue entry (`TR-0.5.1`).
///
/// > No `TR-0.2.x` defines this type — logged as gap §2 of the Phase 0 coverage matrix. T-0.11
/// > invents it beside ``Movement`` because `TR-0.3.1` names the field and nothing else does.
///
/// **This is a category, not a mass, and the distinction is load-bearing.** How much a bar
/// weighs belongs to the equipment profile — `barWeightGrams` and `collarWeightGrams` on
/// `EquipmentProfileEntity` (`FR-1.4.2`, `TR-0.3.7`), which `PlateCalculator` (`TR-0.2.7`) takes
/// as input. The two are not two spellings of one idea:
///
/// - A bar type is a property of the **exercise** and is the same everywhere. A bar weight is a
///   property of the **gym**, and the user has several profiles (`FR-1.4.3`) precisely because it
///   differs between them.
/// - A 20 kg men's bar and a 15 kg women's bar are both ``standard``. They differ only in mass,
///   which is the profile's business. So are a power bar and a deadlift bar.
/// - Nothing here ever participates in weight arithmetic. Never derive a bar weight from a case
///   below; read it from the profile. (T-0.17 and T-0.32 both touch this boundary — this note is
///   the answer to the question they will each otherwise guess at.)
///
/// Renaming a case is a storage migration. Reordering them is free.
///
/// **Unknown values decode to ``other``** — see ``init(from:)``.
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
    /// Named `noBar` rather than `none` on purpose. `BarType.none` collides with `Optional.none`
    /// wherever the contextual type is `BarType?`, and Swift resolves that in favour of
    /// `Optional` with a warning — which, under warnings-as-errors
    /// (`scripts/swift-strict-flags.sh`, `G-6.4`), is a build failure in consuming code rather
    /// than a nuisance.
    case noBar

    /// A specialty bar the cases above do not name — axle, log, buffalo — and the landing place
    /// for a bar type from a newer app version. See ``init(from:)``.
    case other
}

extension BarType {
    /// Decodes a bar type, degrading an unrecognised spelling to ``other`` instead of throwing.
    ///
    /// Same policy and same trade-off as ``Movement/init(from:)``. Specialty bars are an
    /// open-ended and genuinely growing vocabulary, so this is the case where a newer catalogue
    /// meeting an older client is most likely — and losing the label must not cost the exercise.
    ///
    /// A non-string value still throws.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = BarType(rawValue: raw) ?? .other
    }
}
