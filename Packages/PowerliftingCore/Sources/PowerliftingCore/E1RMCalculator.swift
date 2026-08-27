/// The estimated one-rep maximum for a logged set, under a chosen formula (`TR-0.2.5`).
///
/// **This is the filter; a formula is only the arithmetic.** A conformance of ``E1RMFormula``
/// answers what its equation predicts and nothing else, so every judgement about whether a set
/// should have been asked about lives here. A formula that quietly declined a warmup would make
/// two of the refusals below indistinguishable from its equation having nothing to say.
///
/// **A negative ``SetRecord/weight`` is refused, and that is a domain decision rather than a range
/// check.** Assisted bodyweight work stores a negative *added* load, and every equation is linear
/// in weight, so a multiplier above 1 makes the estimate more negative: more assistance — an easier
/// set — reported as a heavier maximum. Refusing it here is what stops `TR-0.2.8`'s cached personal
/// records ranking the most-assisted attempt highest, and it fixes the sign question once for every
/// caller rather than in each of them. Zero is allowed: an unweighted set estimates as zero, which
/// is useless but not backwards.
///
/// **Nothing is stored or cached** (`G-1.4`). Every call recomputes, which is what makes changing
/// the formula recalculate history (`FR-1.7.3`) rather than only new sets.
public struct E1RMCalculator: Sendable {
    /// The formula this calculator reads.
    ///
    /// An existential because the choice is made at runtime — restored from a persisted setting
    /// (`TR-0.3.8`) and changeable afterwards (`FR-1.7.3`), so it cannot be a type parameter.
    public let formula: any E1RMFormula

    /// Creates a calculator reading `formula`.
    public init(formula: any E1RMFormula) {
        self.formula = formula
    }

    /// Creates a calculator reading the formula `id` names, or ``E1RMFormulaID/defaultFormula``.
    public init(_ id: E1RMFormulaID = .defaultFormula) {
        self.init(formula: id.formula)
    }

    /// The estimated one-rep maximum for `set`, or `nil` when the set says nothing about a maximum.
    ///
    /// - Parameter set: The logged set.
    /// - Returns: `nil` for any set ``outcome(for:)`` refuses; otherwise what the formula answered.
    public func estimate(for set: SetRecord) -> Weight? {
        guard case .estimate(let weight) = outcome(for: set) else { return nil }
        return weight
    }

    /// The estimate for `set`, or which of the four guards turned it away (`TR-0.2.5`,
    /// `FR-1.13.3`).
    ///
    /// **The guard chain has one home, and this is it.** A caller that has to explain the blank to
    /// a user needs the same chain ``estimate(for:)`` applies, and a second copy of it elsewhere is
    /// one that drifts — a refusal reported for a reason the calculator did not actually refuse for.
    ///
    /// The order is the answer where a set fails more than one guard: an assisted twelve-rep set is
    /// ``E1RMRefusal/assisted``, because that is the guard that stopped it.
    ///
    /// The rep-range guard is applied here as well as inside every formula, so the refusal
    /// `TR-0.2.5` names holds for any conformance rather than for the ones that remember.
    ///
    /// - Parameter set: The logged set.
    /// - Returns: What this calculator did with it.
    public func outcome(for set: SetRecord) -> E1RMOutcome {
        if set.isWarmup { return .refused(.warmup) }
        if !set.isCompleted { return .refused(.incomplete) }
        if set.weight.grams < 0 { return .refused(.assisted) }
        if !formula.validRepRange.contains(set.reps) { return .refused(.repsOutOfRange) }
        guard let weight = formula.estimate(for: set) else { return .refused(.formulaDeclined) }
        return .estimate(weight)
    }
}

/// What ``E1RMCalculator/outcome(for:)`` made of a set.
public enum E1RMOutcome: Sendable, Hashable {
    /// The formula answered, and this is what it said.
    case estimate(Weight)

    /// It was never asked, or it declined — see ``E1RMRefusal``.
    case refused(E1RMRefusal)
}

/// Why a set produced no estimated one-rep maximum (`TR-0.2.5`).
///
/// **Not a stored vocabulary and deliberately not `Codable`.** Every case is recomputed from the
/// set in front of it, so there is no persisted value to meet again and no unknown case to resolve;
/// adding one is a copy change in the presentation layer rather than a migration.
///
/// Declared in the order ``E1RMCalculator/outcome(for:)`` applies them, which is what makes "the
/// first guard that stopped it" a statement about this type rather than about one call site.
public enum E1RMRefusal: Sendable, Hashable, CaseIterable, Comparable {
    /// A warmup. It was not an attempt at anything.
    case warmup

    /// Not completed — nothing says the load was actually lifted for the reps recorded.
    case incomplete

    /// Assisted work: a negative added load, which every equation would read as a heavier maximum
    /// the more assistance was used.
    case assisted

    /// More reps than the formula is tabulated over — see ``E1RMFormula/validRepRange``.
    case repsOutOfRange

    /// The formula itself had nothing to say: ``RPEBased`` over a set that recorded no effort.
    case formulaDeclined

    /// Ordered by how far the set got before it was turned away, so the greater of two is the
    /// **nearer miss**.
    ///
    /// That is what a caller explaining a blank over several sets wants: a lifter whose warmups sit
    /// beside one twelve-rep working set is owed the sentence about the rep range, not the one about
    /// warmups.
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.reached < rhs.reached
    }

    /// How many of ``E1RMCalculator/outcome(for:)``'s guards this case cleared.
    private var reached: Int {
        switch self {
        case .warmup: 0
        case .incomplete: 1
        case .assisted: 2
        case .repsOutOfRange: 3
        case .formulaDeclined: 4
        }
    }
}

extension E1RMFormulaID {
    /// The formula used when nobody has chosen one.
    ///
    /// Two roles deliberately sharing one value, so they cannot drift apart: the estimate a lifter
    /// sees before ever opening settings, and the formula a settings record falls back to when its
    /// persisted name cannot be read (`TR-0.3.8`). Refusing to invent a formula from an unknown name
    /// must not cost the whole record.
    ///
    /// ``epley`` rather than one of the others: it is arithmetic throughout, it has no singularity
    /// anywhere (``brzycki`` divides by `37 − reps`), and it is the most widely reproduced of the
    /// five, so its number is the one a lifter will have seen elsewhere. ``rpeBased`` is
    /// disqualified twice over — it answers `nil` for any set recording neither an RPE nor an RIR,
    /// which is most sets, and its chart is a transcription rather than a citation.
    public static let defaultFormula: E1RMFormulaID = .epley

    /// The implementation this name refers to.
    ///
    /// Exhaustive without a `default` arm on purpose: a case added without an implementation stops
    /// compiling here, which is what makes "a case exists only where an implementation does" a rule
    /// the compiler holds rather than a claim in a doc comment.
    public var formula: any E1RMFormula {
        switch self {
        case .epley: Epley()
        case .brzycki: Brzycki()
        case .lombardi: Lombardi()
        case .oConner: OConner()
        case .wathan: Wathan()
        case .rpeBased: RPEBased()
        }
    }
}
