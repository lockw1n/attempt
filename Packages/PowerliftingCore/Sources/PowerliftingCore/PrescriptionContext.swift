/// The situation a ``Prescription`` resolves against (`TR-0.2.11`).
///
/// **Everything here is already resolved**: a ``TrainingMax`` rather than a configuration, an
/// estimate rather than a set collection. Resolution is then arithmetic over numbers the caller has
/// chosen, with no formula, no log, no clock and no locale in it — which is what makes
/// ``PrescriptionResolver`` deterministic and free of any persistence dependency (`TR-2.6`).
///
/// **``rounding`` decides the number; ``plates`` only describes it.** A rounding rule answers "what
/// is a sensible target" and a plate inventory answers "what will go on this bar", and applying both
/// to one target would discard weights the smaller pairs load precisely. So a loading is attached to
/// the resolved weight and never moves it — which is also what leaves `FR-1.4.4` something to show,
/// since a target snapped to the inventory would always load exactly.
///
/// **No bodyweight is needed and none is here.** ``Prescription/bodyweight(added:)`` prescribes the
/// external load alone, matching what a set records, so a bodyweight would be an input nothing
/// reads.
public struct PrescriptionContext: Sendable {
    /// The exercise's training max, or `nil` when none is configured or none could be resolved.
    ///
    /// The two are one answer to `FR-2.3.5`: both prompt for a training max. A value
    /// ``TrainingMaxResolver`` produced is non-negative; a negative one is refused at resolution
    /// rather than assumed away.
    public let trainingMax: TrainingMax?

    /// The best estimated one-rep maximum over the exercise's history.
    ///
    /// Read by ``Prescription/percentOfE1RM(percentage:)`` and by
    /// ``Prescription/rpeTarget(rpe:)``, whose chart gives a fraction *of a maximum* — an RPE target
    /// taken against a training max instead would underprescribe by the training max's own
    /// percentage on every set.
    public let estimatedOneRepMax: Weight?

    /// The heaviest set worked up to in the session being logged.
    ///
    /// The one input that is not prior data: `FR-2.2.3`'s backoffs resolve against the session in
    /// progress, so this is the input most likely to be absent at the moment resolution runs.
    public let topSetWeight: Weight?

    /// The load logged for this slot the last time it was performed.
    public let previousWeight: Weight?

    /// The slot's rep count (`FR-2.2.2`), read only by ``Prescription/rpeTarget(rpe:)``.
    ///
    /// A slot expressing a rep *range* has to pick one before resolving; nothing here can choose for
    /// it.
    public let reps: Int?

    /// The step a derived weight is snapped to, and the direction (`FR-2.2.4`, `FR-2.3.3`).
    ///
    /// Required rather than optional: every percentage lands on an arbitrary gram, and "no rounding
    /// rule" is not a state a user could act on. A one-gram increment is how a caller asks for no
    /// rounding. Applied only where a `Double` factor entered the arithmetic — see
    /// ``PrescriptionResolver``.
    public let rounding: RoundingRule

    /// The equipment profile the resolved weight is loaded on, or `nil` when none is selected.
    ///
    /// Absent is not a refusal: a target weight is a complete answer without knowing what plates the
    /// gym holds.
    public let plates: PlateCalculator?

    /// Creates a context. Every input other than ``rounding`` is optional, and each prescription
    /// type reads only the ones it needs.
    public init(
        rounding: RoundingRule,
        trainingMax: TrainingMax? = nil,
        estimatedOneRepMax: Weight? = nil,
        topSetWeight: Weight? = nil,
        previousWeight: Weight? = nil,
        reps: Int? = nil,
        plates: PlateCalculator? = nil
    ) {
        self.rounding = rounding
        self.trainingMax = trainingMax
        self.estimatedOneRepMax = estimatedOneRepMax
        self.topSetWeight = topSetWeight
        self.previousWeight = previousWeight
        self.reps = reps
        self.plates = plates
    }
}
