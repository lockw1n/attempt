import Foundation
import PowerliftingCore
import RepositoryInterface

/// One PR-setting set, as `FR-1.6.5`'s feed lists it.
///
/// **A set, not a cached row, and that is the whole difference between this and
/// ``DatedRepMax``.** A 140 × 3 that beats the 1RM, 2RM and 3RM writes three rows sharing one
/// `sourceSetID`, one weight and one date; listed as they are stored, a single good session across
/// four exercises fills a reverse-chronological feed with one day of training. A per-exercise list
/// wants the rows — it is a table of ten N's — and a feed wants the events.
///
/// **``reps`` and ``sets`` are ranges because the cells one run holds are contiguous.** A run holds a
/// cell when it is the earliest run at the heaviest load for it; a run that lost a cell to an earlier
/// one lost every cell below it in both dimensions too, so there is no gap for a range to
/// misrepresent. Both are built from the lowest and highest present, so a cache hand-edited into a
/// gap is spanned rather than refused.
///
/// **A run, not a set** (`FR-16.2.4`). One `100 × 5 × 5` fills up to twenty-five cells; listed as
/// they are stored, a single good session would fill the whole feed. The rows are grouped on the
/// run's first set — see ``RepositoryInterface/PersonalRecordCache/sourceSetID``, which is why that
/// identifier is the run's rather than each cell's.
public struct RecentRecord: Sendable, Hashable {
    /// The exercise the record belongs to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The N's this one run is the record for — `1...3` for a 140 × 3 that beat all three.
    public let reps: ClosedRange<Int>

    /// The set counts it is the record for — `1...5` for a `× 5` that beat every one of them
    /// (`FR-16.2.1`).
    public let sets: ClosedRange<Int>

    /// The load. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The run's **first** set, which is the run's identity — see
    /// ``RepositoryInterface/PersonalRecordCache/sourceSetID``. What `FR-16.3.3`'s row navigates to,
    /// and the anchor a reader holding the entry's sets recovers the whole run from.
    public let sourceSetID: UUID

    /// The day it was set, taken from the source set's session.
    public let achievedAt: Date

    /// The load the **maximal** scheme in this event beat, or `nil` where that scheme is a baseline
    /// (`FR-16.2.3`, `FR-16.3.4`).
    ///
    /// **The maximal cell's, not any cell's**, because `FR-16.3.2` shows a run's maximal scheme and
    /// a row's delta has to be that scheme's: a `5 × 5` that is a first-ever `× 5` but an improvement
    /// at `× 1` is a baseline `5 × 5`, and reporting the `× 1`'s delta beside the `5 × 5` label would
    /// be a number about a different record.
    public let previous: Weight?

    /// The maximal scheme this event set — the bottom-right cell of what it holds (`FR-16.3.2`).
    public var scheme: (reps: ClosedRange<Int>, sets: ClosedRange<Int>) { (reps, sets) }

    /// How far the load moved at the maximal scheme, or `nil` for a baseline (`FR-16.3.3`).
    public var delta: Weight? {
        guard let previous else { return nil }
        return weight - previous
    }

    /// Whether the maximal scheme had never been performed for this exercise before (`FR-16.3.4`).
    public var isBaseline: Bool { previous == nil }

    /// Creates one feed entry.
    ///
    /// ``sets`` and ``previous`` default to what an `FR-1.6.1` rep max holds — one set, no beaten
    /// load — so a caller stating a rep max states the same entry it always did.
    public init(
        exerciseID: UUID,
        reps: ClosedRange<Int>,
        sets: ClosedRange<Int> = 1...1,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        previous: Weight? = nil
    ) {
        self.exerciseID = exerciseID
        self.reps = reps
        self.sets = sets
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
        self.previous = previous
    }
}

extension RecentRecord {
    /// `FR-1.6.5`'s feed, from whatever the cache holds.
    ///
    /// **Rows this build did not compute are dropped rather than recomputed** (`G-1.5`). Recomputing
    /// them would be a pass over the whole catalogue on the screen the app launches into, which is
    /// what `FR-1.6.4`'s per-exercise scope and `NFR-1.6` between them rule out; showing them would
    /// present numbers produced under rules this build does not implement. So a rules-version bump
    /// empties the feed and each exercise refills it the next time a set moves it — the per-exercise
    /// list (`FR-1.6.2`) recomputes on read and is where the records stay readable meanwhile.
    ///
    /// **The order is the cache's**, which the repository already guarantees is newest first with a
    /// deterministic tie-break — several exercises' records share a session's date, so the tie-break
    /// is the common case and not the edge. Grouping preserves it: a group takes the position of its
    /// first row.
    ///
    /// - Parameters:
    ///   - cached: The rows, in the order the repository returned them.
    ///   - limit: How many entries the caller draws. Applied after grouping, so a feed of five is
    ///     five *events* rather than five rows that may be one run.
    /// - Returns: The feed, newest first.
    static func feed(from cached: [PersonalRecordCache], limit: Int) -> [RecentRecord] {
        guard limit > 0 else { return [] }
        var order: [Key] = []
        var grouped: [Key: [PersonalRecordCache]] = [:]
        for row in cached
        where row.computationVersion == PersonalRecordCalculator.computationVersion {
            let key = Key(exerciseID: row.exerciseID, sourceSetID: row.sourceSetID)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(row)
        }
        return order.prefix(limit).compactMap { key in
            guard let rows = grouped[key], let first = rows.first else { return nil }
            let reps = rows.map(\.repCount)
            let sets = rows.map(\.setCount)
            guard let lowReps = reps.min(), let highReps = reps.max(),
                let lowSets = sets.min(), let highSets = sets.max(),
                let maximal = rows.max(by: { $0.scheme < $1.scheme })
            else { return nil }
            return RecentRecord(
                exerciseID: key.exerciseID,
                reps: lowReps...highReps,
                sets: lowSets...highSets,
                weight: first.weight,
                sourceSetID: key.sourceSetID,
                achievedAt: first.achievedAt,
                previous: maximal.previousWeight
            )
        }
    }

    /// What makes two cached rows one feed entry.
    ///
    /// **The exercise as well as the set**, though a set belongs to exactly one exercise: the cache
    /// mirrors a computation rather than joining to the catalogue, so nothing in the store enforces
    /// that, and a restored backup that broke it would otherwise merge two exercises' records into
    /// one row.
    ///
    /// **The set is the run's first**, which is what makes this the *run* key `FR-16.2.4` asks the
    /// feed to group on rather than a per-cell one.
    private struct Key: Hashable {
        let exerciseID: UUID
        let sourceSetID: UUID
    }
}
