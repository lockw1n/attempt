import Foundation

/// How much of what a routine prescribed was actually performed as prescribed (`FR-15.3.3`).
///
/// **Derived at read time from the exercises, never stored beside the workout** — the rule
/// ``PlannedTargetComparison`` is built on, and for the same reason: an adjustment made to a logged
/// set re-derives on the next read, so the figure follows the edit with nothing to invalidate. A
/// stored count would be a second answer that parts company with the sets the moment one is
/// corrected, deleted or re-marked as a warmup.
///
/// **Nil is a state, and it is the common one.** A workout started by hand prescribes nothing, so
/// there is no ratio to take — `FR-1.13.3`'s "say so rather than display zero", applied to a value
/// that is *undefined* rather than merely small. The initialiser refuses in that case rather than
/// returning `0 / 0`, which is what makes ``fraction`` total for every value that exists.
public struct SessionAdherence: Equatable, Sendable {
    /// How many prescribed sets were completed and matched what was planned for them.
    public let asPrescribed: Int

    /// How many sets the routine prescribed, over every exercise it named. Always positive.
    public let prescribed: Int

    /// The proportion, `0` through `1`.
    ///
    /// Not a division by zero: a value with nothing prescribed does not exist — see ``init(_:)``.
    public var fraction: Double { Double(asPrescribed) / Double(prescribed) }

    /// Reads adherence off the workout's exercises, or refuses where nothing was prescribed.
    ///
    /// **The denominator is the plan, not the log**, which is what makes a skipped exercise cost
    /// something: `FR-15.3.4`'s check-off with no work behind it leaves its prescribed sets standing
    /// in the total with nothing counted against them, and an exercise nobody planned — one added by
    /// hand to a planned workout — contributes to neither side.
    ///
    /// **The numerator counts a set three ways, and every one of them has its home elsewhere.** It
    /// must have a target at all (``SessionExercise/plannedTargets``, which is also where warmups
    /// and sets logged past the end of the plan drop out — the first do not consume a planned set
    /// and the second have nothing to be measured against, `FR-15.2.4`); it must have been completed
    /// (`FR-1.2.5` — "sets completed as prescribed" is two claims, and a set left unticked has not
    /// met the first); and it must match (``PlannedTargetComparison/isOnTarget``, which is where
    /// `FR-15.2.2`'s blank target is judged on its reps alone rather than excluded — excluding it
    /// would drop from the denominator sets the routine explicitly prescribed).
    ///
    /// - Parameter exercises: The workout's exercises, joined with what was planned for them.
    public init?(_ exercises: [SessionExercise]) {
        var prescribed = 0
        var matched = 0
        for exercise in exercises {
            prescribed += exercise.planned.reduce(0) { $0 + $1.targetSets }
            let targets = exercise.plannedTargets
            matched += exercise.sets.count { set in
                guard set.isCompleted, let target = targets[set.id] else { return false }
                return PlannedTargetComparison(set: set, target: target).isOnTarget
            }
        }
        guard prescribed > 0 else { return nil }
        self.prescribed = prescribed
        asPrescribed = matched
    }
}
