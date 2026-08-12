import Foundation

/// The four columns every stored row carries (`G-1.2`, `G-1.3`, `G-2.4`), on the record side of the
/// boundary.
///
/// The counterpart of `Persistence`'s `StoredEntity`, and deliberately the same four names: a
/// mapping that has to rename a column is a mapping with somewhere to make a mistake.
///
/// **Two of the four are read-only in practice, and no signature shows it.** A repository ignores
/// ``updatedAt`` and ``deletedAt`` on the way in — the save path stamps the first (`G-2.4`) and
/// ``deletedAt`` moves only through a repository's soft delete — so a caller that edits either and
/// saves has written nothing. ``createdAt`` is honoured when the row is new and ignored when it is
/// not, which is what lets an import or a restore keep the history it arrived with (`FR-1.11.3`)
/// without a later edit relabelling it.
public protocol StoredRecord: Sendable, Hashable, Identifiable {
    /// Client-generated (`G-1.2`), and **not unique in the store** — see the tiebreak rule in this
    /// module's header.
    var id: UUID { get }

    /// When the row was first written.
    var createdAt: Date { get }

    /// When the row was last written, and the field the duplicate tiebreak resolves on (`G-2.4`).
    var updatedAt: Date { get }

    /// When the row was soft-deleted (`G-1.3`), or `nil` while it is live.
    var deletedAt: Date? { get }
}

extension StoredRecord {
    /// Whether the row has been soft-deleted.
    ///
    /// A read that takes `includingDeleted: false` never returns one of these; the reads that take
    /// no flag at all resolve to a live row for the same reason. It can still be `true` on a record
    /// a caller built, or one an export handed back.
    public var isSoftDeleted: Bool { deletedAt != nil }
}
