import Foundation
import PowerliftingCore

/// The cell that means **computed, and this exercise holds no record** (`G-1.5`, `OUT-17.4`).
///
/// **A row rather than a column**, and the choice is `G-2.5`'s Production schema being
/// additive-only: a column on the cache entity is a CloudKit field that can never be withdrawn,
/// where a row occupying an impossible cell needs no schema change at all. The cell is impossible
/// because every computed scheme lies within `PersonalRecords.repRange` and
/// `SchemeRecordCalculator.setRange`, both of which start at one — so nothing a walk produces can
/// collide with it, and the `(exerciseID, repCount, setCount)` identity a write reconciles on keeps
/// it exactly one row per exercise.
///
/// **It carries ``PersonalRecordCache/computationVersion`` like any other row**, which is what makes
/// a rules bump drop it without a mechanism of its own (`TR-16.1`).
///
/// **Every reader has to exclude it**, since it is a row claiming a record it does not hold. The
/// per-exercise reads strip it where they decide the cache is current; `FR-1.6.5`'s feed strips it
/// at its own read, and must — the markers of every confirmed-zero exercise share one
/// ``PersonalRecordCache/sourceSetID``, so a feed that kept them would group them into one event.
public enum PersonalRecordCacheMarker {
    /// The cell a marker row occupies. No computed scheme can equal it.
    public static let scheme = RecordScheme(reps: 0, sets: 0)

    /// The set id a marker row names — an all-zero identity, since it names no set.
    ///
    /// Shared by every exercise's marker, which is why a reader excludes markers before grouping
    /// on this column rather than after.
    public static let unlinkedSetID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

extension PersonalRecordCacheValues {
    /// The marker row for an exercise a walk found no record for.
    ///
    /// - Parameter computationVersion: The rules version the walk ran under (`G-1.5`).
    /// - Returns: The values to write, as the exercise's only row.
    public static func confirmedZero(computationVersion: Int) -> Self {
        Self(
            repCount: PersonalRecordCacheMarker.scheme.reps,
            setCount: PersonalRecordCacheMarker.scheme.sets,
            weight: .zero,
            sourceSetID: PersonalRecordCacheMarker.unlinkedSetID,
            achievedAt: .distantPast,
            previousWeight: nil,
            computationVersion: computationVersion)
    }
}

extension PersonalRecordCache {
    /// Whether this row is ``PersonalRecordCacheMarker``'s row rather than a record.
    public var isConfirmedZero: Bool { scheme == PersonalRecordCacheMarker.scheme }
}
