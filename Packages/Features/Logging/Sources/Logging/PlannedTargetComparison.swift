import DesignSystem
import Foundation
import Localization
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

/// One *group* measured against the group that was planned for it (`FR-17.9.4`).
///
/// **``PlannedTargetComparison`` one dimension wider.** That type answers for a single set, which
/// has a load and reps; a group also has a count, and the Log sheet's whole job is to collect one.
/// Written as a second type rather than as an optional third field on that one, because every
/// caller of that one asks about a set and would have to answer a question it cannot have.
///
/// **Only over a plan that collapses to one group.** A prescription of `100 × 5 × 3` then
/// `90 × 8 × 2` has no single deviation to state — the form says one thing and the plan says two —
/// so the initialiser refuses rather than inventing a comparison against the first half. The pair
/// still draws both lines there; what it drops is the sentence.
struct PlannedGroupComparison: Equatable, Sendable {
    /// Which way the load went, or `nil` where the plan named none (`FR-15.2.2`).
    let weight: DeltaDirection?

    /// How far, unsigned — `nil` alongside a `nil` ``weight``.
    let weightDifference: Weight?

    /// Which way the repetitions went.
    let reps: DeltaDirection

    /// How many, unsigned.
    let repsDifference: Int

    /// Which way the set count went.
    let sets: DeltaDirection

    /// How many, unsigned.
    let setsDifference: Int

    /// The load's move, where the plan named a load *and* the group did not match it.
    ///
    /// ``PlannedTargetComparison/movedWeight``'s convenience, for its reason: the two absences are
    /// different facts and are kept apart above, and a caller drawing the difference wants neither
    /// a `nil` nor a signed zero.
    var movedWeight: (direction: DeltaDirection, difference: Weight)? {
        guard let weight, weight != .unchanged, let weightDifference else { return nil }
        return (weight, weightDifference)
    }

    /// Whether the group matched everything the plan named — ``PlannedTargetComparison/isOnTarget``
    /// with the count added.
    var isOnTarget: Bool {
        reps == .unchanged && sets == .unchanged && (weight ?? .unchanged) == .unchanged
    }

    /// Measures what the form says against what the routine prescribed.
    ///
    /// - Parameters:
    ///   - planned: The prescription, in order. Collapsed first, on ``DayRow/wasAsPlanned``'s rule:
    ///     the group boundary is the routine's bookkeeping rather than a claim about the work.
    ///   - performed: What the form says — its load, reps and set count.
    init?(planned: [WeekPlanTarget], performed: WeekPlanTarget) {
        let collapsed = DayPerformance.collapsed(planned)
        guard collapsed.count == 1, let target = collapsed.first else { return nil }
        if let plannedWeight = target.weight, let actual = performed.weight {
            weight = Self.direction(from: plannedWeight.grams, to: actual.grams)
            weightDifference = Weight(grams: abs(actual.grams - plannedWeight.grams))
        } else {
            weight = nil
            weightDifference = nil
        }
        reps = Self.direction(from: target.reps, to: performed.reps)
        repsDifference = abs(performed.reps - target.reps)
        sets = Self.direction(from: target.sets, to: performed.sets)
        setsDifference = abs(performed.sets - target.sets)
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

/// The difference, said in the lifter's own words (`FR-17.9.4`).
///
/// **A sentence rather than a row of indicators, because it sits inside a line.** The Planned /
/// Actual pair reads `30 kg × 8 × 3 · −2 reps`; two `DeltaIndicator`s there would be two boxed
/// glyphs inside a value, which is the shape ``PlannedTargetLine`` already gives its own verdict a
/// line of its own for.
///
/// **The sign is ``DesignSystem/DeltaDirection/sign``'s and never a hyphen**, so the clause carries
/// the direction where the tint cannot (`G-4.5`).
enum PlannedDeviation {
    /// What the group did against its plan, or that it did exactly it.
    ///
    /// **Only the dimensions that moved**, on ``PlannedTargetLine``'s rule: a signed zero is a
    /// number the reader has to look past on the way to the one that changed.
    ///
    /// - Parameters:
    ///   - comparison: The measured group.
    ///   - unit: The unit the load reads in (`G-3.1`).
    ///   - precision: `G-3.3`'s step, or `nil` for the unit's own.
    ///   - locale: Which locale the numbers read in (`G-3.4`).
    /// - Returns: `−2 reps`, `+2.5 kg, +1 set`, or *as planned*.
    static func sentence(
        _ comparison: PlannedGroupComparison,
        unit: MassUnit,
        precision: DisplayPrecision?,
        locale: Locale
    ) -> String {
        guard !comparison.isOnTarget else {
            return String(localized: LoggingStrings.setDeviationAsPlanned)
        }
        var clauses: [String] = []
        if let moved = comparison.movedWeight {
            let load = moved.difference.formatted(
                AppFormat.weight(WeightDisplay(unit: unit, resolving: precision), locale: locale))
            clauses.append(
                String(localized: LoggingStrings.setDeviationWeight(moved.direction.sign + load)))
        }
        if comparison.reps != .unchanged {
            clauses.append(
                String(
                    localized: LoggingStrings.setDeviationReps(
                        sign: comparison.reps.sign, count: comparison.repsDifference)))
        }
        if comparison.sets != .unchanged {
            clauses.append(
                String(
                    localized: LoggingStrings.setDeviationSets(
                        sign: comparison.sets.sign, count: comparison.setsDifference)))
        }
        return clauses.joined(separator: String(localized: LoggingStrings.setDeviationSeparator))
    }
}
