import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2).

/// The four increments `TR-0.2.6`'s "done when" names, in grams.
///
/// Gram literals rather than `Weight(kilograms:rounding:)` calls because the `arguments:` of a
/// parameterized test needs constants, and because a failable initialiser cannot be force
/// unwrapped here (`force_unwrapping` is banned by `.swiftlint.yml`). The literals are not taken
/// on trust: `incrementsAreTheStepsTheyClaimToBe` asserts each one against the conversion. A pound
/// is not a whole number of grams, which is why 5 lb is 2268 g and 1 lb is 454 g.
enum Increments {
    /// The identity: every weight is already a multiple of one gram. How a caller asks for a rule
    /// that does not round — `RoundingRule` has no "none".
    static let oneGram = Weight(grams: 1)
    static let twoAndAHalfKilograms = Weight(grams: 2_500)
    static let oneAndAQuarterKilograms = Weight(grams: 1_250)
    static let fivePounds = Weight(grams: 2_268)
    static let onePound = Weight(grams: 454)
}

/// Builds a rule, failing the test rather than force unwrapping.
func roundingRule(_ increment: Weight, _ strategy: RoundingStrategy) throws -> RoundingRule {
    try #require(RoundingRule(increment: increment, strategy: strategy))
}

@Suite("RoundingRule — construction")
struct RoundingRuleConstructionTests {
    @Test("An increment of at least one gram is accepted")
    func positiveIncrementIsAccepted() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 1), strategy: .nearest))
        #expect(rule.increment == Weight(grams: 1))
        #expect(rule.strategy == .nearest)
    }

    @Test("The named increments are the kg and lb steps they claim to be")
    func incrementsAreTheStepsTheyClaimToBe() throws {
        #expect(try #require(Weight(kilograms: 2.5, rounding: .nearest)) == Increments.twoAndAHalfKilograms)
        #expect(try #require(Weight(kilograms: 1.25, rounding: .nearest)) == Increments.oneAndAQuarterKilograms)
        #expect(try #require(Weight(pounds: 5, rounding: .nearest)) == Increments.fivePounds)
        #expect(try #require(Weight(pounds: 1, rounding: .nearest)) == Increments.onePound)
    }

    @Test("A zero or negative increment is rejected", arguments: [0, -1, -2_500, Int.min])
    func nonPositiveIncrementIsRejected(grams: Int) {
        // A precondition inside `Weight.rounded` would be a crash; `TR-0.2.6`'s boundary is here,
        // and it is failable for the same reason `DisplayPrecision`'s is.
        #expect(RoundingRule(increment: Weight(grams: grams), strategy: .nearest) == nil)
        #expect(RoundingRule(increment: Weight(grams: grams), strategy: .down) == nil)
        #expect(RoundingRule(increment: Weight(grams: grams), strategy: .up) == nil)
    }

    @Test("Rules are equal when both halves match")
    func equalityCoversBothProperties() {
        let base = RoundingRule(increment: Increments.twoAndAHalfKilograms, strategy: .nearest)
        #expect(base == RoundingRule(increment: Weight(grams: 2_500), strategy: .nearest))
        #expect(base != RoundingRule(increment: Weight(grams: 2_500), strategy: .up))
        #expect(base != RoundingRule(increment: Weight(grams: 1_250), strategy: .nearest))
    }
}

@Suite("RoundingRule — the increments TR-0.2.6 names")
struct RoundingRuleIncrementTests {
    @Test(
        "A 102.483 kg target snaps to each increment in each direction",
        arguments: [
            // increment, nearest, down, up
            (Increments.twoAndAHalfKilograms, 102_500, 100_000, 102_500),
            (Increments.oneAndAQuarterKilograms, 102_500, 101_250, 102_500),
            (Increments.fivePounds, 102_060, 102_060, 104_328),
            (Increments.onePound, 102_604, 102_150, 102_604),
        ]
    )
    func targetSnapsToIncrement(increment: Weight, nearest: Int, down: Int, up: Int) throws {
        let target = Weight(grams: 102_483)
        #expect(try roundingRule(increment, .nearest).rounded(target) == Weight(grams: nearest))
        #expect(try roundingRule(increment, .down).rounded(target) == Weight(grams: down))
        #expect(try roundingRule(increment, .up).rounded(target) == Weight(grams: up))
    }

    @Test(
        "An exact multiple is unchanged by all three strategies",
        arguments: [
            (Increments.twoAndAHalfKilograms, 100_000),
            (Increments.oneAndAQuarterKilograms, 101_250),
            (Increments.fivePounds, 102_060),
            (Increments.onePound, 102_150),
        ]
    )
    func exactMultipleIsUnchanged(increment: Weight, grams: Int) throws {
        let target = Weight(grams: grams)
        for strategy in RoundingStrategy.allCases {
            #expect(try roundingRule(increment, strategy).rounded(target) == target)
        }
    }

    @Test("Zero is a multiple of every increment")
    func zeroIsUnchanged() throws {
        for strategy in RoundingStrategy.allCases {
            #expect(try roundingRule(Increments.twoAndAHalfKilograms, strategy).rounded(.zero) == .zero)
        }
    }
}

@Suite("RoundingRule — tie-breaking")
struct RoundingRuleTieTests {
    @Test("An exact tie rounds away from zero")
    func tieRoundsAwayFromZero() throws {
        // The documented case: 102.5 kg on a 5 kg increment is 105, not 100. A lifter reading a
        // prescribed 102.5 kg expects the heavier bar, not the lighter one.
        let rule = try #require(RoundingRule(increment: Weight(grams: 5_000), strategy: .nearest))
        #expect(rule.rounded(Weight(grams: 102_500)) == Weight(grams: 105_000))
        #expect(rule.rounded(Weight(grams: -102_500)) == Weight(grams: -105_000))
    }

    @Test("One gram either side of a tie rounds to the nearer multiple")
    func justEitherSideOfATie() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 5_000), strategy: .nearest))
        #expect(rule.rounded(Weight(grams: 102_499)) == Weight(grams: 100_000))
        #expect(rule.rounded(Weight(grams: 102_501)) == Weight(grams: 105_000))
        #expect(rule.rounded(Weight(grams: -102_499)) == Weight(grams: -100_000))
        #expect(rule.rounded(Weight(grams: -102_501)) == Weight(grams: -105_000))
    }
}

@Suite("RoundingRule — direction on negative weights")
struct RoundingRuleDirectionTests {
    // `.down` is floor and `.up` is ceiling, not "smaller" and "larger in magnitude". `Weight` is
    // signed because it doubles as a delta (an increment, a deload, target-minus-loaded), so this
    // path is reachable rather than theoretical, and Swift's `/` truncating toward zero is exactly
    // the trap it invites: -7 down to a step of 5 is -10, not -5.

    @Test(
        "Down is floor for both signs",
        arguments: [(7, 5), (-7, -10), (0, 0), (5, 5), (-5, -5), (-1, -5), (1, 0)]
    )
    func downIsFloor(grams: Int, expected: Int) throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 5), strategy: .down))
        #expect(rule.rounded(Weight(grams: grams)) == Weight(grams: expected))
    }

    @Test(
        "Up is ceiling for both signs",
        arguments: [(7, 10), (-7, -5), (0, 0), (5, 5), (-5, -5), (-1, 0), (1, 5)]
    )
    func upIsCeiling(grams: Int, expected: Int) throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 5), strategy: .up))
        #expect(rule.rounded(Weight(grams: grams)) == Weight(grams: expected))
    }

    @Test("A negative delta rounds symmetrically to its positive twin under .nearest")
    func nearestIsSymmetric() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 2_500), strategy: .nearest))
        for grams in [1, 1_249, 1_250, 2_499, 102_483, 7] {
            #expect(rule.rounded(Weight(grams: -grams)) == -rule.rounded(Weight(grams: grams)))
        }
    }
}

@Suite("RoundingRule — extreme magnitudes")
struct RoundingRuleOverflowTests {
    // Unreachable from any physical load, and asserted anyway: the alternative to saturating is a
    // trap, and this function is called from resolvers (T-0.19, T-0.21) that have no way to report
    // one. A naive `(quotient + 1) * step` traps here; stepping from the truncated multiple with
    // an overflow check does not.

    @Test("Rounding up at Int.max stays on the truncated multiple")
    func upSaturatesAtIntMax() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 2_500), strategy: .up))
        #expect(rule.rounded(Weight(grams: .max)) == Weight(grams: Int.max - (Int.max % 2_500)))
    }

    @Test("Rounding down at Int.min stays on the truncated multiple")
    func downSaturatesAtIntMin() throws {
        let rule = try #require(RoundingRule(increment: Weight(grams: 2_500), strategy: .down))
        #expect(rule.rounded(Weight(grams: .min)) == Weight(grams: Int.min - (Int.min % 2_500)))
    }

    @Test("Rounding away from zero at the bounds stays on the truncated multiple")
    func nearestSaturatesAtBothBounds() throws {
        // A 1 kg increment on purpose: `Int.max` sits 807 g above a multiple of 1000, which is
        // past the halfway mark, so `.nearest` takes the away-from-zero branch and finds no room.
        let rule = try #require(RoundingRule(increment: Weight(grams: 1_000), strategy: .nearest))
        #expect(rule.rounded(Weight(grams: .max)) == Weight(grams: Int.max - (Int.max % 1_000)))
        #expect(rule.rounded(Weight(grams: .min)) == Weight(grams: Int.min - (Int.min % 1_000)))
    }

    @Test("A one-gram increment leaves every weight alone")
    func oneGramIncrementIsTheIdentity() throws {
        for strategy in RoundingStrategy.allCases {
            let rule = try #require(RoundingRule(increment: Weight(grams: 1), strategy: strategy))
            for grams in [0, 1, -1, 102_483, Int.max, Int.min] {
                #expect(rule.rounded(Weight(grams: grams)) == Weight(grams: grams))
            }
        }
    }
}

@Suite("RoundingRule — wire format")
struct RoundingRuleCodableTests {
    // The module's first composite shape, so this suite pins the precedent rather than just
    // checking a round trip: key spelling, key order, and the fact that a nested `Weight` stays a
    // bare integer. `ProbeValue.object` compares its fields in order, so the assertion below fails
    // if the two `encode` calls are ever swapped.

    private let encodedShape = ProbeValue.object([
        ProbeField(key: "increment", value: .int(2_500)),
        ProbeField(key: "strategy", value: .string("nearest")),
    ])

    @Test("Encodes as a two-key object with the increment as a bare integer of grams")
    func encodesAsPinnedObject() throws {
        let rule = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        #expect(try probeEncode(rule) == encodedShape)
    }

    @Test("Round-trips through Codable")
    func roundTripsThroughCodable() throws {
        for strategy in RoundingStrategy.allCases {
            for grams in [1, 454, 1_250, 2_500, Int.max] {
                let original = try roundingRule(Weight(grams: grams), strategy)
                #expect(try probeDecode(RoundingRule.self, from: try probeEncode(original)) == original)
            }
        }
    }

    @Test("Encode → decode → encode is byte-stable")
    func encodingIsStableAcrossARoundTrip() throws {
        let first = try probeEncode(try roundingRule(Increments.twoAndAHalfKilograms, .nearest))
        let second = try probeEncode(try probeDecode(RoundingRule.self, from: first))
        #expect(first == second)
    }

    @Test("Decoding accepts the keys in either order")
    func decodingIsOrderInsensitive() throws {
        let reordered = ProbeValue.object([
            ProbeField(key: "strategy", value: .string("nearest")),
            ProbeField(key: "increment", value: .int(2_500)),
        ])
        let expected = try roundingRule(Increments.twoAndAHalfKilograms, .nearest)
        #expect(try probeDecode(RoundingRule.self, from: reordered) == expected)
        // …and re-encoding puts them back in the pinned order.
        #expect(try probeEncode(try probeDecode(RoundingRule.self, from: reordered)) == encodedShape)
    }

    @Test("Decoding enforces the same increment invariant as the initialiser", arguments: [0, -1, -2_500])
    func decodingEnforcesTheIncrementInvariant(grams: Int) {
        // The point of hand-writing `init(from:)`: synthesised `Decodable` would bypass
        // `init?(increment:strategy:)` and produce a zero increment that divides by zero.
        let corrupt = ProbeValue.object([
            ProbeField(key: "increment", value: .int(grams)),
            ProbeField(key: "strategy", value: .string("nearest")),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RoundingRule.self, from: corrupt)
        }
    }

    @Test("An unknown strategy throws rather than degrading")
    func unknownStrategyThrows() {
        // Deliberately unlike `Movement`/`Equipment`/`BarType`, which degrade to `.other`. Those
        // have an upstream copy that a seed re-import restores (T-0.52); a rounding direction has
        // none, and a rule whose direction is unreadable cannot be applied to anything.
        let future = ProbeValue.object([
            ProbeField(key: "increment", value: .int(2_500)),
            ProbeField(key: "strategy", value: .string("bankers")),
        ])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RoundingRule.self, from: future)
        }
    }

    @Test("A missing key throws")
    func missingKeyThrows() {
        let truncated = ProbeValue.object([ProbeField(key: "increment", value: .int(2_500))])
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RoundingRule.self, from: truncated)
        }
    }

    @Test("A non-object throws")
    func nonObjectThrows() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RoundingRule.self, from: .int(2_500))
        }
    }
}
