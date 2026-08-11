/// Resolves a ``TrainingMaxConfiguration`` against one exercise's logged sets (`TR-0.2.9`).
///
/// **The order is percentage, then rounding, and it is two rounding decisions rather than one.**
/// Scaling the source weight lands on a fraction of a gram, which comes back to whole grams because
/// grams are the storage resolution (`G-1.1`); ``TrainingMaxConfiguration/rounding`` then snaps that
/// to something a bar can hold. Reversing them gives a different, quietly wrong answer — 103 kg at
/// 90% on a 5 kg rule is 95 kg this way round and 94.5 kg the other.
///
/// **The sets are one exercise's, oldest first**, exactly as ``PersonalRecordCalculator`` requires —
/// this type reads its sources through that one and inherits both constraints. A manual source
/// ignores the collection entirely.
///
/// **Nothing is cached** (`G-1.4`). `TR-0.3.6` persists the configuration; the training max is
/// recomputed, which is what makes a new personal record move it.
public struct TrainingMaxResolver: Sendable {
    /// The records both derived sources are read through.
    public let records: PersonalRecordCalculator

    /// Creates a resolver reading sources through `records`.
    public init(records: PersonalRecordCalculator) {
        self.records = records
    }

    /// Creates a resolver using the formula `id` names, or ``E1RMFormulaID/defaultFormula``.
    public init(_ id: E1RMFormulaID = .defaultFormula) {
        self.init(records: PersonalRecordCalculator(id))
    }

    /// The training max `configuration` describes, or what stopped it resolving.
    ///
    /// - Parameters:
    ///   - configuration: The source, percentage and rounding rule.
    ///   - sets: One exercise's sets, oldest first. Warmups and incomplete sets may be included.
    ///     Unread when the source is ``TrainingMaxSource/manual(_:)``.
    public func resolve(
        _ configuration: TrainingMaxConfiguration, from sets: [SetRecord]
    ) -> TrainingMaxResolution {
        traced(configuration, from: sets).resolution
    }

    /// The same answer, with the chain that produced it (`TR-0.2.12`).
    ///
    /// **This is the only implementation** — ``resolve(_:from:)`` calls it and drops the trace — so a
    /// trace can never describe a computation different from the number it explains.
    ///
    /// This is the earlier half of `FR-2.3.4`'s `e1RM → TM → % → rounded → plates`, and a manual
    /// source is visibly one step: no percentage and no rounding, because neither ran.
    /// ``PrescriptionResolver/traced(_:in:)`` produces the later half.
    ///
    /// - Parameters:
    ///   - configuration: The source, percentage and rounding rule.
    ///   - sets: One exercise's sets, oldest first. Unread when the source is manual.
    public func traced(
        _ configuration: TrainingMaxConfiguration, from sets: [SetRecord]
    ) -> TracedTrainingMaxResolution {
        let source: Weight
        let basis: ResolutionBasis
        switch configuration.source {
        case .manual(let weight):
            source = weight
            basis = .entered
        case .percentOfE1RM:
            guard let record = records.bestE1RM(in: sets) else {
                return refused(.noSourceData, after: [])
            }
            source = record.weight
            basis = .bestEstimatedOneRepMax(formula: records.e1rm.formula.id)
        case .percentOfRepMax(let reps):
            guard PersonalRecords.repRange.contains(reps) else {
                return refused(.repCountOutOfRange(reps), after: [])
            }
            guard let record = records.repMax(forReps: reps, in: sets) else {
                return refused(.noSourceData, after: [])
            }
            source = record.weight
            basis = .repMax(reps: reps)
        }
        let read: [ResolutionStep] = [.basis(basis, source)]

        // One guard for all three sources rather than one per path, so it cannot be half-removed.
        // Unreachable through `.percentOfE1RM`, which `E1RMCalculator` already refuses a negative
        // weight for; live on the other two, where a negative is real data or a typo.
        guard source.grams >= 0 else { return refused(.negativeSourceWeight(source), after: read) }

        if configuration.source.isManual {
            return resolved(TrainingMax(weight: source, sourceWeight: source), after: read)
        }
        guard let scaled = source.scaled(by: configuration.percentage) else {
            return refused(.notRepresentable, after: read)
        }
        let snapped = configuration.rounding.rounded(scaled)
        return resolved(
            TrainingMax(weight: snapped, sourceWeight: source),
            after: read + [
                .scaled(by: configuration.percentage, from: source, to: scaled),
                .rounded(configuration.rounding, from: scaled, to: snapped),
            ])
    }

    /// A resolved training max and the chain behind it.
    private func resolved(
        _ trainingMax: TrainingMax, after steps: [ResolutionStep]
    ) -> TracedTrainingMaxResolution {
        TracedTrainingMaxResolution(
            resolution: .resolved(trainingMax), trace: ResolutionTrace(steps: steps))
    }

    /// A refusal, carrying however far the chain got before it.
    ///
    /// `steps` is not defaulted, for the reason ``PrescriptionResolver``'s is not: an empty chain is a
    /// claim, and a claim should be made rather than inherited by omission.
    private func refused(
        _ reason: TrainingMaxUnresolvedReason, after steps: [ResolutionStep]
    ) -> TracedTrainingMaxResolution {
        TracedTrainingMaxResolution(
            resolution: .unresolvable(reason), trace: ResolutionTrace(steps: steps))
    }
}
