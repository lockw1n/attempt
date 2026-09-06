import Foundation
import SwiftData

/// A cached N-rep max (`TR-0.3.9`, `G-1.5`).
///
/// **N-rep maxes only. The omission of a best-e1RM row is deliberate**, not an oversight to be
/// helpfully filled in. An N-rep max reads logged weights, reps and the two `G-1.8` flags and
/// **nothing else**, so one ``computationVersion`` is a complete statement of what produced it. A
/// best e1RM additionally depends on the user's `E1RMFormulaID`, and a version cannot carry a
/// setting — see ``CachedDerivedEntity``. Caching one would need two more columns, a formula and a
/// row-kind discriminator, and `TR-0.3.9` has neither. Best e1RM is recomputed instead (`G-1.4`),
/// which is also what makes `FR-1.7.3`'s retroactive recalculation free.
///
/// **``repCount`` is the N, not the reps the set was performed for.** A 5-rep set holds the 1RM
/// through the 5RM, so one ``sourceSetID`` legitimately appears on five rows at the same
/// ``weightGrams``. Anything treating `(exerciseID, sourceSetID)` as unique is wrong about the
/// definition, not about the schema — and with ``setCount`` a single run legitimately appears on up
/// to sixty.
///
/// **A row is one cell of `FR-16.2.1`'s scheme table**, identified by `(exerciseID, repCount,
/// setCount)`. `FR-1.6.1`'s rep max is the `setCount == 1` column.
@Model
final class PersonalRecordCacheEntity: CachedDerivedEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ExerciseEntity`` the record belongs to. Records are never compared across exercises.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// The N this is the record for — within `PersonalRecords.repRange`, so zero records no N.
    var repCount: Int = 0

    /// How many consecutive sets the scheme asks for — within `SchemeRecordCalculator.setRange`
    /// (`FR-16.2.1`, `TR-16.1`).
    ///
    /// **Defaulted to 1, which is the only safe default for a column added after v1**: every row
    /// written before it existed *was* an `FR-1.6.1` rep max, so the frozen value the migration
    /// backfills is true of the history rather than a claim about it (see ``SchemaV1``'s three
    /// rules). It is free either way — the `TR-16.1` rules-version bump drops every pre-existing row
    /// before anything reads it (`G-1.5`).
    var setCount: Int = 1

    /// The record weight, in grams (`G-1.1`). Signed: assisted work records a negative load.
    var weightGrams: Int = 0

    /// The ``SetEntryEntity`` holding the record.
    ///
    /// `PersonalRecord` reports a *position* in the collection it was handed, not an identity —
    /// `PowerliftingCore` has no `UUID` — so this is resolved by the caller that supplied and
    /// ordered that collection (`TR-0.4.3`).
    var sourceSetID: UUID = SchemaDefaults.unlinkedID

    /// When the record was set, taken from the source set's session.
    var achievedAt: Date = SchemaDefaults.achievedAt

    /// The load this record beat at this scheme, in grams, or `nil` for a baseline (`FR-16.2.3`).
    ///
    /// **Optional, and not only because a baseline has nothing to put here.** `Weight` is signed, so
    /// a beaten load of zero is a real one — and `SchemaV1`'s rules make an optional the column a
    /// later version can add without asserting anything about the rows that predate it.
    var previousWeightGrams: Int?

    /// The rules version that produced this row (`G-1.5`). Zero means none was recorded and matches
    /// no real version; see ``CachedDerivedEntity``.
    var computationVersion: Int = 0

    init(
        id: UUID = UUID(),
        exerciseID: UUID,
        repCount: Int,
        setCount: Int = 1,
        weightGrams: Int,
        sourceSetID: UUID,
        achievedAt: Date,
        previousWeightGrams: Int? = nil,
        computationVersion: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.repCount = repCount
        self.setCount = setCount
        self.weightGrams = weightGrams
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
        self.previousWeightGrams = previousWeightGrams
        self.computationVersion = computationVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
