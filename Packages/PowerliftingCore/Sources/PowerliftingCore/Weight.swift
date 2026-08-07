/// A mass, stored as a whole number of grams.
///
/// `G-1.1` is why this type exists: grams are the only representation there is, so `Weight` is the
/// currency of every formula input and output here. Kilograms and pounds are *display* conversions
/// only (`G-3.1`, `G-3.2`) — never stored, and no API accepts one back without an explicit rounding
/// decision. 1 kg = 1000 g exactly; 1 lb = 453.59237 g exactly.
///
/// **Any `Int`, including negative.** `Weight` is signed because it doubles as a *delta* — an
/// increment, a deload, a target-versus-loaded gap. That a load is non-negative is a caller's
/// invariant, not this type's: rejecting negatives here would make subtraction partial and push
/// every difference through an optional. Arithmetic traps on overflow rather than wrapping.
///
/// Kilogram round-trips are lossless; pound round-trips lose at most half a gram per conversion.
public struct Weight: Sendable, Hashable, Comparable, Codable, AdditiveArithmetic, CustomStringConvertible {
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
    /// `rounding` has no default on purpose: `G-1.1` allows floating point at the boundary but
    /// never inside, so every crossing must name the rounding it wants. A silent default would make
    /// the lossy step invisible at the call site.
    ///
    /// - Parameters:
    ///   - kilograms: Any finite value whose gram equivalent fits in `Int`.
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
    /// See ``init(kilograms:rounding:)`` for why `rounding` is required. Pounds are lossy in a way
    /// kilograms are not: even a whole number of pounds is not a whole number of grams.
    ///
    /// - Parameters:
    ///   - pounds: Any finite value whose gram equivalent fits in `Int`.
    ///   - rounding: How to resolve the fractional gram a pound value almost always leaves.
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

    /// This mass multiplied by a dimensionless factor, rounded to the nearest whole gram.
    ///
    /// The one place a `Double` crosses back into grams — an e1RM multiplier, a percentage of a
    /// training max. Internal on purpose: a public version would invite scaling weights by
    /// floating-point factors at call sites with no business doing so (`G-1.1`).
    ///
    /// **Not configurable, and that is the point.** A whole gram is the *storage* resolution, not a
    /// display or loading choice, so there is nothing here for a caller to decide. Snapping to a
    /// weight a bar can hold is ``RoundingRule``'s, and it happens after this.
    ///
    /// - Returns: The scaled mass, or `nil` if the product is not finite or does not fit in `Int`
    ///   grams.
    func scaled(by factor: Double) -> Weight? {
        guard let scaled = RoundingStrategy.nearest.roundedToInt(Double(grams) * factor) else {
            return nil
        }
        return Weight(grams: scaled)
    }
}

// MARK: - Codable

extension Weight {
    /// Encodes as a bare integer of grams — `102500`, not `{"grams": 102500}`.
    ///
    /// Hand-written so the wire format is pinned rather than incidental. A single value on
    /// purpose: it nests inside composites without adding a wrapper object. Changing it is a
    /// storage migration.
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
    /// The fraction is **fixed** width, derived from `precision`: a 0.5 step always yields one
    /// decimal, so 102 000 g is `"102.0"`. Trimming trailing zeros is the UI layer's choice.
    ///
    /// Rounding to `precision` is always `.nearest`, ties away from zero, and is **display only** —
    /// the stored grams are untouched (`G-3.2`). Rounding to something a bar can hold is
    /// ``RoundingRule``'s question.
    ///
    /// Pounds round twice — grams to milli-pounds, then to `precision` — so a value within half a
    /// milli-pound of a tie can display one step off. Accepted; see `WeightDisplayRoundingTests`.
    ///
    /// - Parameter precision: The step to round to, in thousandths of `unit`.
    /// - Returns: A plain decimal string using `.` as the separator and `-` for negatives.
    public func formatted(in unit: MassUnit, precision: DisplayPrecision) -> String {
        let rounded = Self.rounded(
            milliUnits(in: unit), toMultipleOf: precision.milliUnits, strategy: .nearest)
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

    /// Rounds `value` to a multiple of `step` in the direction `strategy` names.
    ///
    /// Pure integer arithmetic, so the result is exact for every input. Unit-agnostic on purpose —
    /// the display path applies it to milli-pounds as well as grams. Stays internal so
    /// ``RoundingRule`` is the only public way to snap a `Weight` to a step.
    ///
    /// `.down` is floor and `.up` is ceiling — toward ±infinity, *not* toward and away from zero.
    /// Since `Weight` is signed, that distinction is real: `-7` rounded `.down` to a step of `5` is
    /// `-10`.
    ///
    /// - Precondition: `step > 0`. A negative step is rejected rather than normalised — the
    ///   multiples of `-5` are the multiples of `5`, so a sign carries no meaning and only buys
    ///   `Int.min` edge cases. Callers cannot violate this: `DisplayPrecision` and `RoundingRule`
    ///   both enforce it at their own initialisers.
    ///
    /// Near `Int.max`/`Int.min`, stepping away from the truncated multiple would leave `Int`, so
    /// that case stays on the truncated multiple: formatting an already-stored value must not
    /// trap.
    static func rounded(_ value: Int, toMultipleOf step: Int, strategy: RoundingStrategy) -> Int {
        // Deliberately without a message: the message is an autoclosure that only evaluates on
        // failure, which llvm-cov scores as an uncovered line forever. `file:line` already names
        // this function, and the doc comment above carries the explanation.
        precondition(step > 0)
        let remainder = value % step
        if remainder == 0 { return value }
        // `remainder` carries the sign of `value` and `|remainder| < step`, so this subtraction
        // moves toward zero and cannot overflow. It is the multiple on `value`'s own side of zero.
        let truncated = value - remainder
        switch strategy {
        case .down:
            // A positive `value` already sits above its truncated multiple; a negative one sits
            // below, and truncation moved it the wrong way.
            return remainder > 0 ? truncated : Self.stepping(truncated, by: -step)
        case .up:
            return remainder < 0 ? truncated : Self.stepping(truncated, by: step)
        case .nearest:
            // Doubling in `UInt` cannot overflow, since `|remainder| < step <= Int.max`.
            guard remainder.magnitude * 2 >= step.magnitude else { return truncated }
            return remainder < 0 ? Self.stepping(truncated, by: -step) : Self.stepping(truncated, by: step)
        }
    }

    /// `truncated + step`, falling back to `truncated` when that would leave `Int`.
    ///
    /// See the note on overflow in ``rounded(_:toMultipleOf:strategy:)``; the fallback always fits
    /// because `truncated` is bounded by the original value.
    private static func stepping(_ truncated: Int, by step: Int) -> Int {
        let (result, overflowed) = truncated.addingReportingOverflow(step)
        return overflowed ? truncated : result
    }

    /// Rounds to the nearest `Int`, clamping instead of failing.
    ///
    /// Pound display path only, and reachable only beyond 4.1 × 10¹⁸ grams. Formatting cannot
    /// report failure and must not trap on an already-stored value, so it clamps.
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
