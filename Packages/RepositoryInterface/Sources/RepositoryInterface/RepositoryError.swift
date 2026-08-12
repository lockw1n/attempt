import Foundation

/// What a repository refuses, as opposed to what the store failed at.
///
/// **Every case here is a write.** No read produces one: a stored value this version cannot map
/// resolves to a fallback and a row whose columns contradict each other comes back intact, both by
/// the rule in this module's header — so a caller displaying history never has to handle an error
/// that would cost it a row. An implementation may still throw something else entirely; a store
/// failure is the store's error, not this.
public enum RepositoryError: Error, Sendable, Hashable {
    /// A write named a row that is not there, or that has been soft-deleted.
    ///
    /// Only raised by an operation that acts on an existing row — a save upserts and never raises
    /// it.
    case recordNotFound(id: UUID)

    /// A write carried a join key naming a row that does not exist (`G-2.5` declares no
    /// relationships, so nothing else would notice).
    ///
    /// Refused rather than stored, because a dangling reference is indistinguishable from a real
    /// one afterwards: the schema's all-zero sentinel marks a key that was *never written*, and one
    /// predicate finds every such row, where a plausible UUID pointing at nothing is found by
    /// nothing.
    case danglingReference(recordID: UUID, referencing: UUID)

    /// A save carried a record no projection can interpret — a plate inventory that repeats a
    /// denomination, a training-max row whose source names a payload column that is `nil`.
    ///
    /// **The write path's half of rule 4, and the reason it exists is that a record does not
    /// validate.** Reading such a row returns it whole, on purpose, so `FR-1.11.3` can export one
    /// for repair; but a row *authored* on this device has no such excuse, and without this case a
    /// save would have no way to refuse one. The refusal would otherwise land at read time, in
    /// `PlateCalculator`, on a screen far from the one that stored it.
    ///
    /// **A save that authors a row raises this; a restore does not.** Tolerating a corrupt row is
    /// the whole point of the record shape, and a restore is the one caller that legitimately writes
    /// one — which is why it needs its own writer anyway, `deletedAt` being the other reason.
    case unusableRecord(recordID: UUID, reason: RecordProjectionError)

    /// A settings save carried a different anonymous user id from the one already stored
    /// (`TR-1.10`).
    ///
    /// Refused rather than ignored: `FR-5.1.2` claims the user's local data under this id, so
    /// silently keeping the stored one would let a caller believe it had moved their history to
    /// another identity.
    case identityAlreadyEstablished(recordID: UUID)
}
