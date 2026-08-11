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
    /// - Returns: `nil` for a warmup, for an incomplete set, for a negative ``SetRecord/weight``,
    ///   or for a rep count outside the formula's ``E1RMFormula/validRepRange``; otherwise whatever
    ///   the formula answers, which may itself be `nil` — ``RPEBased`` has nothing to say about a
    ///   set that recorded no effort.
    ///
    ///   The rep-range guard is applied here as well as inside every formula, so the refusal
    ///   `TR-0.2.5` names holds for any conformance rather than for the ones that remember.
    public func estimate(for set: SetRecord) -> Weight? {
        guard !set.isWarmup,
            set.isCompleted,
            set.weight.grams >= 0,
            formula.validRepRange.contains(set.reps)
        else {
            return nil
        }
        return formula.estimate(for: set)
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
