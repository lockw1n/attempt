import Foundation
import PowerliftingCore
import RepositoryInterface

/// A record, with the set that holds it and the day it was set (`FR-1.6.2`, `TR-0.3.9`).
///
/// **`PowerliftingCore`'s `PersonalRecord` plus the two things it structurally cannot carry.** That
/// module has no `UUID` and no `Date` (`NFR-0.2`), so it reports a *position* in the collection it
/// was handed; resolving that position back to a set and a session is this module's job, and this is
/// the shape it hands on.
public struct DatedRecord: Sendable, Hashable {
    /// The record weight. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The set that holds it — what `FR-1.6.2`'s link navigates to.
    public let sourceSetID: UUID

    /// The day it was set: the source set's session date, or the set's own timestamp when the
    /// session row cannot be read. See ``PersonalRecordRecomputer``.
    public let achievedAt: Date

    /// Creates a dated record.
    public init(weight: Weight, sourceSetID: UUID, achievedAt: Date) {
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
    }
}

/// An N-rep max, dated (`FR-1.6.1`).
public struct DatedRepMax: Sendable, Hashable {
    /// The N this is the record for — **not** the reps the set was performed for. A 5-rep set holds
    /// the 1RM through the 5RM, so one source set legitimately appears five times here.
    public let reps: Int

    /// The record itself.
    public let record: DatedRecord

    /// Creates a dated N-rep max.
    public init(reps: Int, record: DatedRecord) {
        self.reps = reps
        self.record = record
    }
}

/// Why there is no estimated one-rep maximum (`FR-1.7.1`, `FR-1.13.3`).
///
/// **Three reasons, and only one of them is "nothing has been logged".** The other two are the ones
/// `FR-1.13.3` exists for: the lifter did log sets and the number is still absent, and a screen that
/// says "log a set and an estimate appears here" over a twelve-rep set is telling them something
/// they can see is untrue.
///
/// ``refused(_:)`` carries `PowerliftingCore`'s own vocabulary rather than restating it, so a guard
/// added to `E1RMCalculator` cannot be one this layer has no sentence for.
public enum EstimateAbsence: Sendable, Hashable {
    /// Nothing at all has ever been logged against this exercise.
    case noSetsLogged

    /// Sets exist, but none inside the lookback window said anything about a maximum — either none
    /// falls inside it, or every one that does was turned away without a reason worth naming.
    case noneInWindow

    /// The nearest miss among the in-window sets, and why it missed. See `E1RMRefusal`'s ordering.
    case refused(E1RMRefusal)
}

/// `FR-1.7.1`'s answer for one exercise: the estimate, or the reason there is none.
///
/// **Exactly one of ``record`` and ``absence`` is non-`nil`.** A number with no explanation and an
/// explanation with no number are the two states a screen has to draw, and pairing two independent
/// optionals would add two it cannot.
///
/// ``formula`` and ``lookback`` travel with it because the number means nothing without them: the
/// same sets estimate differently under Brzycki, and "no set in the window" is a different sentence
/// at thirty days than at ninety.
public struct EstimatedMax: Sendable, Hashable {
    /// The number, or the reason there is none — never both and never neither.
    public enum Content: Sendable, Hashable {
        /// The heaviest estimate any in-window set produced.
        case record(DatedRecord)

        /// Why none did.
        case absence(EstimateAbsence)
    }

    /// Which of the two this is. A screen switches on it rather than testing two optionals.
    public let content: Content

    /// The formula it was produced under (`FR-1.7.2`).
    public let formula: E1RMFormulaID

    /// The window it was produced over (`FR-1.7.1`).
    public let lookback: E1RMLookback

    /// The estimate, or `nil`.
    public var record: DatedRecord? {
        guard case .record(let record) = content else { return nil }
        return record
    }

    /// Why there is none, or `nil` when there is one.
    public var absence: EstimateAbsence? {
        guard case .absence(let absence) = content else { return nil }
        return absence
    }

    /// An estimate.
    public init(record: DatedRecord, formula: E1RMFormulaID, lookback: E1RMLookback) {
        self.init(content: .record(record), formula: formula, lookback: lookback)
    }

    /// The absence of one.
    public init(absence: EstimateAbsence, formula: E1RMFormulaID, lookback: E1RMLookback) {
        self.init(content: .absence(absence), formula: formula, lookback: lookback)
    }

    /// Either, as its content.
    public init(content: Content, formula: E1RMFormulaID, lookback: E1RMLookback) {
        self.content = content
        self.formula = formula
        self.lookback = lookback
    }
}

/// Everything one recompute of one exercise produced (`FR-1.6.1`, `FR-1.7.1`).
///
/// **The two halves have different lifetimes, which is why they are usually read apart.** The rep
/// maxes are cached (`TR-0.3.9`) and survive until a set moves; the estimate is recomputed every
/// time because it depends on a setting a version cannot carry (`CachedDerivedEntity`). They arrive
/// together only here, from the one walk that produced both — see
/// ``PersonalRecordRecomputer/recompute(forExerciseID:)``.
///
/// **The halves are also computed over different sets.** A rep max is all-time (`FR-1.6.1`); an
/// estimate reads only the lookback window (`FR-1.7.1`), so an exercise can hold a 5RM from last
/// year and no current estimate at all.
public struct ExerciseRecords: Sendable, Hashable {
    /// The exercise these belong to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The N-rep maxes, ascending by ``DatedRepMax/reps``. An N no set reached is **absent**, not
    /// present at zero — `Weight` is signed, so zero is a real load.
    public let repMaxes: [DatedRepMax]

    /// The current estimated one-rep maximum, or why there is none.
    public let estimate: EstimatedMax

    /// The estimate's record alone, for a caller that has already established there is one.
    public var bestE1RM: DatedRecord? { estimate.record }

    /// The formula the estimate was produced under.
    public var formula: E1RMFormulaID { estimate.formula }

    /// Creates one exercise's records.
    public init(exerciseID: UUID, repMaxes: [DatedRepMax], estimate: EstimatedMax) {
        self.exerciseID = exerciseID
        self.repMaxes = repMaxes
        self.estimate = estimate
    }

    /// The N-rep max for `reps`, or `nil` when no set reached that many.
    ///
    /// A lookup, not a guard: it finds whatever ``repMaxes`` holds.
    public func repMax(forReps reps: Int) -> DatedRecord? {
        repMaxes.first { $0.reps == reps }?.record
    }
}

/// What changed, as the recompute pipeline announces it (`TR-1.5`, `TR-1.6`).
public enum RecordChange: Sendable, Hashable {
    /// One exercise's records were recomputed. Everything else is untouched.
    case exercise(UUID)

    /// A setting moved, so every derived value in the app is stale (`FR-1.6.4`, `FR-1.7.3`).
    ///
    /// **The cache is not invalidated by this and must not be.** An N-rep max reads logged weights,
    /// reps and the two `G-1.8` flags and no setting at all, which is exactly why `TR-0.3.9` may
    /// cache it; what goes stale is every estimate, and nothing caches one.
    case everyExercise
}
