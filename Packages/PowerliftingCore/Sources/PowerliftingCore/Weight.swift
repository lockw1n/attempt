/// A mass, stored as a whole number of grams.
///
/// `G-1.1` is the reason this type exists: no floating-point weight is ever persisted. The only
/// way to hold that line is to make grams the only representation there is, so `Weight` is the
/// currency of every formula input and output in this package. Kilograms and pounds exist here
/// solely as *display* conversions (`G-3.1`, `G-3.2`) — they return `Double`, they are never
/// stored, and no API accepts one back without an explicit rounding decision.
///
/// **Units.** ``grams`` is the storage. 1 kg = 1000 g exactly; 1 lb = 453.59237 g exactly.
///
/// **Valid range.** Any `Int`, including negative. `Weight` is signed because it doubles as a
/// *delta* — a progression increment, a deload, the gap between a target and what was loaded — and
/// those are genuinely negative. A weight that represents a load is expected to be non-negative,
/// but that is a caller's invariant, not this type's: rejecting negatives here would make
/// subtraction partial and push every difference through an optional. Practical loads sit under
/// 1 000 000 g (1000 kg). Arithmetic traps on `Int` overflow rather than wrapping.
///
/// **Precision.** Kilogram round-trips are lossless. Pound round-trips are lossy by at most half a
/// gram per conversion, because a pound is not a whole number of grams.
public struct Weight: Sendable, Hashable, Comparable, Codable, AdditiveArithmetic,
                      CustomStringConvertible {
    /// The mass in grams — the sole stored representation (`G-1.1`).
    public let grams: Int

    /// Creates a weight from a whole number of grams.
    ///
    /// - Parameter grams: Mass in grams. Any `Int`; see the type's note on negatives.
    public init(grams: Int) {
        self.grams = grams
    }

    /// A mass of zero grams. Also satisfies `AdditiveArithmetic`.
    public static let zero = Weight(grams: 0)
}

// MARK: - Conversion in (floating point → grams)

extension Weight {
    /// Creates a weight from a kilogram value, rounding to whole grams.
    ///
    /// The `rounding` argument has no default on purpose: `G-1.1` allows floating point at the
    /// boundary but never inside, so every crossing of that boundary must name the rounding it
    /// wants. A silent default would make the lossy step invisible at the call site.
    ///
    /// - Parameters:
    ///   - kilograms: Mass in kilograms. Any finite value whose gram equivalent fits in `Int`;
    ///     one kilogram is 1000 grams, so the fractional part is exact to three decimal places
    ///     before rounding applies.
    ///   - rounding: How to resolve a value that is not a whole number of grams.
    /// - Returns: `nil` if `kilograms` is NaN or infinite, or if the result overflows `Int`.
    public init?(kilograms: Double, rounding: RoundingStrategy) {
        guard let grams = rounding.roundedToInt(kilograms * MassUnit.kilograms.gramsPerUnit) else {
            return nil
        }
        self.init(grams: grams)
    }

    /// Creates a weight from a pound value, rounding to whole grams.
    ///
    /// See ``init(kilograms:rounding:)`` for why `rounding` is required. Note that pounds are
    /// lossy in a way kilograms are not: 1 lb is 453.59237 g, so even a whole number of pounds
    /// does not land on a whole number of grams.
    ///
    /// - Parameters:
    ///   - pounds: Mass in pounds. Any finite value whose gram equivalent fits in `Int`.
    ///   - rounding: How to resolve the fractional gram that a pound value almost always leaves.
    /// - Returns: `nil` if `pounds` is NaN or infinite, or if the result overflows `Int`.
    public init?(pounds: Double, rounding: RoundingStrategy) {
        guard let grams = rounding.roundedToInt(pounds * MassUnit.pounds.gramsPerUnit) else {
            return nil
        }
        self.init(grams: grams)
    }
}

// MARK: - Conversion out (grams → floating point, display only)

extension Weight {
    /// This mass in kilograms. Display only — never persist this value (`G-1.1`).
    ///
    /// Exact for every `Weight`: a gram is exactly one thousandth of a kilogram.
    public var kilograms: Double {
        Double(grams) / MassUnit.kilograms.gramsPerUnit
    }

    /// This mass in pounds. Display only — never persist this value (`G-1.1`).
    ///
    /// Inexact by up to half a gram (about 0.0011 lb), because a pound is not a whole number of
    /// grams. Converting to pounds and back with `.nearest` returns the original weight.
    public var pounds: Double {
        Double(grams) / MassUnit.pounds.gramsPerUnit
    }

    /// This mass expressed in `unit`. Display only — never persist this value (`G-1.1`).
    ///
    /// - Parameter unit: The unit to convert to.
    /// - Returns: The mass in `unit`. See ``kilograms`` and ``pounds`` for exactness.
    public func converted(to unit: MassUnit) -> Double {
        switch unit {
        case .kilograms: kilograms
        case .pounds: pounds
        }
    }
}

// MARK: - Comparison

extension Weight {
    /// Orders by stored grams. Total and exact — there is no floating point in the comparison.
    public static func < (lhs: Weight, rhs: Weight) -> Bool {
        lhs.grams < rhs.grams
    }
}

// MARK: - Arithmetic

extension Weight {
    /// Sum of two masses. Traps on `Int` overflow.
    public static func + (lhs: Weight, rhs: Weight) -> Weight {
        Weight(grams: lhs.grams + rhs.grams)
    }

    /// Difference of two masses. May be negative; see the type's note on negatives. Traps on
    /// `Int` overflow.
    public static func - (lhs: Weight, rhs: Weight) -> Weight {
        Weight(grams: lhs.grams - rhs.grams)
    }

    /// Negation — turns an increment into a decrement. Traps on `Int` overflow.
    public static prefix func - (operand: Weight) -> Weight {
        Weight(grams: -operand.grams)
    }

    /// A mass repeated a whole number of times — three plates, five sets. Traps on `Int` overflow.
    ///
    /// - Parameter rhs: Repeat count. Any `Int`; negative flips the sign.
    public static func * (lhs: Weight, rhs: Int) -> Weight {
        Weight(grams: lhs.grams * rhs)
    }

    /// A mass repeated a whole number of times. Commuted form of the operator above.
    public static func * (lhs: Int, rhs: Weight) -> Weight {
        Weight(grams: lhs * rhs.grams)
    }

    /// Scales in place by a whole number. Traps on `Int` overflow.
    public static func *= (lhs: inout Weight, rhs: Int) {
        lhs = lhs * rhs
    }
}

// MARK: - Codable

extension Weight {
    /// Encodes as a bare integer of grams — `102500`, not `{"grams": 102500}`.
    ///
    /// Hand-written rather than synthesised so the wire format is pinned rather than incidental.
    /// It is a single value on purpose: it nests inside `Prescription` and the DTO layer without
    /// adding a wrapper object, and it is the shape T-0.20's byte-stable round-trip is asserted
    /// against. Changing it is a storage migration.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(grams: try container.decode(Int.self))
    }

    /// Writes ``grams`` as a single integer value. See ``init(from:)`` for the format contract.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(grams)
    }
}

// MARK: - Description

extension Weight {
    /// Grams with a unit suffix — `"102500 g"`. Diagnostic output for tests and logs, not a
    /// display string: it is unlocalised and always in grams. Use ``formatted(in:precision:)``
    /// for anything a user sees.
    public var description: String {
        "\(grams) g"
    }
}

// MARK: - Display formatting

extension Weight {
    /// The mass rendered in `unit`, rounded to `precision` (`G-3.3`).
    ///
    /// Returns digits only — `"102.5"`, `"226"`, `"-2.5"` — with no unit name or symbol. Naming
    /// the unit is a localisation concern and localisation is Foundation, which this package may
    /// not import (`NFR-0.2`); the UI layer appends it.
    ///
    /// The fraction is rendered to a **fixed** number of digits, derived from `precision`: a
    /// 0.5 step always yields one decimal, so 102 000 g is `"102.0"` and not `"102"`. Fixed width
    /// keeps a column of weights aligned and keeps this function deterministic; trimming trailing
    /// zeros, if wanted, is a presentation choice for the UI layer.
    ///
    /// Rounding to `precision` is always `.nearest` with ties away from zero, and is **display
    /// only** — the stored grams are untouched (`G-3.2`). Rounding to something a bar can actually
    /// hold is a different question, answered by `RoundingRule` (T-0.13).
    ///
    /// **Pounds round twice, and very occasionally that shows.** Grams are converted to whole
    /// milli-pounds first, then rounded to `precision`, so a value sitting within half a
    /// milli-pound (about 0.23 mg) of an exact tie can be nudged across it and display one step
    /// away from what rounding the exact ratio in one operation would give. Measured: three gram
    /// values between 100 kg and 105 kg. It is accepted rather than fixed — at 0.23 mg from a tie
    /// either answer is defensible, and the alternative reintroduces floating point into the step
    /// rounding, which is the part `G-1.1` most wants kept integral. Kilograms are unaffected: one
    /// gram is exactly one milli-kilogram, so that path never converts at all.
    ///
    /// - Parameters:
    ///   - unit: The unit to render in.
    ///   - precision: The step to round to, in thousandths of `unit`.
    /// - Returns: A plain decimal string using `.` as the separator and `-` for negatives.
    public func formatted(in unit: MassUnit, precision: DisplayPrecision) -> String {
        let rounded = Self.rounded(milliUnits(in: unit), toMultipleOf: precision.milliUnits)
        return Self.decimalString(milliUnits: rounded, fractionDigits: precision.fractionDigits)
    }

    /// The mass rendered in `unit` at `G-3.3`'s default precision for that unit — 0.5 kg, or 1 lb.
    ///
    /// - Parameter unit: The unit to render in.
    /// - Returns: A plain decimal string; see ``formatted(in:precision:)``.
    public func formatted(in unit: MassUnit) -> String {
        formatted(in: unit, precision: .default(for: unit))
    }

    /// This mass in thousandths of `unit`, rounded to the nearest milli-unit.
    ///
    /// For `.kilograms` this is the stored grams unchanged — one gram is exactly one
    /// milli-kilogram — so kilogram formatting involves no floating point at all.
    func milliUnits(in unit: MassUnit) -> Int {
        switch unit {
        case .kilograms:
            grams
        case .pounds:
            Self.saturatingRoundToNearest(Double(grams) / unit.gramsPerMilliUnit)
        }
    }

    /// Rounds `value` to the nearest multiple of `step`, ties away from zero.
    ///
    /// Pure integer arithmetic — no `Double` anywhere, so the result is exact for every input.
    ///
    /// - Precondition: `step != 0`. `DisplayPrecision` guarantees `>= 1`, so no display path can
    ///   violate it. The check is here for T-0.13: `RoundingRule` is expected to reuse this
    ///   function, and a zero increment would otherwise surface as "Division by zero in remainder
    ///   operation" from inside the standard library, with nothing naming the caller. `RoundingRule`
    ///   should reject a zero increment at its own boundary, the way `DisplayPrecision` does.
    ///
    /// Rounding away from zero near `Int.max` would land outside `Int`, so that one case rounds
    /// toward zero instead. Like `saturatingRoundToNearest`, this is unreachable from any physical
    /// load and exists because formatting an already-stored value must not trap.
    static func rounded(_ value: Int, toMultipleOf step: Int) -> Int {
        // Deliberately without a message: the message is an autoclosure that only evaluates on
        // failure, which llvm-cov scores as an uncovered line forever. `file:line` already names
        // this function, and the doc comment above carries the explanation.
        precondition(step != 0)
        let remainder = value % step
        if remainder == 0 { return value }
        // `remainder` carries the sign of `value`, and `|remainder| < step`, so doubling it in
        // `UInt` cannot overflow.
        let roundsAway = remainder.magnitude * 2 >= step.magnitude
        let quotient = value / step
        guard roundsAway else { return quotient * step }
        let target = value < 0 ? quotient - 1 : quotient + 1
        let (product, overflowed) = target.multipliedReportingOverflow(by: step)
        // `quotient * step` is bounded by `value`, so the fallback always fits.
        return overflowed ? quotient * step : product
    }

    /// Rounds to the nearest `Int`, clamping instead of failing.
    ///
    /// Only used on the pound display path, and only reachable for masses beyond 4.1 × 10¹⁸ grams
    /// — four thousand trillion tonnes. Formatting has no way to report failure and must not trap
    /// on a value that is already stored, so it clamps; the alternative is a crash in a view.
    static func saturatingRoundToNearest(_ value: Double) -> Int {
        guard !value.isNaN else { return 0 }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        if let exact = Int(exactly: rounded) { return exact }
        return rounded < 0 ? Int.min : Int.max
    }

    /// Renders `milliUnits` as a decimal with exactly `fractionDigits` digits after the point.
    ///
    /// `fractionDigits` comes from `DisplayPrecision` and is chosen so that its scaling factor
    /// divides the step exactly, which is what makes the division below lossless rather than
    /// truncating. Works in `UInt` magnitude so that `Int.min` has no special case.
    static func decimalString(milliUnits: Int, fractionDigits: Int) -> String {
        let divisor: UInt
        let scale: UInt
        switch fractionDigits {
        case 0: (divisor, scale) = (1000, 1)
        case 1: (divisor, scale) = (100, 10)
        case 2: (divisor, scale) = (10, 100)
        default: (divisor, scale) = (1, 1000)
        }

        let scaled = milliUnits.magnitude / divisor
        let whole = scaled / scale
        let fraction = scaled % scale

        var result = milliUnits < 0 && scaled != 0 ? "-" : ""
        result += String(whole)
        if fractionDigits > 0 {
            var digits = String(fraction)
            while digits.count < fractionDigits {
                digits = "0" + digits
            }
            result += "." + digits
        }
        return result
    }
}
