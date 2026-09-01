import Foundation
import PowerliftingCore
import RepositoryInterface

/// One exercise as it sits in the workout being logged — the entry, the exercise it names, and the
/// sets logged against it (`FR-1.2.2`, `FR-1.2.13`).
///
/// **Three records rather than one, because the schema declares no relationships** (`G-2.5`):
/// `WorkoutRepository` returns entries, `ExerciseRepository` returns exercises and the sets come
/// from a third read, and joining them is the caller's. This is that join, done once where the
/// screen can be handed it.
///
/// **Not a source of truth for anything** (`G-1.4`). Every field here is a copy of a row, rebuilt by
/// the read that produced it; ``isComplete`` is recomputed from the sets rather than stored, which
/// is what keeps a collapsed card and a finished exercise the same fact.
public struct SessionExercise: Identifiable, Equatable, Sendable {
    /// The entry — this exercise's position in the workout, and its notes.
    public let entry: ExerciseEntry

    /// The exercise performed, or `nil` when the catalogue no longer has that row.
    ///
    /// **Optional, and the card renders the absence rather than dropping the entry.** An exercise
    /// cannot be deleted (`FR-1.1.5` gives archiving instead), so this is `nil` only where a restore
    /// or a sync left an entry pointing at a row that never arrived — and an exercise silently
    /// missing from a workout is worse than one the user can see is broken.
    public let exercise: Exercise?

    /// The sets logged against it, in ``RepositoryInterface/SetEntry/order``.
    public let sets: [SetEntry]

    /// What the routine prescribed for it when the workout was started, in
    /// ``RepositoryInterface/PlannedTargetGroup/order`` (`TR-15.3`).
    ///
    /// **Empty for an exercise nobody planned**, which is most of them: a workout started by hand
    /// has no plan, and an exercise added to a planned workout is not part of the plan either. That
    /// is not a state anything reports — the card simply has no target to show.
    public let planned: [PlannedTargetGroup]

    /// The entry's id: one entry is one card, and the same exercise may be performed twice in a
    /// workout.
    public var id: UUID { entry.id }

    /// Builds the join.
    ///
    /// - Parameters:
    ///   - entry: This exercise's place in the workout.
    ///   - exercise: The catalogue row it names, where there is one.
    ///   - sets: The sets logged against the entry.
    ///   - planned: The targets snapshotted from a routine, or none.
    public init(
        entry: ExerciseEntry,
        exercise: Exercise?,
        sets: [SetEntry],
        planned: [PlannedTargetGroup] = []
    ) {
        self.entry = entry
        self.exercise = exercise
        self.sets = sets
        self.planned = planned
    }

    /// Whether this exercise is finished — what `FR-1.2.13` collapses a card for.
    ///
    /// **Working sets only, and at least one of them.** Warmups are excluded for the reason every
    /// derived value in this app excludes them: they are not the work. An exercise with no working
    /// set is not complete but *unstarted*, which is the case a bare `allSatisfy` reports backwards
    /// — an empty collection satisfies everything, so a card the user has just added would collapse
    /// itself the moment it appeared.
    public var isComplete: Bool {
        let working = sets.filter { !$0.isWarmup }
        return !working.isEmpty && working.allSatisfy(\.isCompleted)
    }

    /// Whether any of the work proper has been logged yet — what `FR-1.2.14`'s warmup group folds
    /// itself on.
    ///
    /// **The same partition ``isComplete`` makes, asked one step earlier.** That property answers
    /// *is the work finished*; this one answers *has it started*, and the two are different states
    /// of a card that has warmups in it and nothing else.
    public var hasWorkingSets: Bool {
        sets.contains { !$0.isWarmup }
    }

    /// The planned group the next working set falls in, or `nil` (`FR-15.2.3`).
    ///
    /// **Working sets only, and it walks the groups rather than indexing them.** A plan of
    /// `100×5×1` then `85×8×3` puts the first set in the top-set group and the next three in the
    /// backoff, so the answer is the group whose running total the next set has not yet passed —
    /// which is also what makes a multi-group exercise pre-populate correctly rather than offering
    /// the top set four times.
    ///
    /// **Warmups do not consume a planned set.** A routine prescribes the work; warming up to it is
    /// the lifter's business, and counting warmups here would push a lifter who took three of them
    /// straight past their first working target.
    ///
    /// `nil` once the plan is exhausted — an extra set beyond what was planned is `FR-15.2.4`'s
    /// independence, not an error, and the form opens blank for it exactly as an unplanned
    /// exercise's does.
    public var nextPlannedGroup: PlannedTargetGroup? {
        var remaining = sets.count { !$0.isWarmup }
        for group in planned {
            if remaining < group.targetSets { return group }
            remaining -= group.targetSets
        }
        return nil
    }

    /// What the set editor opens filled in with for the next set, or `nil` where nothing was
    /// planned for it (`FR-15.2.3`).
    ///
    /// **A blank-weight group still fills the reps in** (`FR-15.2.2`). The load is the one thing
    /// that plan left to the lifter, and it is left empty rather than zeroed — a zero would assert
    /// a load nobody chose, which is the distinction that requirement exists for — but the reps and
    /// the sets are prescribed either way, and dropping them would make a blank-weight group
    /// pre-populate nothing at all.
    public var plannedSeed: PlannedSetSeed? {
        guard let group = nextPlannedGroup else { return nil }
        return PlannedSetSeed(weight: group.targetWeight, reps: group.targetReps)
    }
}

/// What a planned group puts into the set editor when it opens (`FR-15.2.3`).
///
/// **Not ``SetEntryValues``, because the load is optional here and is not there.** That type
/// describes a set that was performed — `FR-1.2.6`'s duplicate and `FR-1.2.7`'s edit both start from
/// one — and every set that was performed has a weight. A plan need not: `FR-15.2.2`'s blank target
/// prescribes the reps and leaves the load open, and widening the performed-set type to carry that
/// would put an unreachable `nil` in front of every existing caller.
///
/// Warmup is not a field: a routine prescribes the work, and `FR-1.2.4`'s warmup is a mark the
/// lifter puts on a set rather than something a plan can predict.
public struct PlannedSetSeed: Equatable, Sendable {
    /// The load prescribed, or `nil` where the plan named none (`FR-15.2.2`).
    public let weight: Weight?

    /// The reps prescribed per set in the group the next set falls in.
    public let reps: Int

    /// Builds the seed.
    ///
    /// - Parameters:
    ///   - weight: The load prescribed, or `nil`.
    ///   - reps: The reps prescribed.
    public init(weight: Weight?, reps: Int) {
        self.weight = weight
        self.reps = reps
    }
}

/// How far through the workout the user is (`FR-1.2.13`).
///
/// A value rather than two numbers on the view, so the claim "three of six" can be asserted without
/// rendering anything — and so the one division in it has exactly one home.
public struct SessionProgress: Equatable, Sendable {
    /// How many exercises are finished.
    public let completed: Int

    /// How many there are.
    public let total: Int

    /// Reads the progress off the workout's exercises.
    ///
    /// - Parameter exercises: The workout's exercises, in order.
    public init(_ exercises: [SessionExercise]) {
        total = exercises.count
        completed = exercises.count(where: \.isComplete)
    }

    /// The proportion complete, `0` through `1`.
    ///
    /// **An empty workout is `0` and not a division by zero.** It is also not `1`: a workout with
    /// nothing in it is not a finished one, and a bar drawn full over an empty session would say it
    /// was.
    public var fraction: Double {
        total == 0 ? 0 : Double(completed) / Double(total)
    }
}
