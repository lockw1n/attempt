/// A published equation that estimates a one-rep maximum from a logged set (`TR-0.2.4`).
///
/// **Formulas are dumb on purpose.** A conformance answers exactly one question — *given what this
/// set was, what 1RM does my equation predict?* — and answers `nil` when its own equation has
/// nothing to say. It does **not** decide whether the set should have been asked about at all:
/// warmups and incomplete sets are filtered by `E1RMCalculator` (`TR-0.2.5`, T-0.16), which is
/// where the requirement puts them. A formula that quietly refused warmups would make two of that
/// calculator's three documented `nil` cases untestable, because they could no longer be
/// distinguished from the formula declining.
///
/// **Why the input is a whole ``SetRecord`` rather than a weight and a rep count.** `TR-0.2.4`
/// lists a sixth implementation, `RPEBased` (T-0.15), which reads ``SetRecord/rpe`` and
/// ``SetRecord/rir``. A protocol taking only weight and reps could not express it. The five
/// closed-form equations that ignore everything but weight and reps say so by conforming to
/// ``RepOnlyE1RMFormula`` instead, which is where the friendlier entry point lives.
///
/// **Every conformance is `Sendable`, declared explicitly.** Implicit synthesis does not reach a
/// `public` type, and an omitted conformance on a leaf type compiles here and fails only at the
/// first consumer (`TR-0.1.3`).
public protocol E1RMFormula: Sendable {
    /// The formula's stable persisted name (`TR-0.3.8`). See ``E1RMFormulaID``.
    var id: E1RMFormulaID { get }

    /// The rep counts this formula will produce an estimate for.
    ///
    /// Declared per conformance rather than shared, because nothing guarantees two published
    /// equations were fitted over the same range — see ``E1RMFormulaID/tabulatedRepRange`` for why
    /// these five nonetheless agree on `1...10`. ``estimate(for:)`` returns `nil` outside it, which
    /// is the behaviour `TR-0.2.5` requires of the calculator.
    var validRepRange: ClosedRange<Int> { get }

    /// The estimated one-rep maximum for `set`, or `nil` if this formula cannot produce one.
    ///
    /// - Parameter set: The logged set. ``SetRecord/isWarmup`` and ``SetRecord/isCompleted`` are
    ///   deliberately **not** consulted; see the type's note.
    /// - Returns: The estimate, rounded to the nearest whole gram, or `nil` when
    ///   ``SetRecord/reps`` falls outside ``validRepRange`` or the result will not fit in a
    ///   `Weight`.
    func estimate(for set: SetRecord) -> Weight?
}

/// An ``E1RMFormula`` whose prediction is the lifted weight multiplied by a factor that depends
/// only on the rep count.
///
/// All five of `TR-0.2.4`'s closed-form equations have this shape, and saying so buys three things
/// a bare ``E1RMFormula`` conformance would not.
///
/// *The range guard cannot be forgotten.* It is applied once, in ``estimate(weight:reps:)`` below,
/// rather than copied into five implementations where the sixth would omit it. That is not
/// hypothetical tidiness: Brzycki's equation divides by `37 − reps`, and this arrangement makes
/// reaching that division with `reps == 37` structurally impossible rather than merely tested.
///
/// *A set is not needed to ask the question.* ``SetRecord`` requires `isWarmup` and `isCompleted`
/// at every call site with no defaults, on purpose (`G-1.8`) — so a caller that has a weight and a
/// rep count but no logged set, such as T-0.19's training-max arithmetic, would otherwise have to
/// fabricate one. Making that awkward is how a default argument eventually gets added to
/// ``SetRecord``, which is the exact thing `G-1.8` cannot afford.
///
/// *The published percentage tables become directly assertable*, since ``multiplier(forReps:)`` is
/// the reciprocal of the %1RM figure each source tabulates.
public protocol RepOnlyE1RMFormula: E1RMFormula {
    /// The published equation's multiplier: estimated 1RM ÷ the weight lifted.
    ///
    /// Dimensionless — a ratio, not a mass — which is why it may be a `Double` in a module where
    /// weights may not be (`G-1.1`, `TR-0.2.1`). The reciprocal of the percent-of-1RM figure these
    /// equations are usually published as, so 1.333 here is the same statement as "75%".
    ///
    /// **Unguarded.** This is the raw equation, evaluated wherever it is asked, so a rep count
    /// outside ``E1RMFormula/validRepRange`` can return a meaningless, infinite or negative factor
    /// — Brzycki at 37 reps is `+∞` and at 38 is negative. ``estimate(weight:reps:)`` is the
    /// guarded entry point and the one callers should use; this exists so the equation itself can
    /// be tested against its source.
    ///
    /// - Parameter reps: A rep count. Meaningful only within ``E1RMFormula/validRepRange``.
    /// - Returns: The multiplier. See the note above for what happens outside the range.
    func multiplier(forReps reps: Int) -> Double
}

extension RepOnlyE1RMFormula {
    /// The estimated one-rep maximum for a lift of `weight` for `reps` reps.
    ///
    /// The `Double` arithmetic each equation needs stays inside this call: the multiplier is
    /// applied to the stored grams and the product is rounded straight back to whole grams, so no
    /// floating-point mass is ever handed out or stored (`G-1.1`). Rounding is `.nearest` and is
    /// **not** configurable — a whole gram is the storage resolution, not a display or loading
    /// choice, so there is nothing here for a caller to decide. Rounding to a weight that can
    /// actually be loaded is a different question, answered by ``RoundingRule``, and applying it
    /// to an e1RM would be a category error: nobody loads an estimate.
    ///
    /// - Parameters:
    ///   - weight: The load lifted, on one implement — see ``SetRecord/weight``. May be negative;
    ///     see the note on ``estimate(for:)`` about what that means.
    ///   - reps: Reps performed.
    /// - Returns: The estimate, or `nil` if `reps` falls outside ``E1RMFormula/validRepRange`` or
    ///   the product will not fit in a `Weight`.
    public func estimate(weight: Weight, reps: Int) -> Weight? {
        guard validRepRange.contains(reps) else { return nil }
        return weight.scaled(by: multiplier(forReps: reps))
    }

    /// The estimated one-rep maximum for `set`, read from its weight and reps alone.
    ///
    /// **A negative ``SetRecord/weight`` produces an estimate that is arithmetically consistent and
    /// physically backwards, and no formula here corrects it.** Assisted bodyweight work stores a
    /// negative added load — a banded pull-up (`TR-0.2.3`, T-0.12) — and every one of these
    /// equations is linear in weight, so a multiplier above 1 makes that number *more* negative:
    /// more assistance, which is easier, presented as a heavier one-rep maximum. Guarding against
    /// it here would be this task inventing a domain rule no requirement states, and `TR-0.2.5`
    /// puts input filtering on the calculator rather than the formula. Recorded instead as an
    /// obligation on T-0.16 and T-0.18, whose task files carry it — a personal record computed
    /// from assisted sets is the place it would actually mislead someone.
    ///
    /// - Parameter set: The logged set.
    /// - Returns: See ``estimate(weight:reps:)``.
    public func estimate(for set: SetRecord) -> Weight? {
        estimate(weight: set.weight, reps: set.reps)
    }
}

extension Weight {
    /// This mass multiplied by a dimensionless factor, rounded to the nearest whole gram.
    ///
    /// Internal, and deliberately so: it is the one place a formula's `Double` result crosses back
    /// into grams, and a public version would be an invitation to scale weights by floating-point
    /// factors in call sites that have no business doing so (`G-1.1`). ``RoundingStrategy/nearest``
    /// is not a parameter for the reason given on ``RepOnlyE1RMFormula/estimate(weight:reps:)``.
    ///
    /// - Parameter factor: Any `Double`.
    /// - Returns: The scaled mass, or `nil` if the product is not finite or does not fit in `Int`
    ///   grams. Both are unreachable from a plausible lift and reachable from an absurd rep count,
    ///   which is why this is failable rather than trapping.
    func scaled(by factor: Double) -> Weight? {
        guard let scaled = RoundingStrategy.nearest.roundedToInt(Double(grams) * factor) else {
            return nil
        }
        return Weight(grams: scaled)
    }
}
