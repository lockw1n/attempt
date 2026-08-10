/// The ordered operations behind a resolved number (`TR-0.2.12`, `FR-2.3.4`).
///
/// **The steps are contiguous**: each one that consumes a weight consumes the last weight the trace
/// produced, so reading ``ResolutionStep/resultingWeight`` down the list follows one number from its
/// source to the target. Producing a contiguous list is a resolver's guarantee rather than this
/// type's — the initialiser takes any steps, because nothing in the module consumes a hand-built
/// trace.
///
/// **An empty trace means no operation over a weight was performed** — the input that was needed was
/// absent before any weight could be read, the prescription names no load at all, or it came from a
/// version this one cannot read. *Which* of those it was belongs to the resolution, and this type does
/// not restate it. Both resolvers produce empty traces, each for reasons of its own.
///
/// **`FR-2.3.4`'s `e1RM → TM → % → rounded → plates` is two of these joined.**
/// ``TrainingMaxResolver`` traces as far as the training max and ``PrescriptionResolver`` traces from
/// it, since a resolved training max is all that crosses between them. A caller holding both halves
/// joins them with ``followed(by:)``.
///
/// **No user-facing text and no formatting** — rendering a chain is a presentation concern. The only
/// string any payload can reach is ``E1RMFormulaID``'s raw value, which is a storage identifier
/// rather than prose.
public struct ResolutionTrace: Sendable, Hashable {
    /// A trace of nothing, for a resolution that computed nothing.
    public static let empty = ResolutionTrace(steps: [])

    /// The operations, in the order they ran.
    public let steps: [ResolutionStep]

    /// Creates a trace.
    public init(steps: [ResolutionStep]) {
        self.steps = steps
    }

    /// This trace, followed by `later`'s steps.
    ///
    /// The join `FR-2.3.4`'s chain needs across the two resolvers. Continuity is **not** checked:
    /// whether `later` starts from the weight this one ended at is the caller's to know, because only
    /// the caller resolved both halves.
    public func followed(by later: ResolutionTrace) -> ResolutionTrace {
        ResolutionTrace(steps: steps + later.steps)
    }
}

/// A prescription resolution together with the chain behind it (`TR-0.2.12`).
///
/// The trace rides beside the resolution rather than inside it because a refusal has a chain too — as
/// far as the point it stopped — and neither ``PrescriptionResolution/unspecifiedLoad`` nor
/// ``PrescriptionResolution/unresolvable(_:)`` has anywhere a trace could sit: one carries nothing and
/// the other carries a reason, which is a different fact. Keeping them apart also leaves that type's
/// equality about the answer.
public struct TracedPrescriptionResolution: Sendable, Hashable {
    /// The answer: a weight, no load at all, or what stopped it.
    public let resolution: PrescriptionResolution

    /// How it got there, ending where it stopped.
    public let trace: ResolutionTrace

    /// Creates a traced resolution.
    public init(resolution: PrescriptionResolution, trace: ResolutionTrace) {
        self.resolution = resolution
        self.trace = trace
    }
}

/// A training max resolution together with the chain behind it (`TR-0.2.12`).
///
/// The first half of `FR-2.3.4`'s chain. ``ResolutionTrace/followed(by:)`` joins it to the
/// prescription's, which begins at ``ResolutionBasis/trainingMax``.
public struct TracedTrainingMaxResolution: Sendable, Hashable {
    /// The answer: a training max, or what stopped it.
    public let resolution: TrainingMaxResolution

    /// How it got there, ending where it stopped.
    public let trace: ResolutionTrace

    /// Creates a traced resolution.
    public init(resolution: TrainingMaxResolution, trace: ResolutionTrace) {
        self.resolution = resolution
        self.trace = trace
    }
}
