/// The two transcendental functions this module needs, implemented from the standard library alone.
///
/// **Why this file exists.** `TR-0.2.4`'s Lombardi (`weight · reps^0.10`) and Wathan
/// (`100·weight / (48.8 + 53.8·e^(−0.075·reps))`) need `pow` and `exp`. Neither is in scope in a
/// module that imports nothing: they live in the C math library, which reaches Swift only through
/// `Foundation`, `Darwin` or `Glibc`, and `NFR-0.2` forbids the first while the other two are the
/// same violation under another name. `swift-numerics` would supply them as a package dependency,
/// which `TR-0.1.1` and `G-5.1` rule out. **Reach for this file rather than an import.**
///
/// Accuracy against the system `libm` is recorded in `RealMathTests`, which is where the claim is
/// pinned — comfortably tighter than a whole-gram e1RM needs.
///
/// **Not public.** No requirement asks this module to publish a maths library, and a public `exp`
/// here would invite call sites that should be using `Weight` arithmetic instead.
enum RealMath {
    /// The natural logarithm of 2, written to more digits than a `Double` can hold so the literal
    /// rounds to the nearest representable value rather than to whatever was typed.
    static let ln2 = 0.693_147_180_559_945_309_417_232_121_458

    /// ``ln2`` split into a high part with 32 trailing zero mantissa bits and a low remainder.
    ///
    /// `exponential` subtracts `scale · ln2` from its argument, and for a large `scale` that
    /// cancels most of the significant digits. Splitting makes `scale · ln2Hi` exact, so only the
    /// tiny `ln2Lo` correction carries rounding error. It earns its keep only at the extremes — for
    /// the arguments the formulas use (|x| < 1) `scale` is zero and the split does nothing.
    static let ln2Hi = 0.693_147_180_369_123_816_490
    static let ln2Lo = 1.908_214_929_270_587_700_02e-10

    /// The square root of 2, used to centre ``logarithm(_:)``'s argument reduction. Computed rather
    /// than written out — `squareRoot()` is the one transcendental the standard library does hand
    /// over, which avoids a hand-typed digit string that nothing checks.
    static let squareRootOfTwo = 2.0.squareRoot()

    /// Euler's number raised to `value`.
    ///
    /// Argument reduction plus a Taylor series: `e^x = 2^k · e^r` where `k = round(x / ln 2)` and
    /// `r = x − k·ln 2`, which puts `|r| ≤ ln2/2 ≈ 0.347` where the series converges quickly. The
    /// `2^k` scaling is exact — it only adjusts the exponent field.
    ///
    /// - Returns: `e^value`. NaN for NaN, `+∞` on overflow, `0` on underflow, exactly `1` for `0`.
    ///   Matches `libm` bit for bit at both boundaries.
    static func exponential(_ value: Double) -> Double {
        if value.isNaN { return value }
        // Not just a shortcut: it pins e^0 == 1 exactly, which `power` relies on so that
        // `base^0` and `1^exponent` come back exact rather than one ulp away.
        if value == 0 { return 1 }
        // The largest and smallest arguments with a representable result. Beyond them the series
        // would still run but `Double(sign:exponent:significand:)` has nowhere to put the answer.
        if value > 709.782_712_893_384 { return .infinity }
        if value < -745.133_219_101_941_1 { return 0 }

        let scale = (value / ln2).rounded(.toNearestOrEven)
        let remainder = (value - scale * ln2Hi) - scale * ln2Lo

        // Horner's form of 1 + r/1!(…) + r^n/n!, accumulated from the tail. Seventeen terms: the
        // next one is below 4 × 10⁻²³ for the largest |r| this can see, so it cannot move the
        // result by even one ulp.
        var series = 1.0
        for term in stride(from: 17, through: 1, by: -1) {
            series = 1 + remainder * series / Double(term)
        }
        return Double(sign: .plus, exponent: Int(scale), significand: series)
    }

    /// The natural logarithm of `value`.
    ///
    /// `value` is split into `significand · 2^exponent` — free, since that is how a `Double` is
    /// stored — so `ln value = ln significand + exponent · ln 2`. The significand is nudged into
    /// `[√2/2, √2)` to keep the series argument small on both sides of 1, then the `atanh` series
    /// `ln m = 2(s + s³/3 + s⁵/5 + …)` with `s = (m−1)/(m+1)` does the rest. That series rather than
    /// Taylor's for `ln(1+x)`: `|s| ≤ 0.172` where `|x|` would reach 0.414, and only odd powers
    /// appear, so it converges about four times faster per term.
    ///
    /// - Parameter value: Any `Double`. Subnormal inputs are handled with no loss of accuracy,
    ///   because `Double.significand` normalises them.
    /// - Returns: `ln value`. NaN for NaN and for any negative input, `−∞` for `0`, `+∞` for `+∞`,
    ///   and exactly `0` for `1`.
    static func logarithm(_ value: Double) -> Double {
        if value.isNaN { return value }
        if value < 0 { return .nan }
        if value == 0 { return -.infinity }
        if value == .infinity { return value }

        var exponent = value.exponent
        var mantissa = value.significand
        if mantissa > squareRootOfTwo {
            mantissa /= 2
            exponent += 1
        }

        let sub = (mantissa - 1) / (mantissa + 1)
        let squared = sub * sub
        // Horner's form of 1/1 + s²/3 + s⁴/5 + …, accumulated from the tail. Thirteen odd terms:
        // s² ≤ 0.0295, so the next one is below 10⁻²⁰ relative to the leading 1.
        var series = 0.0
        for term in stride(from: 25, through: 1, by: -2) {
            series = 1 / Double(term) + squared * series
        }
        return 2 * sub * series + Double(exponent) * ln2
    }

    /// `base` raised to `exponent`, for a real (not necessarily whole) exponent.
    ///
    /// `b^e = e^(e · ln b)`, which is why this file only had to build two functions rather than
    /// three. Only Lombardi uses it, and only with a base of at least 1, so the awkward corners
    /// below are reachable from the tests alone.
    ///
    /// - Parameters:
    ///   - base: Must be positive for a real result. Zero gives zero; negative gives NaN — a
    ///     negative base raised to a fractional power has no real value, and this function cannot
    ///     know the exponent is whole.
    ///   - exponent: Any `Double`.
    /// - Returns: `base^exponent`, or NaN where that is undefined over the reals. Exactly `1` when
    ///   `base` is `1`.
    static func power(_ base: Double, exponent: Double) -> Double {
        exponential(exponent * logarithm(base))
    }
}
