/// A prescription resolved against a context: the weight, and how it loads (`TR-0.2.11`).
public struct ResolvedPrescription: Sendable, Hashable {
    /// The weight to put on the bar.
    public let target: Weight

    /// What ``PrescriptionContext/plates`` makes of ``target``, for `FR-1.4.1` and `FR-1.4.4`.
    ///
    /// **Descriptive only.** ``target`` is already decided when this is computed, so a
    /// ``PlateLoadingResult/nearest(below:above:)`` here reports a target the profile cannot load
    /// rather than replacing it with one it can.
    ///
    /// `nil` in two cases: the context carries no equipment profile, or the prescription is
    /// ``Prescription/bodyweight(added:)``, whose added load hangs from a belt or a band — a loading
    /// would describe a bar and two collars that are not there.
    public let loading: PlateLoadingResult?

    /// Creates a resolved prescription. The relationship between the two — that ``loading`` is
    /// ``target``'s and not some other weight's — is ``PrescriptionResolver``'s guarantee.
    public init(target: Weight, loading: PlateLoadingResult? = nil) {
        self.target = target
        self.loading = loading
    }
}

/// What a ``Prescription`` resolves to in a given context (`TR-0.2.11`, `FR-2.3.5`).
///
/// Three cases rather than an optional, because "no load" and "no answer" are different facts and
/// a zero is neither.
public enum PrescriptionResolution: Sendable, Hashable {
    /// The prescription names a weight, and this is it.
    case resolved(ResolvedPrescription)

    /// The prescription is complete and names no load: the lifter picks the weight.
    ///
    /// ``Prescription/amrap`` alone. Not a refusal — nothing is missing, so `FR-2.3.5`'s prompt for
    /// it would have nothing to ask the user for, and filing it as one would put a permanent error
    /// state on a valid program row.
    case unspecifiedLoad

    /// It does not resolve, and this is what stopped it (`FR-2.3.5`).
    case unresolvable(PrescriptionUnresolvedReason)
}

/// Why a prescription could not be resolved (`FR-2.3.5`).
///
/// Each case is a different sentence on screen: a missing input names what to supply, an impossible
/// one names the value that was impossible. Values reach here rather than being rejected earlier
/// because ``Prescription`` validates nothing at construction — an enum case cannot be failable, and
/// a percentage or an RPE is only meaningless in the presence of the thing it is a percentage *of*.
public enum PrescriptionUnresolvedReason: Sendable, Hashable {
    /// ``Prescription/percentOfTrainingMax(percentage:)`` with no training max configured or none
    /// resolvable.
    case noTrainingMax

    /// ``Prescription/percentOfE1RM(percentage:)`` or ``Prescription/rpeTarget(rpe:)`` with no
    /// estimate — no qualifying set has been logged for the exercise.
    case noEstimatedOneRepMax

    /// ``Prescription/percentOfTopSet(percentage:)`` before a top set exists in this session.
    case noTopSet

    /// ``Prescription/previousPlusIncrement(_:)`` with no earlier performance of the slot.
    case noPreviousPerformance

    /// ``Prescription/rpeTarget(rpe:)`` with no rep count in the context — a slot carrying a rep
    /// *range* has to collapse it to one before resolving.
    case noRepCount

    /// A percentage of a negative weight, which is assisted work rather than a load to scale.
    ///
    /// 80% of 20 kg of assistance is 16 kg of assistance — a backoff set that comes out *harder*
    /// than the set it backs off from. The boundary is `< 0`, matching ``E1RMCalculator``'s and
    /// ``TrainingMaxUnresolvedReason/negativeSourceWeight(_:)``'s, so the module has one sign rule.
    /// ``Prescription/previousPlusIncrement(_:)`` deliberately does not meet it: an absolute step
    /// keeps its direction on a negative load, so adding 2.5 kg to 20 kg of assistance is genuine
    /// progression.
    case negativeBasis(Weight)

    /// The percentage is not finite, or is not greater than zero.
    ///
    /// Uncapped above: 110% of a training max is a peaking block, not an error. Matches
    /// ``TrainingMaxConfiguration/percentage``'s bound, which is checked at construction because a
    /// configuration has somewhere to reject it.
    case percentageOutOfRange(Double)

    /// The RPE falls outside ``SetRecord/rpeRange``, or is not a number.
    case rpeOutOfRange(Double)

    /// The rep count falls outside the rep axis of the resolver's chart, so no cell can apply.
    ///
    /// Distinct from ``effortOffTheChart(reps:rpe:)``: this one is fixed by editing the slot's reps,
    /// that one by editing the RPE.
    case repCountOutOfRange(Int)

    /// Reps and RPE are both legal and the chart still has no cell for them, because reps plus reps
    /// in reserve falls past its extent.
    case effortOffTheChart(reps: Int, rpe: Double)

    /// The weight does not fit in `Int` grams. Needs an absurd basis, percentage or increment.
    case notRepresentable

    /// A prescription written by a newer version, named by the raw type it arrived as.
    ///
    /// The `kind` is passed on so the UI can say *which* prescription it cannot handle. Nothing
    /// looks inside the preserved payload or at the schema version it came under: guessing at a
    /// newer version's fields is the corruption `NFR-2.3` exists to avoid.
    case unrecognisedPrescription(kind: String)
}
