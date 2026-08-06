/// Where a training max gets its number from (`TR-0.2.9`, `FR-1.5.1.1`).
public enum TrainingMaxSource: Sendable, Hashable {
    /// A percentage of the best estimated one-rep maximum over the sets supplied.
    ///
    /// *Best*, not most recent: read through ``PersonalRecordCalculator/bestE1RM(in:)``, so the
    /// answer moves only when a better set is logged.
    case percentOfE1RM

    /// A percentage of the heaviest completed working set performed for at least `reps` reps.
    ///
    /// - Parameter reps: The N, within ``PersonalRecords/repRange``. A value outside it is a
    ///   *refusal* at resolution rather than a rejection here; see
    ///   ``TrainingMaxUnresolvedReason/repCountOutOfRange(_:)``.
    case percentOfRepMax(reps: Int)

    /// The training max, entered by hand (`FR-1.5.1.5`). The associated weight is the answer.
    case manual(Weight)

    /// Whether this source is a hand-entered value rather than a derived one.
    ///
    /// A case test and nothing more. **The behaviour it names — that a manual training max is the
    /// number the user typed, with neither the percentage nor the rounding rule applied — is
    /// ``TrainingMaxResolver/resolve(_:from:)``'s**, which is the only thing that reads this.
    /// `FR-1.5.1.5` makes manual an *override*, the state in which the derived pipeline is not
    /// running. No requirement states it.
    ///
    /// Public because `FR-1.5.1.5` also asks for a visible override indicator, which is this.
    public var isManual: Bool {
        if case .manual = self { return true }
        return false
    }
}

/// How one exercise's training max is computed (`TR-0.2.9`, `TR-0.3.6`).
///
/// The persisted counterpart is `TR-0.3.6`'s `TrainingMaxConfigEntity`, column per property. Not
/// `Codable` on purpose: it is stored as columns rather than as a blob, so a wire format here would
/// be a second storage contract nothing asked for.
///
/// **`TR-0.2.9` names four things — "source, percentage, rounding, increment" — and they are three
/// steps.** The rounding increment and its strategy are together one ``RoundingRule``;
/// ``progressionIncrement`` is a different quantity that resolution never touches.
public struct TrainingMaxConfiguration: Sendable, Hashable {
    /// `FR-1.5.1.2`'s default, as a ratio: 90%.
    public static let defaultPercentage = 0.9

    /// Where the number comes from.
    public let source: TrainingMaxSource

    /// The fraction of the source weight to take, as a ratio — `0.9` is 90%, not `90`.
    ///
    /// Always finite and greater than zero, and deliberately uncapped above 1: no requirement rules
    /// out a training max above the value it derives from. Left unread by
    /// ``TrainingMaxResolver/resolve(_:from:)`` when ``source`` is ``TrainingMaxSource/manual(_:)``
    /// — see ``TrainingMaxSource/isManual``.
    public let percentage: Double

    /// What the scaled weight is snapped to, so the training max is a loadable number.
    ///
    /// Applied *after* the percentage by ``TrainingMaxResolver/resolve(_:from:)``, strategy
    /// included — a `.down` rule can floor a small training max to zero, which is the rule's answer
    /// and not an absence. A one-gram increment is the identity, which is how a caller asks for no
    /// rounding. Left unread for a manual source, as ``percentage`` is.
    public let rounding: RoundingRule

    /// The step added on successful block completion (`FR-1.5.1.3`, `FR-2.4.7`).
    ///
    /// **Carried, never applied.** Progression is an event that rewrites the configuration;
    /// applying it at resolution would inflate the training max on every read. `nil` when no
    /// automatic progression is configured.
    ///
    /// Unconstrained, unlike ``RoundingRule/increment``: nothing here reads it, and a negative step
    /// is a configured deload rather than a mistake. Whoever applies it owns that boundary.
    public let progressionIncrement: Weight?

    /// Creates a configuration.
    ///
    /// - Parameter percentage: A ratio — `0.9` is 90%.
    /// - Returns: `nil` if `percentage` is not finite or is not greater than zero. Rejected here
    ///   rather than refused at resolution, because a non-finite factor has no meaningful answer
    ///   downstream — unlike ``TrainingMaxSource/percentOfRepMax(reps:)``'s N, which is checked at
    ///   resolution so a configuration written under a wider rep range still loads.
    public init?(
        source: TrainingMaxSource,
        percentage: Double = TrainingMaxConfiguration.defaultPercentage,
        rounding: RoundingRule,
        progressionIncrement: Weight? = nil
    ) {
        guard percentage.isFinite, percentage > 0 else { return nil }
        self.source = source
        self.percentage = percentage
        self.rounding = rounding
        self.progressionIncrement = progressionIncrement
    }
}
