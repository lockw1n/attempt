import Testing

@testable import PowerliftingCore

// Foundation-free by design, like the rest of this target (NFR-0.2) — which is the whole reason
// `RealMath` exists at all.
//
// **These tests assert against mathematics, not against libm.** Every expected value below is a
// high-precision decimal literal of the true value, written to more digits than a `Double` can
// hold so that the literal rounds to the nearest representable value rather than to whatever was
// typed. Asserting against numbers copied out of the system maths library would only prove this
// implementation agrees with a different implementation, which is a weaker claim and one that
// cannot be checked by reading.
//
// The agreement with libm was measured separately, while deciding whether to hand-roll these at
// all. That measurement is recorded here because this is where the claim is pinned:
//
// - `exponential` — within 1 ulp across the whole normal range, and bit-identical to libm at every
//   overflow and underflow boundary. Below about -708.4 the *result* is subnormal and precision
//   degrades to ~142 ulp, which is inherent to subnormals rather than to the series.
// - `logarithm` — within 1 ulp across 2^-1080 … 2^1020, subnormal inputs included.
//
// Far tighter than anything here needs: an e1RM is snapped to a whole gram, so a 100 kg lift only
// asks for a relative accuracy of 1 in 10^5. The measurement that actually settled it — every
// Lombardi and Wathan result *in grams* identical to libm's, over every rep count 1…10 and seven
// different loads.

/// Constants to 40 significant figures. Far more than a `Double` holds, on purpose: the literal
/// then rounds to the nearest representable value instead of encoding a truncation.
enum Exact {
    static let eulersNumber = 2.718_281_828_459_045_235_360_287_471_352_662_497_757
    static let eSquared = 7.389_056_098_930_650_227_230_427_460_575_007_813_180
    static let eToTheMinusOne = 0.367_879_441_171_442_321_595_523_770_161_460_867_446
    static let eToTheHalf = 1.648_721_270_700_128_146_848_650_787_814_163_571_654
    static let naturalLogOfTwo = 0.693_147_180_559_945_309_417_232_121_458_176_568_075
    static let naturalLogOfThree = 1.098_612_288_668_109_691_395_245_236_922_525_704_647
    static let naturalLogOfTen = 2.302_585_092_994_045_684_017_991_454_684_364_207_601
    static let tenToTheOneTenth = 1.258_925_411_794_167_210_423_954_106_395_800_606_093
    static let twoToTheOneTenth = 1.071_773_462_536_293_164_213_006_325_023_529_168_929
}

/// How far `actual` sits from `expected`, as a fraction of `expected`.
func relativeError(_ actual: Double, _ expected: Double) -> Double {
    if actual == expected { return 0 }
    return ((actual - expected) / expected).magnitude
}

/// The tolerance every accuracy assertion below uses: four times the spacing of `Double` at 1.
///
/// Between two and eight units in the last place, depending where in a binade the value lands. The
/// measured worst case for either function is 1.8 ulp, so this leaves real margin without being so
/// loose that a genuine regression would slip through — losing a single Taylor term takes the error
/// to roughly 10⁻⁵, eleven orders of magnitude outside it.
let tolerance = 4 * Double.ulpOfOne

@Suite("RealMath — exponential")
struct RealMathExponentialTests {
    @Test("Matches the true value of e^x at known points")
    func matchesKnownValues() {
        #expect(relativeError(RealMath.exponential(1), Exact.eulersNumber) <= tolerance)
        #expect(relativeError(RealMath.exponential(2), Exact.eSquared) <= tolerance)
        #expect(relativeError(RealMath.exponential(-1), Exact.eToTheMinusOne) <= tolerance)
        #expect(relativeError(RealMath.exponential(0.5), Exact.eToTheHalf) <= tolerance)
        #expect(relativeError(RealMath.exponential(Exact.naturalLogOfTwo), 2) <= tolerance)
        #expect(relativeError(RealMath.exponential(Exact.naturalLogOfTen), 10) <= tolerance)
    }

    @Test("e^0 is exactly one")
    func zeroIsExactlyOne() {
        // Exactness matters downstream, not just tidiness: `power` routes `base^0` and `1^exponent`
        // through here, and Lombardi at one rep has to return the lifted weight unchanged.
        #expect(RealMath.exponential(0) == 1.0)
    }

    @Test("Increases strictly across the whole usable range")
    func isMonotonic() {
        // Strictly greater, not `>=`. With `>=` and a zero seed this test is satisfied by a
        // *constant* function, so it could not fail on the mutation it most needs to catch —
        // measured, and the reason this assertion is the shape it is. Strictness holds all the way
        // down into the subnormal results: at -740 the value is about 84 units in the last place,
        // and each 0.5 step multiplies it by 1.65, so consecutive values never collide.
        var previous = 0.0
        for step in stride(from: -740, through: 700, by: 0.5) {
            let value = RealMath.exponential(step)
            #expect(value > previous)
            previous = value
        }
    }

    @Test("e^(a+b) equals e^a · e^b")
    func satisfiesTheAdditionLaw() {
        for left in stride(from: -20.0, through: 20.0, by: 2.5) {
            for right in stride(from: -20.0, through: 20.0, by: 2.5) {
                let combined = RealMath.exponential(left + right)
                let separate = RealMath.exponential(left) * RealMath.exponential(right)
                #expect(relativeError(combined, separate) <= tolerance)
            }
        }
    }

    @Test("Overflows to infinity only past the last representable argument")
    func overflowBoundary() {
        // 709.782712893384 is ln(Double.greatestFiniteMagnitude): one step further has no
        // representable answer. Both sides verified against libm when this file was written.
        #expect(RealMath.exponential(709.782_712_893_384).isFinite)
        #expect(RealMath.exponential(709.79) == .infinity)
        #expect(RealMath.exponential(710) == .infinity)
        #expect(RealMath.exponential(.infinity) == .infinity)
    }

    @Test("Underflows to zero only past the last representable argument")
    func underflowBoundary() {
        // Below about -708.4 the *result* is subnormal, so it keeps fewer significant bits than a
        // normal `Double` — nothing above asserts precision there, because the loss is inherent to
        // subnormals rather than to the series. What is asserted is where the value reaches zero.
        #expect(RealMath.exponential(-745) > 0)
        #expect(RealMath.exponential(-745.133_219_101_941_1) > 0)
        #expect(RealMath.exponential(-745.2) == 0)
        #expect(RealMath.exponential(-746) == 0)
        #expect(RealMath.exponential(-.infinity) == 0)
    }

    @Test("NaN in, NaN out")
    func notANumberPropagates() {
        #expect(RealMath.exponential(.nan).isNaN)
    }
}

@Suite("RealMath — logarithm")
struct RealMathLogarithmTests {
    @Test("Matches the true value of ln x at known points")
    func matchesKnownValues() {
        #expect(relativeError(RealMath.logarithm(2), Exact.naturalLogOfTwo) <= tolerance)
        #expect(relativeError(RealMath.logarithm(3), Exact.naturalLogOfThree) <= tolerance)
        #expect(relativeError(RealMath.logarithm(10), Exact.naturalLogOfTen) <= tolerance)
        #expect(relativeError(RealMath.logarithm(Exact.eulersNumber), 1) <= tolerance)
        #expect(relativeError(RealMath.logarithm(Exact.eSquared), 2) <= tolerance)
    }

    @Test("ln 1 is exactly zero")
    func oneIsExactlyZero() {
        #expect(RealMath.logarithm(1) == 0.0)
    }

    @Test("Both halves of the argument reduction are exercised")
    func argumentReductionCoversBothBranches() {
        // A significand above √2 is halved and the exponent bumped; one below is left alone. 1.5
        // and 1.9 have significands of 1.5 and 1.9, so they take opposite branches, and both must
        // still land on the right answer.
        let naturalLogOfOnePointFive = 0.405_465_108_108_164_381_978_013_115_464_349_136_571
        let naturalLogOfOnePointNine = 0.641_853_886_172_394_874_814_339_881_921_180_772_364
        #expect(relativeError(RealMath.logarithm(1.5), naturalLogOfOnePointFive) <= tolerance)
        #expect(relativeError(RealMath.logarithm(1.9), naturalLogOfOnePointNine) <= tolerance)
    }

    @Test("ln(a·b) equals ln a + ln b")
    func satisfiesTheProductLaw() {
        for left in stride(from: 0.25, through: 8.0, by: 0.25) {
            for right in stride(from: 0.25, through: 8.0, by: 0.25) {
                let combined = RealMath.logarithm(left * right)
                let separate = RealMath.logarithm(left) + RealMath.logarithm(right)
                #expect((combined - separate).magnitude <= tolerance * 8)
            }
        }
    }

    @Test("Handles the extremes of Double, subnormals included")
    func handlesExtremeMagnitudes() {
        // `Double.significand` normalises a subnormal, so no accuracy is lost at the bottom end.
        // Measured within 1 ulp across 2^-1080 … 2^1020 before this file was written.
        #expect(relativeError(RealMath.logarithm(.leastNonzeroMagnitude), -744.440_071_921_381_2) <= tolerance)
        #expect(relativeError(RealMath.logarithm(.greatestFiniteMagnitude), 709.782_712_893_384) <= tolerance)
    }

    @Test("Undefined inputs give the IEEE answers")
    func undefinedInputs() {
        #expect(RealMath.logarithm(0) == -.infinity)
        #expect(RealMath.logarithm(-1).isNaN)
        #expect(RealMath.logarithm(-.infinity).isNaN)
        #expect(RealMath.logarithm(.infinity) == .infinity)
        #expect(RealMath.logarithm(.nan).isNaN)
    }
}

@Suite("RealMath — power")
struct RealMathPowerTests {
    @Test("Matches the true value of b^e at known points")
    func matchesKnownValues() {
        #expect(relativeError(RealMath.power(10, exponent: 0.1), Exact.tenToTheOneTenth) <= tolerance)
        #expect(relativeError(RealMath.power(2, exponent: 0.1), Exact.twoToTheOneTenth) <= tolerance)
        #expect(relativeError(RealMath.power(2, exponent: 10), 1_024) <= tolerance)
        #expect(relativeError(RealMath.power(9, exponent: 0.5), 3) <= tolerance)
        #expect(relativeError(RealMath.power(2, exponent: -1), 0.5) <= tolerance)
    }

    @Test("Agrees with repeated multiplication for whole exponents")
    func agreesWithRepeatedMultiplication() {
        for base in stride(from: 1.5, through: 6.0, by: 0.5) {
            var expected = 1.0
            for exponent in 1...8 {
                expected *= base
                #expect(relativeError(RealMath.power(base, exponent: Double(exponent)), expected) <= tolerance * 4)
            }
        }
    }

    @Test("A base of one is exactly one for any exponent")
    func oneToAnyPowerIsExactlyOne() {
        // This is what makes Lombardi return the lifted weight unchanged at one rep, and it holds
        // exactly rather than to within an ulp because ln 1 and e^0 are both exact.
        for exponent in stride(from: -5.0, through: 5.0, by: 0.1) {
            #expect(RealMath.power(1, exponent: exponent) == 1.0)
        }
    }

    @Test("Anything to the power of zero is exactly one")
    func anythingToTheZeroIsExactlyOne() {
        for base in [0.5, 1.0, 2.0, 10.0, 1e100] {
            #expect(RealMath.power(base, exponent: 0) == 1.0)
        }
    }

    @Test("A base of zero or below has no real value above zero")
    func undefinedBases() {
        #expect(RealMath.power(0, exponent: 0.1) == 0)
        #expect(RealMath.power(-2, exponent: 0.1).isNaN)
        // Even a whole exponent: this function reduces through a logarithm and has no way to know
        // the exponent is whole, so it does not pretend to.
        #expect(RealMath.power(-2, exponent: 2).isNaN)
    }
}
