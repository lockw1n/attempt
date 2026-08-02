import Testing

@testable import PowerliftingCore

@Suite("DisplayPrecision")
struct DisplayPrecisionTests {
    @Test("A step of at least one milli-unit is accepted")
    func positiveStepIsAccepted() {
        #expect(DisplayPrecision(milliUnits: 1)?.milliUnits == 1)
        #expect(DisplayPrecision(milliUnits: 500)?.milliUnits == 500)
        #expect(DisplayPrecision(milliUnits: 2_500)?.milliUnits == 2_500)
    }

    @Test("A step of zero or less is rejected")
    func nonPositiveStepIsRejected() {
        #expect(DisplayPrecision(milliUnits: 0) == nil)
        #expect(DisplayPrecision(milliUnits: -1) == nil)
        #expect(DisplayPrecision(milliUnits: Int.min) == nil)
    }

    @Test("The named steps are the fractions they claim to be")
    func namedStepsAreCorrect() {
        #expect(DisplayPrecision.quarter.milliUnits == 250)
        #expect(DisplayPrecision.half.milliUnits == 500)
        #expect(DisplayPrecision.whole.milliUnits == 1_000)
        #expect(DisplayPrecision.tenth.milliUnits == 100)
    }

    @Test("G-3.3's defaults are 0.5 kg and 1 lb")
    func defaultsMatchG33() {
        #expect(DisplayPrecision.default(for: .kilograms) == .half)
        #expect(DisplayPrecision.default(for: .pounds) == .whole)
    }

    @Test(
        "Fraction digits are the fewest that can represent the step",
        arguments: [
            (1_000, 0), (2_000, 0), (500, 1), (2_500, 1), (100, 1),
            (250, 2), (1_250, 2), (10, 2), (1, 3), (5, 3), (1_005, 3)
        ]
    )
    func fractionDigitsAreMinimal(milliUnits: Int, expected: Int) throws {
        let precision = try #require(DisplayPrecision(milliUnits: milliUnits))
        #expect(precision.fractionDigits == expected)
    }

    @Test("Encodes as a bare integer of milli-units")
    func encodesAsBareInteger() throws {
        #expect(try probeEncode(DisplayPrecision.half) == .int(500))
        #expect(try probeEncode(DisplayPrecision.whole) == .int(1_000))
    }

    @Test("Round-trips through Codable")
    func roundTripsThroughCodable() throws {
        for precision in [DisplayPrecision.quarter, .half, .whole, .tenth] {
            let encoded = try probeEncode(precision)
            #expect(try probeDecode(DisplayPrecision.self, from: encoded) == precision)
        }
    }

    @Test("Decoding enforces the same invariant as the initialiser")
    func decodingEnforcesTheInvariant() {
        // The point of hand-writing `init(from:)`: synthesised `Decodable` would bypass
        // `init?(milliUnits:)` and produce a zero step that divides by zero downstream.
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(DisplayPrecision.self, from: .int(0))
        }
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(DisplayPrecision.self, from: .int(-500))
        }
    }
}
