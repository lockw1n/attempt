/// Which way to break a value that does not land exactly on the target resolution.
///
/// This is the *direction* half of rounding, deliberately separated from what is being rounded to.
/// It is shared vocabulary, used in three distinct places that must not be conflated:
///
/// - converting a floating-point kg/lb entry into `Int` grams (`Weight.init(kilograms:rounding:)`),
/// - rounding a weight to a loadable increment (`RoundingRule`, T-0.13),
/// - rounding a weight to a display precision (`DisplayPrecision`, which always uses `.nearest`).
///
/// Sharing the enum is not the same as sharing an API: `RoundingRule` stays a separate type with
/// its own increment, because "what can be loaded on a bar" and "what is shown on screen" are
/// different questions with different answers.
///
/// The raw values are a persisted spelling (`RoundingRule` is `Codable`), so renaming a case is a
/// storage migration, not a refactor.
public enum RoundingStrategy: String, Sendable, Hashable, Codable, CaseIterable {
    /// To the closer of the two candidates. Exact ties go **away from zero**: `+0.5 → +1`,
    /// `-0.5 → -1`. Chosen over banker's rounding because a lifter reading 102.5 kg rounded to a
    /// 5 kg increment expects 105, not 100.
    case nearest

    /// Toward negative infinity (floor). For the positive weights that dominate real use this is
    /// "lighter"; for a negative delta it is "more negative", not "smaller in magnitude".
    case down

    /// Toward positive infinity (ceiling). Mirror of `.down`.
    case up
}

extension RoundingStrategy {
    /// Applies this strategy to `value`, producing a whole number.
    ///
    /// Returns `nil` when `value` is not finite (NaN or ±infinity) or when the rounded result
    /// falls outside `Int`. Both are caller errors rather than domain states, which is why the
    /// public initialisers that use this are failable rather than trapping — a weight parsed from
    /// a text field must be rejectable, not fatal.
    func roundedToInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        let rounded: Double =
            switch self {
            case .nearest: value.rounded(.toNearestOrAwayFromZero)
            case .down: value.rounded(.down)
            case .up: value.rounded(.up)
            }
        return Int(exactly: rounded)
    }
}
