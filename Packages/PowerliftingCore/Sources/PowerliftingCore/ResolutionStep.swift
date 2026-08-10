/// One operation in a resolution chain: what it started from, what it did, and what came out
/// (`TR-0.2.12`).
///
/// **Only operations that were actually performed appear.** A prescription carrying a weight
/// somebody typed emits no ``rounded(_:from:to:)`` step because no rule was applied to it, and a
/// context with no equipment profile emits no ``loaded(_:as:)``. A step describing an operation the
/// resolver did not run is the same dishonesty `G-1.6` protects a logged set from. That is why this
/// is an enum over operations rather than a record of source, operation and result: no payload here
/// can mean "not applicable".
public enum ResolutionStep: Sendable, Hashable {
    /// The weight a chain starts from, and where it was read from.
    case basis(ResolutionBasis, Weight)

    /// A factor applied to a weight, with the whole-gram product it landed on.
    ///
    /// In a step either resolver produced the factor is finite and above zero: a percentage is
    /// guarded before it is applied, and a chart fraction is validated when the chart is built. So —
    /// unlike a refusal, which is handed the value a user typed — no step in a real trace carries a
    /// `NaN`, and such a trace equals itself. That is a resolver's guarantee rather than this type's;
    /// nothing stops a hand-built step holding one.
    case scaled(by: Double, from: Weight, to: Weight)

    /// An RPE target read off the chart: the effort asked for, the reps-to-failure key it collapses
    /// to, and the fraction of a maximum found there.
    ///
    /// The one step no other case has, and it yields no weight: the fraction *is* the factor that
    /// the ``scaled(by:from:to:)`` step after it applies.
    case effort(reps: Int, rpe: Double, repsToFailure: Double, fractionOfMax: Double)

    /// A signed step added to a weight. Negative is a configured deload.
    case incremented(by: Weight, from: Weight, to: Weight)

    /// A weight snapped to a rounding rule.
    ///
    /// A full chain holds **two** of these — one where the training max was rounded and one where
    /// the percentage of it was — and they are different operations. Collapsing them leaves a small
    /// discrepancy with nothing to explain it.
    case rounded(RoundingRule, from: Weight, to: Weight)

    /// What an equipment profile makes of an already-decided target.
    ///
    /// Descriptive, and always last: it reports what will go on the bar rather than changing the
    /// number, so it produces no weight of its own. This is the same value
    /// ``ResolvedPrescription/loading`` holds — placed twice by one line, never computed twice.
    case loaded(Weight, as: PlateLoadingResult)

    /// The weight the chain stands at after this step, or `nil` for the two steps that produce none.
    ///
    /// What makes a trace checkable as a chain rather than a list: every step that consumes a weight
    /// consumes the last one produced.
    public var resultingWeight: Weight? {
        switch self {
        case .basis(_, let weight): weight
        case .scaled(_, _, let product): product
        case .effort: nil
        case .incremented(_, _, let sum): sum
        case .rounded(_, _, let snapped): snapped
        case .loaded: nil
        }
    }
}

/// Where the weight at the head of a chain came from (`TR-0.2.12`).
///
/// **Two cases name an estimated one-rep maximum, and the difference between them is a boundary
/// rather than a duplication.** ``bestEstimatedOneRepMax(formula:)`` was computed from a set
/// collection, so it can name the formula that produced it; ``estimatedOneRepMax`` arrived already
/// resolved, and nothing on that side of the boundary knows which formula it came from.
///
/// A basis names the number's origin, not the set behind it. `FR-2.3.4`'s chain begins at the
/// estimate, and this package has no set identity to offer in any case (`NFR-0.2`).
public enum ResolutionBasis: Sendable, Hashable {
    /// The heaviest estimate a set collection yielded, under the formula named.
    case bestEstimatedOneRepMax(formula: E1RMFormulaID)

    /// The heaviest completed working set at N or more reps — a weight somebody lifted, so there is
    /// no formula to name.
    case repMax(reps: Int)

    /// A resolved training max. Its own chain precedes this one and is ``TrainingMaxResolver``'s.
    case trainingMax

    /// An estimated one-rep maximum supplied already resolved.
    case estimatedOneRepMax

    /// The heaviest set worked up to in the session being logged.
    case topSet

    /// The load logged for the slot the last time it was performed.
    case previousPerformance

    /// A weight the program states outright: a fixed load, or a manually entered training max.
    ///
    /// One case for both, because it is one fact — a number nobody derived, which is why neither
    /// goes through a percentage or a rounding rule.
    case entered

    /// The external load a bodyweight prescription adds, which is what a set records.
    ///
    /// Distinct from ``entered``: nothing is loaded on it, so no chain from here reaches a bar.
    case bodyweightLoad
}
