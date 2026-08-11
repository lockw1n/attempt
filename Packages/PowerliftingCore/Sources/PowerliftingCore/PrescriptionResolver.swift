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
        traced(prescription, in: context).resolution
    }

    /// The same answer, with the chain that produced it (`TR-0.2.12`).
    ///
    /// **This is the only implementation** — ``resolve(_:in:)`` calls it and drops the trace — so a
    /// trace can never describe a computation different from the number it explains.
    ///
    /// Each trace begins at the value the prescription reads — see ``ResolutionBasis`` — so for
    /// ``Prescription/percentOfTrainingMax(percentage:)`` it begins at the training max and not at the
    /// e1RM behind it, a resolved training max being all a context carries.
    /// ``TrainingMaxResolver/traced(_:from:)`` produces that earlier half of `FR-2.3.4`'s chain, and
    /// ``ResolutionTrace/followed(by:)`` joins the two.
    public func traced(
        _ prescription: Prescription, in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        switch prescription {
        case .fixedWeight(let weight):
            resolved(weight, after: [.basis(.entered, weight)], in: context)
        case .percentOfTrainingMax(let percentage):
            self.percentage(
                percentage,
                of: context.trainingMax?.weight,
                from: .trainingMax,
                orMissing: .noTrainingMax,
                in: context)
        case .percentOfE1RM(let percentage):
            self.percentage(
                percentage,
                of: context.estimatedOneRepMax,
                from: .estimatedOneRepMax,
                orMissing: .noEstimatedOneRepMax,
                in: context)
        case .percentOfTopSet(let percentage):
            self.percentage(
                percentage,
                of: context.topSetWeight,
                from: .topSet,
                orMissing: .noTopSet,
                in: context)
        case .rpeTarget(let rpe):
            rpeTarget(rpe, in: context)
        case .amrap:
            TracedPrescriptionResolution(resolution: .unspecifiedLoad, trace: .empty)
        case .previousPlusIncrement(let increment):
            previous(plus: increment, in: context)
        case .bodyweight(let added):
            // No rounding and no loading: the added load is what a set records, and it hangs from a
            // belt or a band rather than from a bar. One step, and it is the whole chain.
            TracedPrescriptionResolution(
                resolution: .resolved(ResolvedPrescription(target: added)),
                trace: ResolutionTrace(steps: [.basis(.bodyweightLoad, added)]))
        case .unrecognised(let unrecognised):
            refused(.unrecognisedPrescription(kind: unrecognised.kind), after: [])
        }
    }
}

// MARK: - The cases that compute a weight

extension PrescriptionResolver {
    /// `ratio` of `basis`, rounded — or `reason` when there is no basis to take it of.
    private func percentage(
        _ ratio: Double,
        of basis: Weight?,
        from source: ResolutionBasis,
        orMissing reason: PrescriptionUnresolvedReason,
        in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        guard let basis else { return refused(reason, after: []) }
        let read: [ResolutionStep] = [.basis(source, basis)]
        guard ratio.isFinite, ratio > 0 else {
            return refused(.percentageOutOfRange(ratio), after: read)
        }
        return target(basis, scaledBy: ratio, after: read, in: context)
    }

    /// The load the chart puts at `rpe` for the context's rep count, as a fraction of the estimate.
    private func rpeTarget(
        _ rpe: Double, in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        guard let basis = context.estimatedOneRepMax else {
            return refused(.noEstimatedOneRepMax, after: [])
        }
        let read: [ResolutionStep] = [.basis(.estimatedOneRepMax, basis)]
        // `contains` refuses a NaN and both infinities on its own, so the range is the whole check.
        guard SetRecord.rpeRange.contains(rpe) else {
            return refused(.rpeOutOfRange(rpe), after: read)
        }
        guard let reps = context.reps else { return refused(.noRepCount, after: read) }
        guard rpeTable.repRange.contains(reps) else {
            return refused(.repCountOutOfRange(reps), after: read)
        }
        let reserve = SetRecord.rpeRange.upperBound - rpe
        let key = Double(reps) + reserve
        guard let fraction = rpeTable.fractionOfMax(atRepsToFailure: key) else {
            // No cell, so no step: the chart was consulted and produced nothing. The refusal carries
            // both inputs, and the key is their sum.
            return refused(.effortOffTheChart(reps: reps, rpe: rpe), after: read)
        }
        let chart = ResolutionStep.effort(
            reps: reps, rpe: rpe, repsToFailure: key, fractionOfMax: fraction)
        return target(basis, scaledBy: fraction, after: read + [chart], in: context)
    }

    /// Last session's load plus a signed step, unrounded.
    ///
    /// Added with an overflow check rather than with `+`, which traps. No sign guard: an increment
    /// on assisted work moves it toward zero, which is what progressing assisted work means.
    private func previous(
        plus increment: Weight, in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        guard let previous = context.previousWeight else {
            return refused(.noPreviousPerformance, after: [])
        }
        let read: [ResolutionStep] = [.basis(.previousPerformance, previous)]
        let (grams, overflowed) = previous.grams.addingReportingOverflow(increment.grams)
        guard !overflowed else { return refused(.notRepresentable, after: read) }
        let sum = Weight(grams: grams)
        let step = ResolutionStep.incremented(by: increment, from: previous, to: sum)
        return resolved(sum, after: read + [step], in: context)
    }

    /// `basis` scaled and then snapped to the context's rule — the whole derived pipeline, in the
    /// order that makes it: factor, whole grams, rounding rule.
    ///
    /// One sign guard for all four factor-taking cases rather than one per path, so it cannot be
    /// half-removed. It is also the only place *in this type* that builds a
    /// ``ResolutionStep/rounded(_:from:to:)`` step, which is what keeps that step out of the three
    /// chains where no rule ran. ``TrainingMaxResolver`` builds its own.
    private func target(
        _ basis: Weight,
        scaledBy factor: Double,
        after steps: [ResolutionStep],
        in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        guard basis.grams >= 0 else { return refused(.negativeBasis(basis), after: steps) }
        guard let scaled = basis.scaled(by: factor) else {
            return refused(.notRepresentable, after: steps)
        }
        let snapped = context.rounding.rounded(scaled)
        return resolved(
            snapped,
            after: steps + [
                .scaled(by: factor, from: basis, to: scaled),
                .rounded(context.rounding, from: scaled, to: snapped),
            ],
            in: context)
    }

    /// A decided target, with the loading the profile makes of it attached.
    ///
    /// The loading is computed once and placed twice — on the resolution and on the last step — so
    /// the trace's plate row can never belong to a different weight than the answer does.
    private func resolved(
        _ target: Weight, after steps: [ResolutionStep], in context: PrescriptionContext
    ) -> TracedPrescriptionResolution {
        let loading = context.plates?.loading(for: target)
        return TracedPrescriptionResolution(
            resolution: .resolved(ResolvedPrescription(target: target, loading: loading)),
            trace: ResolutionTrace(
                steps: loading.map { steps + [.loaded(target, as: $0)] } ?? steps))
    }

    /// A refusal, carrying however far the chain got before it.
    ///
    /// `steps` is not defaulted, so every refusal states its own chain — the same reason `SetRecord`
    /// refuses to default its two flags. An empty list here is a claim that nothing had been computed,
    /// and it should be made at the call site rather than inherited by omission.
    private func refused(
        _ reason: PrescriptionUnresolvedReason, after steps: [ResolutionStep]
    ) -> TracedPrescriptionResolution {
        TracedPrescriptionResolution(
            resolution: .unresolvable(reason), trace: ResolutionTrace(steps: steps))
    }
}
