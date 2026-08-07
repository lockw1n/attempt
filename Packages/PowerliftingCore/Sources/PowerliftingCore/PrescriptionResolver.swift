/// Resolves a ``Prescription`` against a ``PrescriptionContext`` (`TR-0.2.11`).
///
/// Pure and deterministic: the situation arrives in the context and the chart is this type's own
/// (see ``rpeTable``), so nothing is read from anywhere else — no clock, no locale, no storage.
/// A `Double` appears only as the factor and the multiply that consumes it, which returns to whole
/// grams immediately; no `Double` weight is stored, returned or compared.
///
/// **Which refusal wins when more than one applies**: the basis first, since there is nothing to
/// scale without it; then the value the prescription itself carries; then the rest of the context.
///
/// **The rounding rule applies exactly where a `Double` factor entered the arithmetic** — the three
/// percentage cases and ``Prescription/rpeTarget(rpe:)``. The three cases carrying a weight somebody
/// typed (``Prescription/fixedWeight(_:)``, ``Prescription/previousPlusIncrement(_:)``,
/// ``Prescription/bodyweight(added:)``) are returned untouched, the same way
/// ``TrainingMaxSource/manual(_:)`` bypasses its configuration's percentage and rule: a target the
/// program states outright must not display as a number the program does not contain. Derived is
/// rounded; entered is not.
///
/// **A percentage of a training max is two roundings from the estimate it came from**, one here and
/// one in ``TrainingMaxResolver``. Both are real steps and neither is redundant.
///
/// **Reps are not resolved here.** `TR-0.2.11` names a rep range in the output, but reps belong to
/// the slot (`FR-2.2.2`) and no prescription carries one — ``Prescription/amrap`` says so most
/// clearly by resolving to ``PrescriptionResolution/unspecifiedLoad``. What this produces is a load.
public struct PrescriptionResolver: Sendable {
    /// The RPE chart ``Prescription/rpeTarget(rpe:)`` is read off.
    ///
    /// A setting rather than situational data, so it sits here beside the resolver rather than in
    /// the context — the same place ``TrainingMaxResolver`` keeps its formula. It is the chart
    /// ``RPEBased`` estimates *from*, used in the other direction.
    public let rpeTable: RPETable

    /// Creates a resolver reading `rpeTable`, or the conventional chart if none is given.
    public init(rpeTable: RPETable = .standard) {
        self.rpeTable = rpeTable
    }

    /// The weight `prescription` prescribes in `context`, or what stopped it resolving.
    public func resolve(
        _ prescription: Prescription, in context: PrescriptionContext
    ) -> PrescriptionResolution {
        switch prescription {
        case .fixedWeight(let weight):
            resolved(weight, in: context)
        case .percentOfTrainingMax(let percentage):
            self.percentage(
                percentage, of: context.trainingMax?.weight, orMissing: .noTrainingMax, in: context)
        case .percentOfE1RM(let percentage):
            self.percentage(
                percentage,
                of: context.estimatedOneRepMax,
                orMissing: .noEstimatedOneRepMax,
                in: context)
        case .percentOfTopSet(let percentage):
            self.percentage(percentage, of: context.topSetWeight, orMissing: .noTopSet, in: context)
        case .rpeTarget(let rpe):
            rpeTarget(rpe, in: context)
        case .amrap:
            .unspecifiedLoad
        case .previousPlusIncrement(let increment):
            previous(plus: increment, in: context)
        case .bodyweight(let added):
            // No rounding and no loading: the added load is what a set records, and it hangs from a
            // belt or a band rather than from a bar.
            .resolved(ResolvedPrescription(target: added))
        case .unrecognised(let unrecognised):
            .unresolvable(.unrecognisedPrescription(kind: unrecognised.kind))
        }
    }
}

// MARK: - The cases that compute a weight

extension PrescriptionResolver {
    /// `ratio` of `basis`, rounded — or `reason` when there is no basis to take it of.
    private func percentage(
        _ ratio: Double,
        of basis: Weight?,
        orMissing reason: PrescriptionUnresolvedReason,
        in context: PrescriptionContext
    ) -> PrescriptionResolution {
        guard let basis else { return .unresolvable(reason) }
        guard ratio.isFinite, ratio > 0 else { return .unresolvable(.percentageOutOfRange(ratio)) }
        return target(basis, scaledBy: ratio, in: context)
    }

    /// The load the chart puts at `rpe` for the context's rep count, as a fraction of the estimate.
    private func rpeTarget(
        _ rpe: Double, in context: PrescriptionContext
    ) -> PrescriptionResolution {
        guard let basis = context.estimatedOneRepMax else {
            return .unresolvable(.noEstimatedOneRepMax)
        }
        // `contains` refuses a NaN and both infinities on its own, so the range is the whole check.
        guard SetRecord.rpeRange.contains(rpe) else { return .unresolvable(.rpeOutOfRange(rpe)) }
        guard let reps = context.reps else { return .unresolvable(.noRepCount) }
        guard rpeTable.repRange.contains(reps) else {
            return .unresolvable(.repCountOutOfRange(reps))
        }
        let reserve = SetRecord.rpeRange.upperBound - rpe
        guard let fraction = rpeTable.fractionOfMax(atRepsToFailure: Double(reps) + reserve) else {
            return .unresolvable(.effortOffTheChart(reps: reps, rpe: rpe))
        }
        return target(basis, scaledBy: fraction, in: context)
    }

    /// Last session's load plus a signed step, unrounded.
    ///
    /// Added with an overflow check rather than with `+`, which traps. No sign guard: an increment
    /// on assisted work moves it toward zero, which is what progressing assisted work means.
    private func previous(
        plus increment: Weight, in context: PrescriptionContext
    ) -> PrescriptionResolution {
        guard let previous = context.previousWeight else {
            return .unresolvable(.noPreviousPerformance)
        }
        let (grams, overflowed) = previous.grams.addingReportingOverflow(increment.grams)
        guard !overflowed else { return .unresolvable(.notRepresentable) }
        return resolved(Weight(grams: grams), in: context)
    }

    /// `basis` scaled and then snapped to the context's rule — the whole derived pipeline, in the
    /// order that makes it: factor, whole grams, rounding rule.
    ///
    /// One sign guard for all four factor-taking cases rather than one per path, so it cannot be
    /// half-removed.
    private func target(
        _ basis: Weight, scaledBy factor: Double, in context: PrescriptionContext
    ) -> PrescriptionResolution {
        guard basis.grams >= 0 else { return .unresolvable(.negativeBasis(basis)) }
        guard let scaled = basis.scaled(by: factor) else { return .unresolvable(.notRepresentable) }
        return resolved(context.rounding.rounded(scaled), in: context)
    }

    /// A decided target, with the loading the profile makes of it attached.
    private func resolved(
        _ target: Weight, in context: PrescriptionContext
    ) -> PrescriptionResolution {
        .resolved(
            ResolvedPrescription(target: target, loading: context.plates?.loading(for: target)))
    }
}
