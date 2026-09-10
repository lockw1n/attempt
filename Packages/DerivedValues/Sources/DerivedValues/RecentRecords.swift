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
/// **A run, not a set** (`FR-16.2.4`). The rows are grouped on the run's first set — see
/// ``RepositoryInterface/PersonalRecordCache/sourceSetID``, which is why that identifier is the
/// run's rather than each cell's.
///
/// **One run holds one cell** (`FR-17.2.1`), so ``scheme`` is the whole of what this row is the
/// record for and there is nothing else to state. The staircase argument this type carried — which
/// N's a run took within the `sets == 1` column, and why that span was contiguous where the
/// two-dimensional one was not — described the withdrawn dominance rule and went with it, along
/// with the `repMaxReps` it justified.
public struct RecentRecord: Sendable, Hashable {
    /// The exercise the record belongs to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The scheme this run set — the one cell it holds (`FR-16.3.2`, `FR-17.2.1`).
    public let scheme: RecordScheme

    /// The load. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The run's **first** set, which is the run's identity — see
    /// ``RepositoryInterface/PersonalRecordCache/sourceSetID``. What `FR-16.3.3`'s row navigates to,
    /// and the anchor a reader holding the entry's sets recovers the whole run from.
    public let sourceSetID: UUID

    /// The day it was set, taken from the source set's session.
    public let achievedAt: Date

    /// The load ``scheme`` beat, or `nil` where it is a baseline (`FR-16.2.3`, `FR-16.3.4`).
    public let previous: Weight?

    /// How far the load moved at ``scheme``, or `nil` for a baseline (`FR-16.3.3`).
    public var delta: Weight? {
        guard let previous else { return nil }
        return weight - previous
    }

    /// Whether ``scheme`` had never been performed for this exercise before (`FR-16.3.4`).
    public var isBaseline: Bool { previous == nil }

    /// Creates one feed entry.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise.
    ///   - scheme: The cell the run set.
    ///   - weight: The load.
    ///   - sourceSetID: The run's first set.
    ///   - achievedAt: The day.
    ///   - previous: What the scheme beat, or `nil` for a baseline (`FR-16.2.3`).
    public init(
        exerciseID: UUID,
        scheme: RecordScheme,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        previous: Weight? = nil
    ) {
        self.exerciseID = exerciseID
        self.scheme = scheme
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
            // The grouping survives `FR-17.2.1` even though a run now writes one row, and the
            // maximal pick with it: the rows are the cache's, so a store restored from a backup
            // another build wrote can still hold several under one key, and a row picked at random
            // there would carry a delta belonging to a scheme the label does not name.
            guard let rows = grouped[key], let first = rows.first,
                let maximal = rows.max(by: { $0.scheme < $1.scheme })
            else { return nil }
            return RecentRecord(
                exerciseID: key.exerciseID,
                scheme: maximal.scheme,
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
    /// feed to group on rather than a per-cell one — the two coincide since `FR-17.2.1`, and the
    /// key stays the run's because that is what the requirement asks for.
    private struct Key: Hashable {
        let exerciseID: UUID
        let sourceSetID: UUID
    }
}
