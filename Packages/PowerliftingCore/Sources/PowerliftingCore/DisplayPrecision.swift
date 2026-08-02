/// The step a weight is rounded to *for display* (`G-3.3`).
///
/// Held as an integer number of **thousandths of the display unit** ("milli-units") rather than as
/// a `Double`, so that formatting is exact integer arithmetic end to end. 0.5 kg is `500`,
/// 1.25 kg is `1250`, 1 lb is `1000`, 0.1 lb is `100`.
///
/// Deliberately unit-agnostic: the same value means 0.5 kg when displaying kilograms and 0.5 lb
/// when displaying pounds. The unit is supplied at the call site
/// (``Weight/formatted(in:precision:)``) because display unit and display precision are two
/// separate user preferences (`G-3.1`, `G-3.3`).
///
/// This is **not** `RoundingRule` (T-0.13). This one decides what a number looks like on screen;
/// that one decides what can actually be loaded on a bar. A weight displayed as "102.5" may well
/// be 102 483 g in storage — display rounding never touches stored data (`G-3.2`).
///
/// Valid range: strictly positive. A step of zero or less has no meaning and is rejected at every
/// entry point, including decoding.
public struct DisplayPrecision: Sendable, Hashable, Codable {
    /// The step, in thousandths of the display unit. Always `>= 1`.
    public let milliUnits: Int

    /// Creates a precision from a step in thousandths of the display unit.
    ///
    /// - Parameter milliUnits: Step size, in thousandths of a unit. Must be `>= 1`; 500 means
    ///   half a unit, 1000 means one whole unit.
    /// - Returns: `nil` if `milliUnits` is zero or negative.
    public init?(milliUnits: Int) {
        guard milliUnits >= 1 else { return nil }
        self.milliUnits = milliUnits
    }

    /// Non-failable path for the statics below, whose arguments are literals checked by eye.
    private init(checked milliUnits: Int) {
        self.milliUnits = milliUnits
    }

    /// 0.5 of a unit — `G-3.3`'s default for kilograms.
    public static let half = DisplayPrecision(checked: 500)

    /// A whole unit — `G-3.3`'s default for pounds.
    public static let whole = DisplayPrecision(checked: 1000)

    /// 0.25 of a unit. The finest step that matches a common plate pair (1.25 kg per side).
    public static let quarter = DisplayPrecision(checked: 250)

    /// 0.1 of a unit.
    public static let tenth = DisplayPrecision(checked: 100)

    /// `G-3.3`'s default precision for a unit: 0.5 kg, or 1 lb.
    ///
    /// This is the factory default, not the user's setting — a user preference overrides it and
    /// is not modelled in this package.
    public static func `default`(for unit: MassUnit) -> DisplayPrecision {
        switch unit {
        case .kilograms: .half
        case .pounds: .whole
        }
    }
}

extension DisplayPrecision {
    /// How many digits after the decimal point this step needs in order to be representable.
    ///
    /// 1000 → 0 ("226"), 500 → 1 ("102.5"), 250 → 2 ("101.25"), 1 → 3. Derived rather than stored
    /// so that the two can never disagree, and chosen so that the step always divides the scaling
    /// factor exactly — which is what makes the rendering in `Weight.formatted` lossless.
    var fractionDigits: Int {
        let remainder = milliUnits % 1000
        if remainder == 0 { return 0 }
        if remainder % 100 == 0 { return 1 }
        if remainder % 10 == 0 { return 2 }
        return 3
    }
}

extension DisplayPrecision {
    /// Encodes as a bare integer of milli-units, not as an object.
    ///
    /// Hand-written rather than synthesised for two reasons: the wire format stays a single
    /// number (a preference, not a record), and the `milliUnits >= 1` invariant is enforced on the
    /// way in. Synthesised `Decodable` bypasses `init?(milliUnits:)` entirely and would happily
    /// produce a zero-step precision that divides by zero downstream.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(Int.self)
        guard let precision = DisplayPrecision(milliUnits: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "DisplayPrecision must be at least 1 milli-unit, got \(value)."
            )
        }
        self = precision
    }

    /// Writes ``milliUnits`` as a single integer value. See ``init(from:)`` for the format
    /// contract and the invariant decoding re-checks.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(milliUnits)
    }
}
