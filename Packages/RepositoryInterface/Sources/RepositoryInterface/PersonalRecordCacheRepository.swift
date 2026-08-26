import Foundation
import PowerliftingCore

/// One N-rep max as a *writer* states it (`TR-1.6`).
///
/// **No identity and no exercise**, which is what makes the write below unambiguous: a cached row is
/// identified by the `(exercise, repCount)` pair the call already names, so an `id` here would be a
/// second answer to a question the parameters have settled, and an `exerciseID` a way to write a
/// record into an exercise the caller did not ask for. The audit columns are absent for the reason
/// they are absent everywhere on the way in — they belong to the write path (rule 7).
public struct PersonalRecordCacheValues: Sendable, Hashable {
    /// The N this is the record for, **not** the reps the source set was performed for.
    public let repCount: Int

    /// The record weight. Signed: assisted work records a negative load.
    public let weight: Weight

    /// The `SetEntry` holding the record.
    public let sourceSetID: UUID

    /// When the record was set, taken from the source set's session.
    public let achievedAt: Date

    /// The rules version that produced it (`G-1.5`). Never zero, which means no version was
    /// recorded — unchecked here, as every range on a record is.
    public let computationVersion: Int

    /// Creates the values one cached row is written from.
    public init(
        repCount: Int,
        weight: Weight,
        sourceSetID: UUID,
        achievedAt: Date,
        computationVersion: Int
    ) {
        self.repCount = repCount
        self.weight = weight
        self.sourceSetID = sourceSetID
        self.achievedAt = achievedAt
        self.computationVersion = computationVersion
    }
}

/// The `PersonalRecordCache` rows for one exercise (`TR-1.6`, `G-1.5`).
///
/// **The sixth protocol, and it is younger than the other five on purpose.** `TR-0.4.1` names five
/// and Phase 0 declined to mint this one, because no Phase 0 requirement asked a repository to read
/// or write the cache: the entity existed for `FR-1.11.3`'s backup and nothing else. `TR-1.6` is
/// what asks, so this is where it lands.
///
/// **Everything it stores is derived and none of it is truth** (`G-1.4`). A caller that cannot read
/// a row recomputes; a caller that reads a row whose ``PersonalRecordCache/computationVersion`` is
/// not the one it computes under must recompute too, and must not trust the row in the meantime —
/// which is why the read returns rows rather than an answer, and why nothing here is called
/// `validRecords`.
public protocol PersonalRecordCacheRepository: Sendable {
    /// One exercise's cached N-rep maxes, ascending by ``PersonalRecordCache/repCount``.
    ///
    /// Rows the caller's rules version did not produce are returned like any other: deciding what a
    /// stale row is worth is the caller's, and a read that hid them would leave nothing to detect
    /// staleness *with*.
    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache]

    /// Makes one exercise's cached records exactly `values` (`TR-1.6`, `FR-1.6.4`).
    ///
    /// **Reconciled per rep count, not cleared and rewritten.** A row's identity is its
    /// `(exerciseID, repCount)` pair, so an N still holding a record keeps the row it had — which is
    /// what lets `FR-1.6.2`'s link to a record survive a recompute that did not move it. An N in
    /// `values` with no row yet gets one; an N with a row and no entry in `values` is **soft-deleted**
    /// (`G-1.3`), because a record that no longer stands is not a record and hard deletion happens
    /// only in a purge.
    ///
    /// **A row that already says what `values` says is not written**, and that is `G-2.4` rather
    /// than tidiness: every save restamps `updatedAt`, the conflict key, so restamping the nine
    /// records a recompute did not move would let a local no-op outrank a real remote edit. A
    /// recompute triggered by a set that beat nothing therefore writes nothing at all.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise whose cache this is. Unchecked — the cache mirrors a
    ///     computation rather than joining to the catalogue, so an exercise that has gone is a
    ///     purge's problem and not a `danglingReference`.
    ///   - values: Every record the exercise now holds. At most one entry per ``PersonalRecordCacheValues/repCount``;
    ///     a repeated one resolves to whichever came last, since the pair is the identity.
    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws
}
