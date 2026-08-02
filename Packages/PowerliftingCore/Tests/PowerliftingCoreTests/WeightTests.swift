import Testing

@testable import PowerliftingCore

// Kept deliberately free of Foundation, like the module it tests: this suite runs on the Linux
// job (T-0.08) too, and a test target that drifts from its module's constraints (NFR-0.2) stops
// being evidence about that module. `Codable` is asserted through `CodableProbe.swift` rather
// than `JSONEncoder` for exactly this reason — see the rationale at the top of that file.

@Suite("Weight — storage and construction")
struct WeightStorageTests {
    @Test("Grams are stored verbatim")
    func gramsRoundTripThroughTheInitialiser() {
        #expect(Weight(grams: 102_500).grams == 102_500)
        #expect(Weight(grams: 0).grams == 0)
        #expect(Weight(grams: -2_500).grams == -2_500)
    }

    @Test("Zero is zero grams")
    func zeroIsZeroGrams() {
        #expect(Weight.zero.grams == 0)
        #expect(Weight.zero == Weight(grams: 0))
    }

    @Test("Description names its unit")
    func descriptionNamesItsUnit() {
        #expect(Weight(grams: 102_500).description == "102500 g")
        #expect(Weight(grams: -500).description == "-500 g")
    }
}

@Suite("Weight — kilogram conversion is lossless")
struct WeightKilogramConversionTests {
    // 0.001 kg is the resolution floor (one gram); 0.5 and 1.25 are G-3.3's display boundaries;
    // 20 is a competition bar; 102.5 and 227.5 are ordinary loads.
    @Test(
        "kg → grams → kg returns the original exactly",
        arguments: [0.0, 0.001, 0.5, 1.25, 2.5, 20.0, 102.5, 227.5, 999.999]
    )
    func kilogramRoundTripIsExact(kilograms: Double) {
        let weight = Weight(kilograms: kilograms, rounding: .nearest)
        #expect(weight?.kilograms == kilograms)
    }

    @Test("A kilogram is exactly one thousand grams")
    func aKilogramIsAThousandGrams() {
        #expect(Weight(kilograms: 1, rounding: .nearest)?.grams == 1_000)
        #expect(Weight(kilograms: 102.5, rounding: .nearest)?.grams == 102_500)
        #expect(Weight(kilograms: -2.5, rounding: .nearest)?.grams == -2_500)
    }

    @Test("Negative kilogram values round-trip too")
    func negativeKilogramRoundTrip() {
        #expect(Weight(kilograms: -102.5, rounding: .nearest)?.kilograms == -102.5)
    }
}

@Suite("Weight — pound conversion is lossless within one gram")
struct WeightPoundConversionTests {
    /// A pound is 453.59237 g, so no whole number of pounds is a whole number of grams. The most
    /// a single conversion can lose is half a gram; `G-1.1`'s guarantee is that grams stay
    /// authoritative, not that pounds are exact.
    private static let gramsPerPound = 453.59237

    @Test(
        "lb → grams → lb returns the original within one gram",
        arguments: [0.0, 1.0, 2.5, 45.0, 135.0, 225.0, 315.0, 1000.0]
    )
    func poundRoundTripIsWithinOneGram(pounds: Double) throws {
        let weight = try #require(Weight(pounds: pounds, rounding: .nearest))
        let driftInGrams = abs(weight.pounds - pounds) * Self.gramsPerPound
        #expect(driftInGrams <= 1.0)
    }

    @Test("A pound is 453.59237 grams, rounded to whole grams")
    func aPoundIsFourFiftyThreeGrams() {
        #expect(Weight(pounds: 1, rounding: .nearest)?.grams == 454)
        #expect(Weight(pounds: 1, rounding: .down)?.grams == 453)
        #expect(Weight(pounds: 1, rounding: .up)?.grams == 454)
        #expect(Weight(pounds: 225, rounding: .nearest)?.grams == 102_058)
    }

    @Test("Negative pound values round-trip within one gram")
    func negativePoundRoundTrip() throws {
        let weight = try #require(Weight(pounds: -45, rounding: .nearest))
        #expect(abs(weight.pounds - -45) * Self.gramsPerPound <= 1.0)
    }
}

@Suite("Weight — floating-point entry demands a rounding decision")
struct WeightFloatingPointEntryTests {
    // 2.5004 kg is 2500.4 g and 2.5006 kg is 2500.6 g — either side of a gram boundary, and
    // neither of them a tie, so all three strategies have an unambiguous answer.
    @Test("Rounding strategy decides the last gram")
    func strategyDecidesTheLastGram() {
        #expect(Weight(kilograms: 2.5004, rounding: .nearest)?.grams == 2_500)
        #expect(Weight(kilograms: 2.5004, rounding: .down)?.grams == 2_500)
        #expect(Weight(kilograms: 2.5004, rounding: .up)?.grams == 2_501)

        #expect(Weight(kilograms: 2.5006, rounding: .nearest)?.grams == 2_501)
        #expect(Weight(kilograms: 2.5006, rounding: .down)?.grams == 2_500)
        #expect(Weight(kilograms: 2.5006, rounding: .up)?.grams == 2_501)
    }

    @Test("`.down` and `.up` are floor and ceiling, not magnitude")
    func downAndUpAreDirectionalNotMagnitude() {
        #expect(Weight(kilograms: -2.5004, rounding: .nearest)?.grams == -2_500)
        #expect(Weight(kilograms: -2.5004, rounding: .down)?.grams == -2_501)
        #expect(Weight(kilograms: -2.5004, rounding: .up)?.grams == -2_500)
    }

    @Test(
        "Non-finite input is rejected, not trapped",
        arguments: [
            Double.nan, .infinity, -.infinity, .signalingNaN,
        ])
    func nonFiniteInputIsRejected(value: Double) {
        #expect(Weight(kilograms: value, rounding: .nearest) == nil)
        #expect(Weight(pounds: value, rounding: .nearest) == nil)
    }

    @Test("Input beyond Int is rejected, not trapped")
    func outOfRangeInputIsRejected() {
        #expect(Weight(kilograms: 1e300, rounding: .nearest) == nil)
        #expect(Weight(kilograms: -1e300, rounding: .nearest) == nil)
        #expect(Weight(pounds: 1e300, rounding: .nearest) == nil)
    }
}

@Suite("Weight — comparison and hashing")
struct WeightComparisonTests {
    @Test("Ordering follows grams")
    func orderingFollowsGrams() {
        #expect(Weight(grams: 100) < Weight(grams: 101))
        #expect(Weight(grams: -1) < Weight.zero)
        #expect(Weight(grams: 100) <= Weight(grams: 100))
        #expect(Weight(grams: 102_500) > Weight(grams: 102_499))
    }

    @Test("Sorting orders lightest first")
    func sortingOrdersLightestFirst() {
        let sorted = [Weight(grams: 102_500), .zero, Weight(grams: -500), Weight(grams: 20_000)]
            .sorted()
        #expect(sorted.map(\.grams) == [-500, 0, 20_000, 102_500])
    }

    @Test("Equal grams are equal and hash alike")
    func equalGramsHashAlike() throws {
        let set: Set<Weight> = [Weight(grams: 20_000), Weight(grams: 20_000), Weight(grams: 500)]
        #expect(set.count == 2)
        // `try #require` rather than `!`: a force unwrap here would crash the whole run instead
        // of failing this one test, and it trips force_unwrapping (T-0.05).
        let twentyKilograms = try #require(Weight(kilograms: 20, rounding: .nearest))
        #expect(set.contains(twentyKilograms))
    }
}

@Suite("Weight — arithmetic")
struct WeightArithmeticTests {
    @Test("Addition and subtraction work in grams")
    func additionAndSubtraction() {
        #expect(Weight(grams: 20_000) + Weight(grams: 2_500) == Weight(grams: 22_500))
        #expect(Weight(grams: 20_000) - Weight(grams: 22_500) == Weight(grams: -2_500))
        #expect(Weight(grams: 500) - Weight(grams: 500) == .zero)
    }

    @Test("Compound assignment matches the operators")
    func compoundAssignment() {
        var weight = Weight(grams: 20_000)
        weight += Weight(grams: 2_500)
        #expect(weight == Weight(grams: 22_500))
        weight -= Weight(grams: 22_500)
        #expect(weight == .zero)
        weight = Weight(grams: 1_250)
        weight *= 4
        #expect(weight == Weight(grams: 5_000))
    }

    @Test("Negation turns an increment into a decrement")
    func negation() {
        #expect(-Weight(grams: 2_500) == Weight(grams: -2_500))
        #expect(-Weight.zero == .zero)
    }

    @Test("Whole-number scaling commutes")
    func wholeNumberScalingCommutes() {
        #expect(Weight(grams: 1_250) * 4 == Weight(grams: 5_000))
        #expect(4 * Weight(grams: 1_250) == Weight(grams: 5_000))
        #expect(Weight(grams: 1_250) * -1 == Weight(grams: -1_250))
        #expect(Weight(grams: 1_250) * 0 == .zero)
    }

    @Test("A sequence of weights sums through AdditiveArithmetic")
    func sequenceSums() {
        let plates = [Weight(grams: 25_000), Weight(grams: 20_000), Weight(grams: 1_250)]
        #expect(plates.reduce(Weight.zero, +) == Weight(grams: 46_250))
    }
}

@Suite("Weight — Codable wire format")
struct WeightCodableTests {
    @Test("Encodes as a bare integer of grams")
    func encodesAsBareInteger() throws {
        #expect(try probeEncode(Weight(grams: 102_500)) == .int(102_500))
        #expect(try probeEncode(Weight.zero) == .int(0))
        #expect(try probeEncode(Weight(grams: -2_500)) == .int(-2_500))
    }

    @Test("Decodes from a bare integer of grams")
    func decodesFromBareInteger() throws {
        #expect(try probeDecode(Weight.self, from: .int(102_500)) == Weight(grams: 102_500))
        #expect(try probeDecode(Weight.self, from: .int(-2_500)) == Weight(grams: -2_500))
    }

    @Test(
        "encode → decode → encode is stable",
        arguments: [0, 1, 500, 20_000, 102_500, -2_500, Int.max, Int.min]
    )
    func roundTripIsStable(grams: Int) throws {
        let original = Weight(grams: grams)
        let encoded = try probeEncode(original)
        let decoded = try probeDecode(Weight.self, from: encoded)
        #expect(decoded == original)
        #expect(try probeEncode(decoded) == encoded)
    }

    @Test("A non-integer payload is rejected")
    func nonIntegerPayloadIsRejected() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(Weight.self, from: .string("102500"))
        }
    }
}

@Suite("Weight — concurrency and value semantics (TR-0.1.3)")
struct WeightSendabilityTests {
    /// Compiles only if `T` is `Sendable`. `TR-0.1.3` is a compile-time property, so this is the
    /// only kind of test it can have — and it is not redundant with the `: Sendable` in the
    /// declaration, because implicit synthesis does not cover `public` types and an omitted
    /// conformance still compiles *inside* the module.
    private func requireSendable<T: Sendable>(_ type: T.Type) {}

    @Test("Domain types are Sendable")
    func domainTypesAreSendable() {
        requireSendable(Weight.self)
        requireSendable(MassUnit.self)
        requireSendable(RoundingStrategy.self)
        requireSendable(DisplayPrecision.self)
    }

    @Test("Assignment copies rather than aliases")
    func assignmentCopies() {
        let original = Weight(grams: 20_000)
        var copy = original
        copy += Weight(grams: 2_500)
        #expect(original == Weight(grams: 20_000))
        #expect(copy == Weight(grams: 22_500))
    }
}
