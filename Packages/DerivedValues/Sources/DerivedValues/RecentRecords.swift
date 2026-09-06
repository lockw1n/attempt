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
/// **A run, not a set** (`FR-16.2.4`). One `100 × 5 × 5` fills up to twenty-five cells; listed as
/// they are stored, a single good session would fill the whole feed. The rows are grouped on the
/// run's first set — see ``RepositoryInterface/PersonalRecordCache/sourceSetID``, which is why that
/// identifier is the run's rather than each cell's.
///
/// **What a run holds is not a rectangle, so this states two exact things rather than one
/// approximate one.** A pair of `(reps, sets)` ranges would describe a box, and the cells a run
/// actually takes are a staircase: a heavy single standing at `1 × 1` blocks that one cell and
/// nothing else, so a later `100 × 5 × 5` holds twenty-four of its twenty-five and a box spanning
/// `1...5 × 1...5` claims the twenty-fifth at a load the lifter never lifted for it. So the type
/// carries ``scheme`` — the one cell `FR-16.3.2` shows — and ``repMaxReps``, which is exact for the
/// different reason: within the `sets == 1` column the held N's really are contiguous, a run that
/// lost an N there having lost every N below it too.
public struct RecentRecord: Sendable, Hashable {
    /// The exercise the record belongs to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The maximal scheme this run set — the bottom-right cell of what it holds (`FR-16.3.2`).
    ///
    /// **Always a cell the run really holds.** The highest reps and the highest set count a run
    /// reached are the corner nothing standing can block: every other cell in its rectangle is
    /// dominated by an equal or heavier record wherever this one is beaten, so if the run set
    /// anything at all it set this.
    public let scheme: RecordScheme

    /// The N's this run is the record for **at a single set** — `1...3` for a 140 × 3 that beat all
    /// three (`FR-1.6.1`) — or `nil` where it set no rep max at all.
    ///
    /// **`nil` is the case the second dimension introduced**, and it is why this is not simply the
    /// span of ``scheme``: a `100 × 5 × 5` performed after a heavier single of five holds cells at
    /// two sets and up, and nothing in the one-set column. Reading it as a rep max would label the
    /// feed's row with an N-rep max the lifter's history contradicts.
    public let repMaxReps: ClosedRange<Int>?

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

    /// How far the load moved at the maximal scheme, or `nil` for a baseline (`FR-16.3.3`).
    public var delta: Weight? {
        guard let previous else { return nil }
        return weight - previous
    }

    /// Whether the maximal scheme had never been performed for this exercise before (`FR-16.3.4`).
    public var isBaseline: Bool { previous == nil }

    /// Creates one feed entry.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise.
    ///   - scheme: The maximal cell the run set.
    ///   - repMaxReps: The N's it holds at a single set, or `nil` for a run that set no rep max.
    ///     Stated rather than defaulted: `nil` and "the one-set column" are the distinction this
    ///     type exists to keep, and a default would let a caller lose it by saying nothing.
    ///   - weight: The load.
    ///   - sourceSetID: The run's first set.
    ///   - achievedAt: The day.
    ///   - previous: What the maximal scheme beat, or `nil` for a baseline (`FR-16.2.3`).
    public init(
        exerciseID: UUID,
        scheme: RecordScheme,
        repMaxReps: ClosedRange<Int>?,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        previous: Weight? = nil
    ) {
        self.exerciseID = exerciseID
        self.scheme = scheme
        self.repMaxReps = repMaxReps
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
            guard let rows = grouped[key], let first = rows.first,
                let maximal = rows.max(by: { $0.scheme < $1.scheme })
            else { return nil }
            let singles = rows.filter { $0.setCount == 1 }.map(\.repCount)
            let repMaxReps = singles.min().flatMap { low in singles.max().map { low...$0 } }
            return RecentRecord(
                exerciseID: key.exerciseID,
                scheme: maximal.scheme,
                repMaxReps: repMaxReps,
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
