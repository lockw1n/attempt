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

/// Everything one recompute of one exercise produced (`FR-1.6.1`, `FR-1.7.1`).
///
/// **The two halves have different lifetimes, which is why they are usually read apart.** The rep
/// maxes are cached (`TR-0.3.9`) and survive until a set moves; the estimate is recomputed every
/// time because it depends on a setting a version cannot carry (`CachedDerivedEntity`). They arrive
/// together only here, from the one walk that produced both — see
/// ``PersonalRecordRecomputer/recompute(forExerciseID:)``.
public struct ExerciseRecords: Sendable, Hashable {
    /// The exercise these belong to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The N-rep maxes, ascending by ``DatedRepMax/reps``. An N no set reached is **absent**, not
    /// present at zero — `Weight` is signed, so zero is a real load.
    public let repMaxes: [DatedRepMax]

    /// The heaviest estimate any set produced under ``formula``, or `nil` when none did.
    public let bestE1RM: DatedRecord?

    /// The formula ``bestE1RM`` was produced under. Carried because the number means nothing without
    /// it and nothing else on this value records which one was in force.
    public let formula: E1RMFormulaID

    /// Creates one exercise's records.
    public init(
        exerciseID: UUID,
        repMaxes: [DatedRepMax],
        bestE1RM: DatedRecord?,
        formula: E1RMFormulaID
    ) {
        self.exerciseID = exerciseID
        self.repMaxes = repMaxes
        self.bestE1RM = bestE1RM
        self.formula = formula
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
