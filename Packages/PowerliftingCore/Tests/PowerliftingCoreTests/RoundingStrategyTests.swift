import Testing

@testable import PowerliftingCore

@Suite("RoundingStrategy")
struct RoundingStrategyTests {
    @Test("There are exactly three directions")
    func thereAreThreeDirections() {
        #expect(RoundingStrategy.allCases == [.nearest, .down, .up])
    }

    // Halves are exactly representable in binary floating point, so these are genuine ties rather
    // than values that happen to sit near one.
    @Test(
        "`.nearest` breaks exact ties away from zero",
        arguments: [(0.5, 1), (1.5, 2), (2.5, 3), (-0.5, -1), (-1.5, -2), (-2.5, -3)]
    )
    func nearestBreaksTiesAwayFromZero(value: Double, expected: Int) {
        #expect(RoundingStrategy.nearest.roundedToInt(value) == expected)
    }

    @Test(
        "`.down` is the floor, including for negatives",
        arguments: [(0.9, 0), (1.5, 1), (-0.1, -1), (-1.5, -2), (-2.0, -2)]
    )
    func downIsTheFloor(value: Double, expected: Int) {
        #expect(RoundingStrategy.down.roundedToInt(value) == expected)
    }

    @Test(
        "`.up` is the ceiling, including for negatives",
        arguments: [(0.1, 1), (1.5, 2), (-0.9, 0), (-1.5, -1), (-2.0, -2)]
    )
    func upIsTheCeiling(value: Double, expected: Int) {
        #expect(RoundingStrategy.up.roundedToInt(value) == expected)
    }

    @Test("Whole numbers are unchanged by every strategy", arguments: RoundingStrategy.allCases)
    func wholeNumbersAreUnchanged(strategy: RoundingStrategy) {
        #expect(strategy.roundedToInt(0) == 0)
        #expect(strategy.roundedToInt(42) == 42)
        #expect(strategy.roundedToInt(-42) == -42)
    }

    @Test("Non-finite input yields nil", arguments: RoundingStrategy.allCases)
    func nonFiniteYieldsNil(strategy: RoundingStrategy) {
        #expect(strategy.roundedToInt(.nan) == nil)
        #expect(strategy.roundedToInt(.infinity) == nil)
        #expect(strategy.roundedToInt(-.infinity) == nil)
    }

    @Test("Input beyond Int yields nil", arguments: RoundingStrategy.allCases)
    func outOfRangeYieldsNil(strategy: RoundingStrategy) {
        #expect(strategy.roundedToInt(1e30) == nil)
        #expect(strategy.roundedToInt(-1e30) == nil)
    }

    @Test("Encodes as its raw string, which is the persisted spelling")
    func encodesAsRawString() throws {
        #expect(try probeEncode(RoundingStrategy.nearest) == .string("nearest"))
        #expect(try probeEncode(RoundingStrategy.down) == .string("down"))
        #expect(try probeEncode(RoundingStrategy.up) == .string("up"))
    }

    @Test("Round-trips through Codable", arguments: RoundingStrategy.allCases)
    func roundTripsThroughCodable(strategy: RoundingStrategy) throws {
        let encoded = try probeEncode(strategy)
        #expect(try probeDecode(RoundingStrategy.self, from: encoded) == strategy)
    }

    @Test("An unknown spelling is rejected")
    func unknownSpellingIsRejected() {
        #expect(throws: DecodingError.self) {
            _ = try probeDecode(RoundingStrategy.self, from: .string("bankers"))
        }
    }
}

@Suite("MassUnit")
struct MassUnitTests {
    @Test("Kilograms and pounds are the only display units")
    func onlyTwoUnits() {
        #expect(MassUnit.allCases == [.kilograms, .pounds])
    }

    @Test("Conversion factors are the defined values, not approximations")
    func conversionFactorsAreExact() {
        #expect(MassUnit.kilograms.gramsPerUnit == 1000)
        #expect(MassUnit.pounds.gramsPerUnit == 453.59237)
        #expect(MassUnit.kilograms.gramsPerMilliUnit == 1)
    }

    @Test("Encodes as its raw string, which is the persisted preference")
    func encodesAsRawString() throws {
        #expect(try probeEncode(MassUnit.kilograms) == .string("kilograms"))
        #expect(try probeEncode(MassUnit.pounds) == .string("pounds"))
    }

    @Test("Round-trips through Codable", arguments: MassUnit.allCases)
    func roundTripsThroughCodable(unit: MassUnit) throws {
        let encoded = try probeEncode(unit)
        #expect(try probeDecode(MassUnit.self, from: encoded) == unit)
    }
}
