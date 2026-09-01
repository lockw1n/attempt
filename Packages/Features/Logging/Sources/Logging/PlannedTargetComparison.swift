import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One logged set measured against the target it was planned with (`FR-15.3.2`).
///
/// **Derived at read time from the plan, never stored on the set.** The snapshot `TR-15.3` writes
/// is one group per prescription, and which set falls in which group is a walk over the working
/// sets — see ``SessionExercise/plannedTargets``. Copying a target onto each set as it is logged
/// would put a second answer in the store, and the two would part company the moment a set was
/// deleted or re-marked as a warmup.
///
/// **The load has three states, not two, because a plan need not name one** (`FR-15.2.2`). A blank
/// target prescribes the reps and leaves the weight to the lifter, so ``weight`` is `nil` there —
/// which is *no target to deviate from*, and is not the same fact as a deviation of zero. The reps
/// are prescribed either way, so ``reps`` always answers.
///
/// **Direction follows the arithmetic, not the sentiment**, which is ``DesignSystem/DeltaDirection``'s
/// own rule: more weight than planned is an increase whether or not that was wise.
public struct PlannedTargetComparison: Equatable, Sendable {
    /// Which way the load went against the target, or `nil` where the plan named no load.
    public let weight: DeltaDirection?

    /// How far it went, unsigned — `nil` alongside a `nil` ``weight``.
    ///
    /// Unsigned because the direction is already carried, and the two cues are drawn separately:
    /// a glyph and a sign say which way, the magnitude says how far.
    public let weightDifference: Weight?

    /// Which way the repetitions went against the target.
    public let reps: DeltaDirection

    /// How many, unsigned. Zero exactly when ``reps`` is `unchanged`.
    public let repsDifference: Int

    /// The load's move, where the plan named a load *and* the set did not match it.
    ///
    /// **The two absences this collapses are different facts and are kept apart above**:
    /// ``weight`` is `nil` where nothing was prescribed and `unchanged` where the lifter hit it.
    /// What a caller drawing an indicator needs is neither — a signed zero is a number the reader
    /// has to look past — so the pair is offered once here rather than reassembled at each call
    /// site.
    public var movedWeight: (direction: DeltaDirection, difference: Weight)? {
        guard let weight, weight != .unchanged, let weightDifference else { return nil }
        return (weight, weightDifference)
    }

    /// Whether the set matched everything the plan named.
    ///
    /// **A blank-weight target is on target on its reps alone**, which is the only thing it
    /// prescribed — treating the absent load as a miss would make every set of a blank-weight group
    /// deviate by construction.
    public var isOnTarget: Bool {
        reps == .unchanged && (weight ?? .unchanged) == .unchanged
    }

    /// Measures one set against one planned group.
    ///
    /// - Parameters:
    ///   - set: The set as it was logged.
    ///   - target: The group it falls in.
    public init(set: SetEntry, target: PlannedTargetGroup) {
        if let planned = target.targetWeight {
            weight = Self.direction(from: planned.grams, to: set.weight.grams)
            weightDifference = Weight(grams: abs(set.weight.grams - planned.grams))
        } else {
            weight = nil
            weightDifference = nil
        }
        reps = Self.direction(from: target.targetReps, to: set.reps)
        repsDifference = abs(set.reps - target.targetReps)
    }

    /// Which way `actual` sits from `planned`.
    ///
    /// - Parameters:
    ///   - planned: What was prescribed.
    ///   - actual: What was done.
    /// - Returns: The direction of the move.
    private static func direction(from planned: Int, to actual: Int) -> DeltaDirection {
        if actual > planned { return .increase }
        if actual < planned { return .decrease }
        return .unchanged
    }
}
