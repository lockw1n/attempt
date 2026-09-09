import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// A finished workout read as the routine it would prescribe (`FR-15.2.6`).
///
/// **The sets that were logged, not the plan the session was given.** A session started from a
/// routine carries that routine's targets (`TR-15.3`), and copying those back would author a second
/// routine identical to one that already exists. What `FR-15.2.6` is for is the other case: a
/// workout the lifter wants to repeat *as performed*, deviations included — which is exactly what
/// the planned targets are not. The cost is deliberate and worth stating: adherence
/// (``SessionAdherence``, `FR-15.3.3`) is measured against the plan a session was given, so a
/// routine saved from a workout that missed its targets makes the miss the new plan, and the next
/// session adherent by construction. That is the lifter saying "this is what I actually do", and it
/// is the only reading under which this command produces a routine they do not already have.
///
/// **Warmups and unperformed sets are left out**, on ``SessionExercise/isComplete``'s rule for the
/// same partition: a warmup is not the work, and a set carrying `isCompleted == false` is one that
/// was prescribed or attempted and not done (`G-1.8`). Neither is something to prescribe next time.
///
/// **Every entry becomes a slot even when nothing under it qualifies.** The exercises a workout
/// trained, in the order it trained them, are the routine's shape; a slot with no targets is the
/// same "short rather than wrong" routine `Routines`' own editor already allows — a slot with no
/// target is one the lifter has not decided yet — and dropping the exercise instead would silently
/// shorten the plan.
///
/// **A skipped exercise keeps the plan it was given, rather than reading as nothing performed**
/// (`FR-17.8.6`). *Skipped* is ``DayRowAnswer/skipped`` — marked done with no completed working set
/// — and the sets are then silent about what the lifter meant to do, so the entry's own planned
/// rows are what is carried forward. They are the rows the day was *started* with rather than the
/// routine's targets as they read today, which is `FR-16.8.3`: a past session is never altered by a
/// later plan edit. An entry nobody answered at all is neither, and contributes an empty slot as
/// before.
struct SessionAsRoutine: Equatable {
    /// One exercise slot, in the order the workout performed it.
    struct Slot: Equatable {
        /// The catalogue exercise the entry named.
        let exerciseID: UUID

        /// What it prescribes, in the order the sets were logged.
        let groups: [Target]
    }

    /// One target group: a load, its reps, and how many sets of it were done back to back.
    struct Target: Equatable {
        /// The load on one implement (`TR-0.2.3`), or `nil` where the plan named none.
        ///
        /// **Optional because a *carried* plan may be**: a performed group always has a load, and a
        /// skipped exercise's planned rows are `FR-15.2.2`'s targets, which are free to leave the
        /// load for the session to decide. Dropping those would shorten the plan silently.
        let weight: Weight?

        /// Repetitions per set.
        let reps: Int

        /// How many consecutive sets carried that load and those reps.
        let sets: Int
    }

    /// The slots, in entry order.
    let slots: [Slot]

    /// Reads a session's exercises as a routine, per answer (`FR-17.8.6`).
    ///
    /// - Parameter exercises: The session's exercises, in entry order, each carrying the targets
    ///   the day was started with (``SessionExercise/planned``).
    init(_ exercises: [SessionExercise]) {
        slots = exercises.map {
            Slot(exerciseID: $0.entry.exerciseID, groups: Self.targets(of: $0))
        }
    }

    /// What one exercise prescribes next week, chosen by what was said about it.
    ///
    /// - Parameter exercise: The entry, its sets and the targets it was planned with.
    /// - Returns: The groups, in order — the performed runs, the planned rows, or none.
    private static func targets(of exercise: SessionExercise) -> [Target] {
        let performed = targets(from: exercise.sets)
        let answer = DayRowAnswer.derived(
            marked: exercise.entry.isMarkedDone, performedSomething: !performed.isEmpty)
        return answer == .skipped ? planned(from: exercise.planned) : performed
    }

    /// A skipped exercise's own plan, as targets.
    ///
    /// - Parameter groups: The entry's planned rows, in
    ///   ``RepositoryInterface/PlannedTargetGroup/order``.
    /// - Returns: The groups, in that order.
    private static func planned(from groups: [PlannedTargetGroup]) -> [Target] {
        groups.map { Target(weight: $0.targetWeight, reps: $0.targetReps, sets: $0.targetSets) }
    }

    /// Compresses one exercise's sets into target groups.
    ///
    /// **``DerivedValues/SetGrouping``'s rule at its prescribing grain, not a second one.** Every
    /// surface that reads sets groups them (`FR-16.1.1`), and a routine is that same run of
    /// consecutive equal sets written as a target: a top set followed by three backoffs is two
    /// groups and not four, which is how a routine writes it (`FR-15.2.1`'s amendment).
    ///
    /// **The grain is `loadAndReps`, and that is what keeps the two agreeing rather than identical.**
    /// A rating or a note that changed mid-run is a second line on the card and the same line in the
    /// plan — a routine has nowhere to put either, so breaking on them would prescribe `100×6×1`
    /// four times over.
    ///
    /// - Parameter sets: The sets logged against one entry, in order.
    /// - Returns: The groups, in that order.
    static func targets(from sets: [SetEntry]) -> [Target] {
        SetGrouping
            .groups(sets.filter { !$0.isWarmup && $0.isCompleted }, at: .loadAndReps)
            .map { Target(weight: $0.weight, reps: $0.reps, sets: $0.count) }
    }
}
