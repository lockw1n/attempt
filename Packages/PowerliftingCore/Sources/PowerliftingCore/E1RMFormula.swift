/// A published equation that estimates a one-rep maximum from a logged set (`TR-0.2.4`).
///
/// **Formulas are dumb on purpose.** A conformance answers only *what 1RM does my equation predict
/// for this set?*, and `nil` when its equation has nothing to say. It does **not** decide whether
/// the set should have been asked about: warmups and incomplete sets are filtered by
/// `E1RMCalculator` (`TR-0.2.5`), and a formula that refused them would make that calculator's
/// `nil` cases indistinguishable from a formula declining.
///
/// The input is a whole ``SetRecord`` rather than a weight and rep count because `TR-0.2.4`'s
/// sixth implementation, `RPEBased`, reads ``SetRecord/rpe`` and ``SetRecord/rir``. The five
/// closed-form equations say they ignore all that by conforming to ``RepOnlyE1RMFormula``.
public protocol E1RMFormula: Sendable {
    /// The formula's stable persisted name (`TR-0.3.8`). See ``E1RMFormulaID``.
    var id: E1RMFormulaID { get }

    /// The rep counts this formula will produce an estimate for.
    ///
    /// Per conformance rather than shared: nothing guarantees two published equations were fitted
    /// over the same range. ``estimate(for:)`` returns `nil` outside it.
    var validRepRange: ClosedRange<Int> { get }

    /// The estimated one-rep maximum for `set`, or `nil` if this formula cannot produce one.
    ///
    /// - Parameter set: The logged set. ``SetRecord/isWarmup`` and ``SetRecord/isCompleted`` are
    ///   deliberately **not** consulted; see the type's note.
    /// - Returns: The estimate in whole grams, or `nil` when ``SetRecord/reps`` falls outside
    ///   ``validRepRange`` or the result will not fit in a `Weight`.
    func estimate(for set: SetRecord) -> Weight?
}

/// An ``E1RMFormula`` whose prediction is the lifted weight times a factor depending only on reps.
///
/// All five of `TR-0.2.4`'s closed-form equations have this shape. Saying so applies the range
/// guard once, in ``estimate(weight:reps:)``, rather than in five implementations where a sixth
/// would omit it — Brzycki divides by `37 − reps`, so this makes reaching that division at
/// `reps == 37` structurally impossible rather than merely tested.
///
/// It also lets a caller with a weight and a rep count but no logged set (training-max arithmetic)
/// ask without fabricating a ``SetRecord``, which is how a default argument would eventually get
/// added to one — the exact thing `G-1.8` cannot afford.
public protocol RepOnlyE1RMFormula: E1RMFormula {
    /// The published equation's multiplier: estimated 1RM ÷ the weight lifted.
    ///
    /// Dimensionless — a ratio, not a mass — which is why it is a `Double` in a module where
    /// weights may not be (`G-1.1`). It is the reciprocal of the percent-of-1RM figure these
    /// equations are usually published as, so 1.333 here is the same statement as "75%".
    ///
    /// **Unguarded.** The raw equation, evaluated wherever asked, so a rep count outside
    /// ``E1RMFormula/validRepRange`` can return a meaningless, infinite or negative factor —
    /// Brzycki at 37 reps is `+∞`, at 38 negative. Use ``estimate(weight:reps:)``; this exists so
    /// the equation itself can be tested against its source.
    func multiplier(forReps reps: Int) -> Double
}

extension RepOnlyE1RMFormula {
    /// The estimated one-rep maximum for a lift of `weight` for `reps` reps.
    ///
    /// The `Double` arithmetic stays inside this call: the multiplier is applied to stored grams
    /// and rounded straight back, so no floating-point mass is handed out or stored (`G-1.1`).
    /// Rounding is `.nearest` and **not** configurable — a whole gram is the storage resolution,
    /// not a display choice. Rounding to a loadable weight is ``RoundingRule``'s job, and applying
    /// it here would be a category error: nobody loads an estimate.
    ///
    /// - Parameter weight: The load lifted, on one implement — see ``SetRecord/weight``. May be
    ///   negative; see ``estimate(for:)``.
    /// - Returns: The estimate, or `nil` if `reps` falls outside ``E1RMFormula/validRepRange`` or
    ///   the product will not fit in a `Weight`.
    public func estimate(weight: Weight, reps: Int) -> Weight? {
        guard validRepRange.contains(reps) else { return nil }
        return weight.scaled(by: multiplier(forReps: reps))
    }

    /// The estimated one-rep maximum for `set`, read from its weight and reps alone.
    ///
    /// **A negative ``SetRecord/weight`` gives an estimate that is arithmetically consistent and
    /// physically backwards, uncorrected.** Assisted work stores a negative added load, and these
    /// equations are linear in weight, so a multiplier above 1 makes it *more* negative: more
    /// assistance presented as a heavier maximum. `TR-0.2.5` puts input filtering on the
    /// calculator, not the formula, so guarding here would invent a domain rule no requirement
    /// states.
    public func estimate(for set: SetRecord) -> Weight? {
        estimate(weight: set.weight, reps: set.reps)
    }
}

extension Weight {
    /// This mass multiplied by a dimensionless factor, rounded to the nearest whole gram.
    ///
    /// Internal on purpose: it is the one place a formula's `Double` result crosses back into
    /// grams, and a public version would invite scaling weights by floating-point factors at call
    /// sites with no business doing so (`G-1.1`).
    ///
    /// - Returns: The scaled mass, or `nil` if the product is not finite or does not fit in `Int`
    ///   grams — unreachable from a plausible lift, reachable from an absurd rep count.
    func scaled(by factor: Double) -> Weight? {
        guard let scaled = RoundingStrategy.nearest.roundedToInt(Double(grams) * factor) else {
            return nil
        }
        return Weight(grams: scaled)
    }
}
