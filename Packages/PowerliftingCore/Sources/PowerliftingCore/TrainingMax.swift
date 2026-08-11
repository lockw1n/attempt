/// A resolved training max: the weight prescriptions are computed from (`TR-0.2.9`).
///
/// Derived, never stored as truth (`G-1.4`) — `TR-0.3.6` persists the *configuration* and this is
/// recomputed, which is what lets a newly logged set move it (`FR-2.3.1`).
public struct TrainingMax: Sendable, Hashable {
    /// The training max itself, after the percentage and the rounding rule.
    public let weight: Weight

    /// The weight the percentage was applied to — the estimate, the rep max, or the entered value.
    ///
    /// The one number a caller cannot recover from the configuration, since a derived source is
    /// read from the set collection rather than stored; `FR-1.5.1.7`'s "e1RM has moved more than a
    /// threshold from the training max" is the comparison it exists for.
    ///
    /// In a value ``TrainingMaxResolver/resolve(_:from:)`` produced this is non-negative, and it
    /// equals ``weight`` exactly when the source was manual — that source bypassing both steps
    /// rather than a coincidence. Both are the resolver's guarantees and not this type's: the
    /// initialiser takes any two weights, because nothing in the module consumes a hand-built
    /// training max and a failable initialiser here would buy a boundary no caller crosses.
    public let sourceWeight: Weight

    /// Creates a training max.
    public init(weight: Weight, sourceWeight: Weight) {
        self.weight = weight
        self.sourceWeight = sourceWeight
    }
}

/// What a configuration resolves to, given a set collection (`TR-0.2.9`, `FR-2.3.5`).
///
/// A two-case enum rather than an optional because `FR-2.3.5` needs the *reason*, and because a
/// training max of zero and no training max at all are different answers — a zero returned as a
/// sentinel becomes an untraceable prescription several phases downstream.
public enum TrainingMaxResolution: Sendable, Hashable {
    /// The configuration resolved.
    case resolved(TrainingMax)

    /// It did not, and this is what was missing.
    case unresolvable(TrainingMaxUnresolvedReason)
}

/// Why a training max could not be resolved (`FR-2.3.5`).
public enum TrainingMaxUnresolvedReason: Sendable, Hashable {
    /// No set in the collection produced a source weight.
    ///
    /// For ``TrainingMaxSource/percentOfE1RM`` every set was refused by ``E1RMCalculator`` or
    /// declined by the formula; for ``TrainingMaxSource/percentOfRepMax(reps:)`` no completed
    /// working set reached that many reps.
    case noSourceData

    /// The configured N is outside ``PersonalRecords/repRange``, so no rep max is computed for it.
    ///
    /// Distinct from ``noSourceData`` deliberately: "you have never done a set of eight" and "eight
    /// is not a rep count this version computes" call for different words on screen, and
    /// ``PersonalRecordCalculator/repMax(forReps:in:)`` answers `nil` to both.
    case repCountOutOfRange(Int)

    /// The source weight is negative, so it is assisted work rather than a load to prescribe from.
    ///
    /// A negative N-rep max is legitimate data and is ranked correctly as a record; a percentage of
    /// it is a negative prescribed weight in every future session. The refusal belongs where a
    /// record becomes a training max, not to the record. No requirement states it.
    ///
    /// The boundary is `< 0`, matching ``E1RMCalculator``'s. Zero resolves — useless but not
    /// backwards, and it stays distinguishable from ``TrainingMaxResolution/unresolvable(_:)``.
    case negativeSourceWeight(Weight)

    /// The scaled weight does not fit in `Int` grams. Needs an absurd source weight or percentage.
    case notRepresentable
}
