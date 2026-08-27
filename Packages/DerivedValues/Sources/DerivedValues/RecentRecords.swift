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
/// **``reps`` is a range because the N's one set holds are contiguous.** A set holds N when it is
/// the earliest set at the heaviest load for that N; a set that lost N to an earlier one lost every
/// N below it too, so there is no gap for a range to misrepresent. Built from the lowest and highest
/// N present, so a cache hand-edited into a gap is spanned rather than refused.
public struct RecentRecord: Sendable, Hashable {
    /// The exercise the record belongs to. Records are never compared across exercises.
    public let exerciseID: UUID

    /// The N's this one set is the record for — `1...3` for a 140 × 3 that beat all three.
    public let reps: ClosedRange<Int>

    /// The load. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The set that holds it.
    public let sourceSetID: UUID

    /// The day it was set, taken from the source set's session.
    public let achievedAt: Date

    /// Creates one feed entry.
    public init(
        exerciseID: UUID,
        reps: ClosedRange<Int>,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date
    ) {
        self.exerciseID = exerciseID
        self.reps = reps
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
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
    ///     five *events* rather than five rows that may be one set.
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
            guard let low = reps.min(), let high = reps.max() else { return nil }
            return RecentRecord(
                exerciseID: key.exerciseID,
                reps: low...high,
                weight: first.weight,
                sourceSetID: key.sourceSetID,
                achievedAt: first.achievedAt
            )
        }
    }

    /// What makes two cached rows one feed entry.
    ///
    /// **The exercise as well as the set**, though a set belongs to exactly one exercise: the cache
    /// mirrors a computation rather than joining to the catalogue, so nothing in the store enforces
    /// that, and a restored backup that broke it would otherwise merge two exercises' records into
    /// one row.
    private struct Key: Hashable {
        let exerciseID: UUID
        let sourceSetID: UUID
    }
}
