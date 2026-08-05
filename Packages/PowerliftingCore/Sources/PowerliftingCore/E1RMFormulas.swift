// The five closed-form e1RM equations `TR-0.2.4` names.
//
// Each carries its published form and primary source so the implementation can be read against
// the citation. The forms are those collated by LeSuer, McCormick, Mayhew, Wasserstein & Arnold
// (1997), Journal of Strength and Conditioning Research 11(4): 211–213, which put all five side by
// side.
//
// All five are `weight × f(reps)`, so they conform to `RepOnlyE1RMFormula` and supply only
// `multiplier(forReps:)`. The rep-range guard, gram rounding and overflow check live once, in that
// protocol's extension.

/// Epley's equation (1985): `1RM = weight · (1 + reps / 30)`.
///
/// Boyd Epley, *Poundage Chart*, Boyd Epley Workout, Lincoln NE: Body Enterprises, 1985.
///
/// **At one rep it returns 1.0333 × the weight, not the weight** — the equation, not a defect. It
/// is a straight line fitted to multi-rep work, so extended down to a single rep it misses the
/// point it "should" pass through. Not smoothed over.
public struct Epley: RepOnlyE1RMFormula {
    public let id = E1RMFormulaID.epley
    public let validRepRange = E1RMFormulaID.tabulatedRepRange

    /// Creates the formula; it holds no state.
    public init() {}

    /// `1 + reps / 30`. See ``RepOnlyE1RMFormula/multiplier(forReps:)`` on the unguarded contract.
    public func multiplier(forReps reps: Int) -> Double {
        1 + Double(reps) / 30
    }
}

/// Brzycki's equation (1993): `1RM = weight · 36 / (37 − reps)`.
///
/// Matt Brzycki, "Strength Testing — Predicting a One-Rep Max from Reps-to-Fatigue",
/// *Journal of Physical Education, Recreation & Dance* 64(1): 88–90, 1993.
///
/// **At one rep it returns the weight exactly** — `36 / 36` — being a percentage table anchored at
/// 100% for a single rep, falling by exactly 1/36 per rep.
///
/// **It has a genuine singularity at 37 reps and goes negative above it.** That is far outside
/// ``E1RMFormula/validRepRange``, so ``RepOnlyE1RMFormula/estimate(weight:reps:)`` can never reach
/// the division; the guard living in the protocol extension rather than here is what makes that
/// structural. ``multiplier(forReps:)`` is unguarded by contract and returns `+∞` there.
public struct Brzycki: RepOnlyE1RMFormula {
    public let id = E1RMFormulaID.brzycki
    public let validRepRange = E1RMFormulaID.tabulatedRepRange

    /// Creates the formula; it holds no state.
    public init() {}

    /// `36 / (37 − reps)`. Singular at 37 — see the type's note, and
    /// ``RepOnlyE1RMFormula/multiplier(forReps:)`` on the unguarded contract.
    public func multiplier(forReps reps: Int) -> Double {
        36 / (37 - Double(reps))
    }
}

/// Lombardi's equation (1989): `1RM = weight · reps^0.10`.
///
/// V. Patteson Lombardi, *Beginning Weight Training: The Safe and Effective Way*,
/// Dubuque IA: Wm. C. Brown, 1989.
///
/// **At one rep it returns the weight exactly** — and exactly, not to within an ulp, because
/// ``RealMath/logarithm(_:)`` returns a hard zero for 1 and ``RealMath/exponential(_:)`` a hard one
/// for zero.
///
/// The only power law of the five, and the flattest. Staying finite where ``Brzycki`` diverges is
/// not a reason to trust it further out. One of two equations needing a transcendental function in
/// a module that imports nothing — see ``RealMath``.
public struct Lombardi: RepOnlyE1RMFormula {
    public let id = E1RMFormulaID.lombardi
    public let validRepRange = E1RMFormulaID.tabulatedRepRange

    /// The exponent Lombardi's equation raises the rep count to.
    private static let exponent = 0.10

    /// Creates the formula; it holds no state.
    public init() {}

    /// `reps^0.10`. Zero at zero reps, which is one of the two reasons
    /// ``E1RMFormulaID/tabulatedRepRange`` starts at 1. See
    /// ``RepOnlyE1RMFormula/multiplier(forReps:)`` on the unguarded contract.
    public func multiplier(forReps reps: Int) -> Double {
        RealMath.power(Double(reps), exponent: Self.exponent)
    }
}

/// O'Conner's equation (1989): `1RM = weight · (1 + 0.025 · reps)`.
///
/// B. O'Conner, J. Simmons and P. O'Shea, *Weight Training Today*,
/// St. Paul MN: West Publishing, 1989.
///
/// **At one rep it returns 1.025 × the weight**, for the same reason ``Epley`` does not return the
/// input. The two differ only in slope — 1/30 per rep against 1/40 — so this is the more
/// conservative of the pair.
public struct OConner: RepOnlyE1RMFormula {
    public let id = E1RMFormulaID.oConner
    public let validRepRange = E1RMFormulaID.tabulatedRepRange

    /// Creates the formula; it holds no state.
    public init() {}

    /// `1 + 0.025 · reps`. See ``RepOnlyE1RMFormula/multiplier(forReps:)`` on the unguarded
    /// contract.
    public func multiplier(forReps reps: Int) -> Double {
        1 + 0.025 * Double(reps)
    }
}

/// Wathan's equation (1994): `1RM = 100 · weight / (48.8 + 53.8 · e^(−0.075 · reps))`.
///
/// Dan Wathan, "Load Assignment", in Thomas R. Baechle (ed.), *Essentials of Strength Training and
/// Conditioning*, 1st ed., Champaign IL: Human Kinetics, 1994, pp. 435–446.
///
/// **At one rep it returns 1.0130 × the weight** — closer to the input than ``Epley`` or
/// ``OConner`` but not equal, the exponential being asymptotic.
///
/// The only **bounded** one of the five: as reps grow the multiplier approaches `100 / 48.8`. That
/// is a statement about arithmetic, not accuracy. The second equation needing ``RealMath``.
public struct Wathan: RepOnlyE1RMFormula {
    public let id = E1RMFormulaID.wathan
    public let validRepRange = E1RMFormulaID.tabulatedRepRange

    /// The three constants of Wathan's regression, named so the equation below reads as its source.
    private static let asymptote = 48.8
    private static let amplitude = 53.8
    private static let decay = -0.075

    /// Creates the formula; it holds no state.
    public init() {}

    /// `100 / (48.8 + 53.8 · e^(−0.075 · reps))`. Never singular — the denominator is bounded
    /// below by 48.8 — so unlike ``Brzycki`` this one is well defined everywhere. See
    /// ``RepOnlyE1RMFormula/multiplier(forReps:)`` on the unguarded contract.
    public func multiplier(forReps reps: Int) -> Double {
        100 / (Self.asymptote + Self.amplitude * RealMath.exponential(Self.decay * Double(reps)))
    }
}
