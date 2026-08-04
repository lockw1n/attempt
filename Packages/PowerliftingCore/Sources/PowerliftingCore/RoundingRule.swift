/// The step a weight is snapped to *for loading*, plus the direction to snap in (`TR-0.2.6`).
///
/// This is the barbell question, not the screen question: a gym with 1.25 kg plates can load
/// 2.5 kg steps, so a 102 483 g target becomes 102 500 g on the bar. `DisplayPrecision` (T-0.10)
/// answers the other one — what a number *looks* like — and the two are deliberately separate
/// types. A weight can be displayed as "102.5" and loaded as 105 000 g under a 5 kg rule; neither
/// value is wrong, because they answer different questions.
///
/// The direction vocabulary *is* shared: ``RoundingStrategy`` is the same enum the floating-point
/// entry points use. Sharing it is not a merge of the two concerns — direction means the same
/// thing everywhere, while the thing being rounded to does not.
///
/// **`.down` is floor and `.up` is ceiling**, toward negative and positive infinity rather than
/// toward and away from zero. `Weight` is signed because it doubles as a delta, so this matters:
/// a -7 g target under a 5 g rule rounds `.down` to -10 g, not -5 g. For the non-negative loads
/// that dominate real use, `.down` reads as "lighter" and `.up` as "heavier", which is what a
/// deload or a conservative jump wants.
///
/// **Ties go away from zero** under `.nearest` — 102.5 kg to a 5 kg increment is 105 kg, not 100.
/// That rule lives on ``RoundingStrategy/nearest`` and is shared with every other rounding path in
/// the module.
///
/// **Valid increment: at least one gram.** Zero has no meaning (every weight is a multiple of it)
/// and negative has none either (the multiples of -2500 g are exactly the multiples of 2500 g), so
/// both are rejected at every entry point, including decoding.
public struct RoundingRule: Sendable, Hashable, Codable {
    /// The loadable step. Always at least one gram.
    ///
    /// A `Weight` rather than a bare `Int` of grams even though `TR-0.2.6` says "increment
    /// (grams)": an increment *is* a mass — the smallest plate pair a gym owns — and it is
    /// compared with, subtracted from and added to weights downstream. `Weight` is already grams
    /// and nothing else (`G-1.1`), so the requirement is met either way; what the `Int` spelling
    /// would cost is a call site converting 2.5 kg to grams by hand, which is exactly the raw-gram
    /// arithmetic `Weight` exists to keep out of the rest of the module.
    public let increment: Weight

    /// Which way to break a target that does not land on ``increment``.
    public let strategy: RoundingStrategy

    /// Creates a rounding rule.
    ///
    /// - Parameters:
    ///   - increment: The loadable step. Must be at least one gram; 2500 g is a 2.5 kg step.
    ///   - strategy: The direction to snap in.
    /// - Returns: `nil` if `increment` is zero or negative.
    public init?(increment: Weight, strategy: RoundingStrategy) {
        guard increment.grams >= 1 else { return nil }
        self.increment = increment
        self.strategy = strategy
    }

    /// `weight` snapped to the nearest multiple of ``increment`` in ``strategy``'s direction.
    ///
    /// Exact integer arithmetic throughout — no floating point, no locale, no `Foundation`
    /// (`NFR-0.2`). A weight that is already an exact multiple is returned unchanged by all three
    /// strategies.
    ///
    /// - Parameter weight: The target weight. May be negative; see the type's note on direction.
    /// - Returns: A multiple of ``increment``. Never traps: a value close enough to `Int`'s bounds
    ///   that stepping away from zero would overflow stays on the multiple nearer zero instead.
    public func rounded(_ weight: Weight) -> Weight {
        Weight(
            grams: Weight.rounded(
                weight.grams, toMultipleOf: increment.grams, strategy: strategy))
    }
}

// MARK: - Codable

extension RoundingRule {
    /// The wire format's keys. Declared rather than synthesised so the spelling is pinned: this is
    /// the module's first composite `Codable` type, and every later one (`SetRecord` T-0.12,
    /// `Prescription` T-0.20) follows the precedent set here.
    ///
    /// The shape is `{"increment": 2500, "strategy": "nearest"}` — `increment` is a bare integer
    /// of grams, because that is `Weight`'s pinned single-value format, and `strategy` is the
    /// enum's bare raw string. Changing any of that is a storage migration.
    private enum CodingKeys: String, CodingKey {
        case increment
        case strategy
    }

    /// Decodes the keyed shape described on ``CodingKeys``.
    ///
    /// Hand-written for the same reason `DisplayPrecision`'s is: synthesised `Decodable` bypasses
    /// ``init(increment:strategy:)`` and would happily produce a zero-increment rule that divides
    /// by zero downstream. An unknown ``strategy`` string throws, inherited from
    /// `RoundingStrategy`'s synthesised conformance — the direction vocabulary is closed, and a
    /// rule whose direction is unreadable cannot be applied to anything.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let increment = try container.decode(Weight.self, forKey: .increment)
        let strategy = try container.decode(RoundingStrategy.self, forKey: .strategy)
        guard let rule = RoundingRule(increment: increment, strategy: strategy) else {
            throw DecodingError.dataCorruptedError(
                forKey: .increment,
                in: container,
                debugDescription: "RoundingRule increment must be at least 1 g, got \(increment)."
            )
        }
        self = rule
    }

    /// Writes the two keys in declaration order.
    ///
    /// Hand-written so the order is a decision rather than a side effect of synthesis: T-0.20
    /// asserts that encode → decode → encode is *byte* stable, and byte stability of a keyed shape
    /// is key order plus key spelling. Both are pinned by test.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(increment, forKey: .increment)
        try container.encode(strategy, forKey: .strategy)
    }
}
