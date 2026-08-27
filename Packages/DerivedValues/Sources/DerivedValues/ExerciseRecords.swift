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
/// **Exactly one of the three contents holds.** A number with no explanation and an explanation
/// with no number are states a screen has to draw, and pairing independent optionals would add
/// combinations it cannot.
///
/// ``formula`` and ``lookback`` travel with it because a computed number means nothing without
/// them: the same sets estimate differently under Brzycki, and "no set in the window" is a
/// different sentence at thirty days than at ninety. **They travel with a manual override too, and
/// took no part in it** — they are what the exercise returns to when the override is cleared
/// (`FR-1.7.5`), the same way a manual training max keeps the percentage it is not computed from
/// (`FR-1.5.1.5`).
public struct EstimatedMax: Sendable, Hashable {
    /// The number, or the reason there is none — exactly one of the three.
    public enum Content: Sendable, Hashable {
        /// The heaviest estimate any in-window set produced.
        case record(DatedRecord)

        /// The number the user entered by hand, which outranks whatever the sets say (`FR-1.7.5`).
        ///
        /// **A `Weight` rather than a ``DatedRecord``, because there is no source set.** A record
        /// names the set that holds it — what `FR-1.7.4` navigates to — and an override has none;
        /// carrying one would mean minting an identifier that resolves to nothing, which is a link
        /// that navigates to a missing session rather than a number that admits it has no source.
        case manual(Weight)

        /// Why neither of the above.
        case absence(EstimateAbsence)
    }

    /// Which of the three this is. A screen switches on it rather than testing three optionals.
    public let content: Content

    /// What this number replaced: the best estimate the exercise held before the day the current one
    /// was set, or `nil` when there is no earlier one (`FR-1.9.1`).
    ///
    /// **`nil` for a manual override and for an absence, and not because it could not be computed.**
    /// An override is a number the user typed, so nothing about the sets is what it moved from
    /// (`FR-1.7.5`); an absence has no number to have moved. A screen therefore never draws a delta
    /// beside either, which is the same rule the provenance line already follows.
    ///
    /// See ``PersonalRecordRecomputer`` for why the comparison excludes the current record's whole
    /// day rather than only its set.
    public let previous: DatedRecord?

    /// The formula it was produced under (`FR-1.7.2`).
    public let formula: E1RMFormulaID

    /// The window it was produced over (`FR-1.7.1`).
    public let lookback: E1RMLookback

    /// The **computed** estimate, or `nil` — a manual override is not one, and asking this is how
    /// a caller finds the set `FR-1.7.4` links to.
    public var record: DatedRecord? {
        guard case .record(let record) = content else { return nil }
        return record
    }

    /// The manual override, or `nil` when the number is computed or absent (`FR-1.7.5`).
    public var manual: Weight? {
        guard case .manual(let weight) = content else { return nil }
        return weight
    }

    /// Why there is none, or `nil` when there is one.
    public var absence: EstimateAbsence? {
        guard case .absence(let absence) = content else { return nil }
        return absence
    }

    /// The number this exercise's e1RM currently *is*, however it was arrived at, or `nil` when
    /// there is none.
    ///
    /// **What a caller wanting the value rather than its provenance reads.** ``record`` alone
    /// silently answers `nil` for an exercise that has an e1RM — the overridden one — which is the
    /// bypass `FR-1.7.5` exists to prevent.
    public var weight: Weight? {
        switch content {
        case .record(let record): record.weight
        case .manual(let weight): weight
        case .absence: nil
        }
    }

    /// Whether the number came from the user rather than from their sets — `FR-1.7.5`'s "clearly
    /// marked as manual", as a screen asks it.
    public var isManual: Bool { manual != nil }

    /// How far the computed number moved, or `nil` where there is nothing to compare (`FR-1.9.1`).
    ///
    /// **It is strictly positive wherever it is not `nil`, and that follows from the definition
    /// rather than from a guard here.** ``previous`` is the best estimate over a *subset* of the
    /// sets the current one is the best over, so it can never exceed it; and a value that merely
    /// matched cannot appear either, ties resolving to the earlier set, which makes the matched
    /// estimate the current one and leaves nothing before it. A caller therefore gets a rise or
    /// nothing — never a fall, and never a zero.
    ///
    /// **The type stays signed anyway**, because ``Weight`` is and because the sign is the honest
    /// carrier of a direction this definition happens not to produce: reading the magnitude out and
    /// asserting the direction here would put a claim in the type that only the definition above
    /// supports. Whether a declining estimate *should* be reportable is `FR-1.9.1`'s own question
    /// and a different definition of "the previous value" — not something this property decides.
    public var delta: Weight? {
        guard case .record(let record) = content, let previous else { return nil }
        return record.weight - previous.weight
    }

    /// An estimate, and what it replaced.
    public init(
        record: DatedRecord,
        previous: DatedRecord? = nil,
        formula: E1RMFormulaID,
        lookback: E1RMLookback
    ) {
        self.init(
            content: .record(record), previous: previous, formula: formula, lookback: lookback)
    }

    /// A manual override.
    public init(manual: Weight, formula: E1RMFormulaID, lookback: E1RMLookback) {
        self.init(content: .manual(manual), formula: formula, lookback: lookback)
    }

    /// The absence of one.
    public init(absence: EstimateAbsence, formula: E1RMFormulaID, lookback: E1RMLookback) {
        self.init(content: .absence(absence), formula: formula, lookback: lookback)
    }

    /// Any of the three, as its content.
    public init(
        content: Content,
        previous: DatedRecord? = nil,
        formula: E1RMFormulaID,
        lookback: E1RMLookback
    ) {
        self.content = content
        self.previous = previous
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

    /// The estimate's computed record alone, for a caller that has already established there is
    /// one. **A manual override answers `nil` here** — see ``EstimatedMax/record``.
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
