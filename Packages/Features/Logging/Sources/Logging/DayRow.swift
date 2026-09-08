import Foundation
import PowerliftingCore
import RepositoryInterface

/// What one exercise on a day has been answered with (`FR-17.9.1`, `FR-17.9.6`).
///
/// **Three answers, and *skipped* is derived rather than stored** (`TR-17.4`): a row marked done
/// with no completed working set behind it is a skip, and a row marked done with sets that failed
/// is not — it has completed rows whose lifts did not go. So the two read apart without a column,
/// which is what keeps `G-2.5`'s schema out of this.
public enum DayRowAnswer: Equatable, Sendable {
    /// Nothing has been said about it yet.
    case unanswered

    /// The lifter dealt with it and none of the work is behind it (`FR-17.9.6`).
    case skipped

    /// Work was logged against it and it is marked done.
    case logged
}

/// One exercise on a day's checklist — the name, what was planned, what was done, and the answer
/// (`FR-17.9.1`).
///
/// **Its identity is the entry's once the day has a session and the routine slot's before that.**
/// A day nobody has logged into has no entries to name, so a row drawn from the plan has to be
/// addressable all the same — the first answer creates the session and ``DayStore`` maps the slot
/// onto the entry the copy wrote for it (`FR-17.9.5`).
public struct DayRow: Identifiable, Equatable, Sendable {
    /// The entry, or the routine slot on a day not yet started.
    public let id: UUID

    /// The catalogue row, or `nil` where it no longer has one.
    ///
    /// Carried whole rather than as a name, on ``WeekPlanLine/exercise``'s rule: which of an
    /// exercise's two names reads is the locale's question, and a store has no locale.
    public let exercise: Exercise?

    /// What the routine prescribed, in order. Empty for a row the lifter added (`FR-1.2.2`).
    public let plan: [WeekPlanTarget]

    /// What was actually logged against it, run-length encoded — see ``DayPerformance``. Empty
    /// where nothing was.
    public let performed: [WeekPlanTarget]

    /// What has been said about it.
    public let answer: DayRowAnswer

    /// Every scheme this row's work holds a personal record at (`FR-1.6.3`, `FR-16.2.4`).
    ///
    /// **On the row rather than looked up by the view**, on `SessionExerciseCardView`'s rule for
    /// the same badge: the cache read is the store's, and a row is what a reference renders.
    ///
    /// **Gathered over the row's runs, and the badge names the maximal one.** The cache names a run
    /// by its first set, which is the identifier ``DayPerformance/runs(of:)`` gives each run — so a
    /// row of five sets holding the 1RM through the 5RM carries one badge, not five.
    public let records: [RecordScheme]

    /// Builds the row.
    ///
    /// - Parameters:
    ///   - id: The entry, or the slot.
    ///   - exercise: The catalogue row.
    ///   - plan: What was prescribed.
    ///   - performed: What was logged, encoded.
    ///   - answer: What has been said about it.
    ///   - records: The schemes its work holds a record at.
    public init(
        id: UUID,
        exercise: Exercise?,
        plan: [WeekPlanTarget],
        performed: [WeekPlanTarget] = [],
        answer: DayRowAnswer = .unanswered,
        records: [RecordScheme] = []
    ) {
        self.id = id
        self.exercise = exercise
        self.plan = plan
        self.performed = performed
        self.answer = answer
        self.records = records
    }

    /// Whether the row carries `FR-17.9.2`'s circle — see ``DayRowCircle``.
    public var hasCircle: Bool { DayRowCircle.isOffered(answer: answer, plan: plan) }

    /// Whether what was logged is exactly what was planned (`FR-17.9.3`).
    ///
    /// **Compared on the load, the reps and the count, and never on the group's identity.** The two
    /// sides carry different ids by construction — the plan's are the routine's target groups and
    /// the performed side's are the first set of each run — so an `==` over the whole value would
    /// answer *false* for a row the circle had just written, which is exactly the row this is
    /// asked about most.
    ///
    /// **Both sides are collapsed first**, so a routine that prescribes `100 × 5 × 3` then
    /// `100 × 5 × 2` reads as planned against five sets of it: the group boundary is the routine's
    /// bookkeeping rather than a claim about the work.
    public var wasAsPlanned: Bool {
        guard !plan.isEmpty, !performed.isEmpty else { return false }
        return DayPerformance.collapsed(plan).map(Self.shape)
            == DayPerformance.collapsed(performed).map(Self.shape)
    }

    /// What one group prescribes or records, without its identity.
    ///
    /// - Parameter target: The group.
    /// - Returns: Its load, reps and count.
    private static func shape(_ target: WeekPlanTarget) -> [Int] {
        [target.weight?.grams ?? -1, target.reps, target.sets]
    }
}

/// Whether one row offers `FR-17.9.2`'s one-tap circle.
///
/// **Off the view so a test can reach it**, which is `T-16.17`'s rule and `T-17.10`'s brief for this
/// task: what a row offers when it is pending, skipped or answered-but-empty is exactly the kind of
/// rule that, written as a condition inside a `body`, no test can fail.
enum DayRowCircle {
    /// Whether the circle is drawn.
    ///
    /// **Three refusals, and each is a different fact.** An answered row is inert — changing an
    /// answer is **Log**'s (`FR-17.7.5`). A row the lifter added has no plan to perform (`FR-1.2.2`),
    /// so there is nothing "as planned" would mean. And a plan naming no load prescribes the reps
    /// and leaves the weight to the lifter (`FR-15.2.2`): a circle there would have to invent a
    /// zero, which is the distinction that requirement exists for.
    ///
    /// **Every group has to name a load, not merely the first.** The circle writes the whole
    /// exercise in one tap, so a plan whose backoff sets are open-load is one this command could
    /// only half perform.
    ///
    /// - Parameters:
    ///   - answer: What has been said about the row.
    ///   - plan: What was prescribed for it.
    /// - Returns: Whether the circle is offered.
    static func isOffered(answer: DayRowAnswer, plan: [WeekPlanTarget]) -> Bool {
        answer == .unanswered && !plan.isEmpty && plan.allSatisfy { $0.weight != nil }
    }
}

/// What was logged against one exercise, as few lines as it can honestly be said in
/// (`FR-17.9.3`).
///
/// **``WeekPlanTarget`` again rather than a shape of its own**, so the planned line and the
/// performed line are rendered by one function: `140 kg × 5 × 5` means the same thing whichever
/// side of *Planned* / *Did* it is on, and two renderers would be two chances for them to disagree.
///
/// **Warmups are absent.** They are not the work anywhere else in this app, and a *Did* line that
/// counted them would report an exercise as over-performed for warming up to it.
enum DayPerformance {
    /// The working sets, collapsed into runs of equal load and reps.
    ///
    /// **Run-length encoded rather than listed**, because a checklist row is one line: five sets at
    /// the same weight read as `× 5`, and a lifter who dropped the load for the last two gets two
    /// runs rather than five rows.
    ///
    /// **A set's own id names its run**, so the value is stable across a re-read and needs no
    /// invented identifier.
    ///
    /// - Parameter sets: Every set logged against the entry, in order.
    /// - Returns: The runs, in the order they were logged.
    static func runs(of sets: [SetEntry]) -> [WeekPlanTarget] {
        var runs: [WeekPlanTarget] = []
        for set in sets where !set.isWarmup {
            if let last = runs.last, last.weight == set.weight, last.reps == set.reps {
                runs[runs.count - 1] = WeekPlanTarget(
                    id: last.id, weight: last.weight, reps: last.reps, sets: last.sets + 1)
            } else {
                runs.append(
                    WeekPlanTarget(id: set.id, weight: set.weight, reps: set.reps, sets: 1))
            }
        }
        return runs
    }

    /// The same collapsing applied to a *plan*, so the two sides compare like with like.
    ///
    /// A routine that prescribes `100 × 5 × 3` then `100 × 5 × 2` prescribes five sets of the same
    /// thing, and a lifter who performs them has performed the plan — the group boundary is the
    /// routine's bookkeeping, not a claim about the work.
    ///
    /// - Parameter targets: The plan's groups, in order.
    /// - Returns: The runs.
    static func collapsed(_ targets: [WeekPlanTarget]) -> [WeekPlanTarget] {
        var runs: [WeekPlanTarget] = []
        for target in targets {
            if let last = runs.last, last.weight == target.weight, last.reps == target.reps {
                runs[runs.count - 1] = WeekPlanTarget(
                    id: last.id,
                    weight: last.weight,
                    reps: last.reps,
                    sets: last.sets + target.sets)
            } else {
                runs.append(target)
            }
        }
        return runs
    }
}

/// How far through the day the lifter is — `FR-17.9.1`'s `n of m done`.
///
/// A value rather than two counts read off a view, for ``SessionProgress``'s reason: the claim is
/// assertable without rendering anything.
public struct DayProgress: Equatable, Sendable {
    /// How many rows have been answered, by any of the three routes.
    public let answered: Int

    /// How many there are.
    public let total: Int

    /// Reads the progress off the day's rows.
    ///
    /// **A skip counts as answered**, which is the whole of `FR-17.9.6`: a lifter who decided
    /// against an exercise has dealt with it, and a counter that disagreed would leave the day
    /// unfinishable.
    ///
    /// - Parameter rows: The day's rows, in order.
    public init(_ rows: [DayRow]) {
        total = rows.count
        answered = rows.count { $0.answer != .unanswered }
    }

    /// Whether every row has been answered, and there is at least one.
    ///
    /// **An empty day is not a finished one**, which is ``WeekState``'s rule for the same fact: a
    /// session with no entries satisfies "every exercise is answered" vacuously, and a day declared
    /// done the instant it was opened would be a claim about a workout nobody logged.
    public var isComplete: Bool { total > 0 && answered == total }

    /// Whether the day's two whole-day commands are offered (`FR-17.9.9`).
    ///
    /// **Only while something is unanswered.** Both commands answer *the rest*, so on a finished
    /// day they would be two buttons with nothing to do.
    public var offersWholeDayCommands: Bool { total > 0 && answered < total }
}
