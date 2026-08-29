import Foundation
import PowerliftingCore

/// Renders a ``PowerliftingCore/Weight`` in a display unit, for one locale — `"102.5 kg"`,
/// `"102,5 kg"`, `"225 lb"`.
///
/// **The number is the domain's and the glyphs are ICU's**, and the split is deliberate. `Weight`
/// `.formatted(in:precision:)` decides the value and how wide it is — `G-3.3`'s step, applied in
/// exact integer arithmetic, with the pound double-rounding it documents — and this style renders
/// that same value with the locale's separator and unit symbol. Rounding is not repeated here; a
/// second implementation of the step would disagree with the first at the ties.
///
/// The unit symbol is ICU's abbreviated form. `MeasurementFormatter`'s medium style is not an
/// alternative: it renders `UnitMass.pounds` as "pounds".
public struct WeightStyle: FormatStyle {
    /// The unit the mass is shown in (`G-3.1`). Storage is always grams.
    public let unit: MassUnit

    /// The step the displayed number is rounded to (`G-3.3`).
    public let precision: DisplayPrecision

    /// The locale supplying the decimal separator and the unit symbol.
    public var locale: Locale

    /// Builds a style. Prefer ``AppFormat/weight(in:precision:locale:)``.
    ///
    /// - Parameters:
    ///   - unit: The display unit.
    ///   - precision: The display step.
    ///   - locale: The locale to render for; in a view, `@Environment(\.locale)`.
    public init(unit: MassUnit, precision: DisplayPrecision, locale: Locale) {
        self.unit = unit
        self.precision = precision
        self.locale = locale
    }

    /// The mass as a localised number with its unit symbol.
    ///
    /// - Parameter value: The mass to render.
    /// - Returns: The rendered string.
    public func format(_ value: Weight) -> String {
        let digits = value.formatted(in: unit, precision: precision)
        // Unreachable in practice — the domain documents this string as a plain decimal — and the
        // fallback degrades to an unrounded magnitude rather than to a wrong one.
        let magnitude = Double(digits) ?? value.converted(to: unit)
        return Measurement(value: magnitude, unit: unit.foundationUnit)
            .formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(
                        .fractionLength(Self.fractionDigits(of: digits)))
                )
                .locale(locale))
    }

    /// This style, rendering for `locale` instead.
    ///
    /// - Parameter locale: The locale to render for.
    /// - Returns: A copy bound to `locale`.
    public func locale(_ locale: Locale) -> WeightStyle {
        WeightStyle(unit: unit, precision: precision, locale: locale)
    }

    /// How wide the fraction is, read off the domain's own output rather than re-derived from the
    /// step — the two cannot then disagree, and the derivation has one home.
    private static func fractionDigits(of digits: String) -> Int {
        guard let separator = digits.firstIndex(of: ".") else { return 0 }
        return digits.distance(from: digits.index(after: separator), to: digits.endIndex)
    }
}

extension MassUnit {
    /// The Foundation unit this maps to, for anything that has to reach ICU.
    ///
    /// Here rather than in the domain: `PowerliftingCore` imports nothing (`NFR-0.2`).
    var foundationUnit: UnitMass {
        switch self {
        case .kilograms: .kilograms
        case .pounds: .pounds
        }
    }
}

extension Weight {
    /// This mass, rendered by `style`.
    ///
    /// - Parameter style: The style to render with; build it from ``Localization/AppFormat``.
    /// - Returns: The rendered string.
    public func formatted(_ style: WeightStyle) -> String {
        style.format(self)
    }
}
