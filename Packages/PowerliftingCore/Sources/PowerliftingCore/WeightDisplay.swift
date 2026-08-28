/// How a stored weight is rendered: the unit it is shown in (`G-3.1`) and the step it reads to
/// (`G-3.3`).
///
/// **The two travel together because neither answers on its own.** A precision of 500 milli-units
/// means half a *kilogram* or half a *pound* depending on the unit beside it, so a screen carrying
/// one and deriving the other shows half-pound steps to a lifter who configured half-kilogram ones
/// the moment they switch units.
///
/// Display and nothing else: storage stays grams (`G-1.1`) and moving either half never rewrites a
/// stored weight (`G-3.2`). It is **not** ``RoundingRule``, which decides what can be loaded on a
/// bar rather than what a number reads as — the two are separate settings and may disagree.
public struct WeightDisplay: Sendable, Hashable {
    /// The unit weights are shown in.
    public let unit: MassUnit

    /// The step displayed numbers are rounded to.
    public let precision: DisplayPrecision

    /// Creates a display pairing.
    ///
    /// - Parameters:
    ///   - unit: The display unit.
    ///   - precision: The display step.
    public init(unit: MassUnit, precision: DisplayPrecision) {
        self.unit = unit
        self.precision = precision
    }

    /// `unit` at `G-3.3`'s factory step for it — 0.5 kg, or 1 lb.
    ///
    /// - Parameter unit: The display unit.
    public init(unit: MassUnit) {
        self.init(unit: unit, precision: .default(for: unit))
    }

    /// `unit`, at `precision` where the user chose one and the factory step otherwise.
    ///
    /// - Parameters:
    ///   - unit: The display unit.
    ///   - precision: The configured step, or `nil` for the unit's own.
    public init(unit: MassUnit, resolving precision: DisplayPrecision?) {
        self.init(unit: unit, precision: precision ?? .default(for: unit))
    }

    /// Kilograms at half-kilogram steps: what a screen shows before it has read the user's row.
    public static let standard = WeightDisplay(unit: .kilograms)
}
