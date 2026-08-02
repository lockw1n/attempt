import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target — see the note in `WeightTests.swift`.
// `NumberFormatter` is doubly out of bounds here: it is Foundation (NFR-0.2) and it is locale
// dependent, so the same weight would render differently on a runner and on a phone.

@Suite("Weight — display formatting at the default precision (G-3.3)")
struct WeightDefaultPrecisionFormattingTests {
    @Test("Kilograms default to a half-kilogram step")
    func kilogramsDefaultToHalfKilogram() {
        #expect(Weight(grams: 102_500).formatted(in: .kilograms) == "102.5")
        #expect(Weight(grams: 102_400).formatted(in: .kilograms) == "102.5")
        #expect(Weight(grams: 102_000).formatted(in: .kilograms) == "102.0")
        #expect(Weight(grams: 20_000).formatted(in: .kilograms) == "20.0")
    }

    @Test("Pounds default to a one-pound step")
    func poundsDefaultToOnePound() {
        // 102.5 kg is 225.97 lb; a 20 kg bar is 44.09 lb; 102 058 g is exactly 225 lb.
        #expect(Weight(grams: 102_500).formatted(in: .pounds) == "226")
        #expect(Weight(grams: 20_000).formatted(in: .pounds) == "44")
        #expect(Weight(grams: 102_058).formatted(in: .pounds) == "225")
    }

    @Test("The convenience overload matches the explicit default")
    func convenienceOverloadMatchesExplicitDefault() {
        let weight = Weight(grams: 102_499)
        for unit in MassUnit.allCases {
            #expect(
                weight.formatted(in: unit)
                    == weight.formatted(in: unit, precision: .default(for: unit)))
        }
    }
}

@Suite("Weight — display rounding")
struct WeightDisplayRoundingTests {
    @Test("Rounds to the nearest step")
    func roundsToNearestStep() {
        #expect(Weight(grams: 102_249).formatted(in: .kilograms) == "102.0")
        #expect(Weight(grams: 102_251).formatted(in: .kilograms) == "102.5")
    }

    @Test("An exact tie rounds away from zero")
    func tieRoundsAwayFromZero() {
        #expect(Weight(grams: 102_250).formatted(in: .kilograms) == "102.5")
        #expect(Weight(grams: -102_250).formatted(in: .kilograms) == "-102.5")
    }

    @Test("Display rounding never mutates the stored grams (G-3.2)")
    func displayRoundingDoesNotMutateStorage() {
        let weight = Weight(grams: 102_483)
        #expect(weight.formatted(in: .kilograms) == "102.5")
        #expect(weight.grams == 102_483)
        #expect(weight.formatted(in: .pounds) == "226")
        #expect(weight.grams == 102_483)
    }

    @Test("Switching unit does not mutate the stored grams (G-3.2)")
    func switchingUnitDoesNotMutateStorage() {
        let weight = Weight(grams: 102_500)
        let asKilograms = weight.converted(to: .kilograms)
        let asPounds = weight.converted(to: .pounds)
        #expect(asKilograms == weight.kilograms)
        #expect(asPounds == weight.pounds)
        #expect(weight.grams == 102_500)
    }

    @Test(
        "Rounding to a multiple is exact integer arithmetic",
        arguments: [
            (0, 500, 0), (500, 500, 500), (249, 500, 0), (250, 500, 500), (251, 500, 500),
            (-249, 500, 0), (-250, 500, -500), (-751, 500, -1_000), (1_250, 1_250, 1_250),
        ]
    )
    func roundingToMultipleIsExact(value: Int, step: Int, expected: Int) {
        #expect(Weight.rounded(value, toMultipleOf: step) == expected)
    }
}

@Suite("Weight — display precision other than the default")
struct WeightPrecisionFormattingTests {
    @Test("A quarter-unit step renders two decimals")
    func quarterStepRendersTwoDecimals() {
        #expect(Weight(grams: 101_250).formatted(in: .kilograms, precision: .quarter) == "101.25")
        #expect(Weight(grams: 101_200).formatted(in: .kilograms, precision: .quarter) == "101.25")
        #expect(Weight(grams: 101_000).formatted(in: .kilograms, precision: .quarter) == "101.00")
    }

    @Test("A tenth-unit step renders one decimal")
    func tenthStepRendersOneDecimal() {
        #expect(Weight(grams: 102_450).formatted(in: .kilograms, precision: .tenth) == "102.5")
        #expect(Weight(grams: 102_440).formatted(in: .kilograms, precision: .tenth) == "102.4")
    }

    @Test("A whole-unit step renders no decimals")
    func wholeStepRendersNoDecimals() {
        #expect(Weight(grams: 102_500).formatted(in: .kilograms, precision: .whole) == "103")
        #expect(Weight(grams: 102_400).formatted(in: .kilograms, precision: .whole) == "102")
    }

    @Test("A one-gram step renders three decimals in kilograms")
    func oneGramStepRendersThreeDecimals() throws {
        let gram = try #require(DisplayPrecision(milliUnits: 1))
        #expect(Weight(grams: 1).formatted(in: .kilograms, precision: gram) == "0.001")
        #expect(Weight(grams: 102_483).formatted(in: .kilograms, precision: gram) == "102.483")
    }

    @Test("Trailing zeros are kept, not trimmed")
    func trailingZerosAreKept() {
        #expect(Weight(grams: 100_000).formatted(in: .kilograms) == "100.0")
        #expect(Weight(grams: 0).formatted(in: .kilograms) == "0.0")
        #expect(Weight(grams: 0).formatted(in: .pounds) == "0")
    }
}

@Suite("Weight — formatting edge cases")
struct WeightFormattingEdgeCaseTests {
    @Test("Negative weights carry a leading minus")
    func negativeWeightsCarryAMinus() {
        #expect(Weight(grams: -2_500).formatted(in: .kilograms) == "-2.5")
        #expect(Weight(grams: -102_500).formatted(in: .kilograms) == "-102.5")
    }

    @Test("A negative that rounds to zero renders as plain zero, not minus zero")
    func negativeRoundingToZeroHasNoSign() {
        #expect(Weight(grams: -100).formatted(in: .kilograms) == "0.0")
        #expect(Weight(grams: -1).formatted(in: .pounds) == "0")
    }

    @Test("Kilogram formatting uses no floating point at all")
    func kilogramFormattingIsIntegerOnly() {
        // One gram is exactly one milli-kilogram, so the conversion is the identity.
        #expect(Weight(grams: 102_483).milliUnits(in: .kilograms) == 102_483)
        #expect(Weight(grams: -7).milliUnits(in: .kilograms) == -7)
    }

    @Test("The pound conversion clamps rather than trapping at absurd magnitudes")
    func poundConversionClamps() {
        // Unreachable from any physical load — asserted because the alternative to clamping is a
        // crash inside a view, and there is no other way to exercise the branch.
        #expect(Weight.saturatingRoundToNearest(1e30) == Int.max)
        #expect(Weight.saturatingRoundToNearest(-1e30) == Int.min)
        #expect(Weight.saturatingRoundToNearest(Double.nan) == 0)
        #expect(Weight.saturatingRoundToNearest(0.5) == 1)
        #expect(Weight.saturatingRoundToNearest(-0.5) == -1)
    }

    @Test("Extreme stored values format without trapping")
    func extremeValuesFormatWithoutTrapping() {
        #expect(!Weight(grams: Int.max).formatted(in: .pounds).isEmpty)
        #expect(!Weight(grams: Int.min).formatted(in: .pounds).isEmpty)
    }
}
