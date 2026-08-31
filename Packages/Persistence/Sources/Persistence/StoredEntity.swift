import Foundation
import SwiftData

/// The conventions every entity in this module carries.
///
/// Conformance is the whole mechanism: `G-1.2`'s identity and timestamps, `G-1.3`'s soft delete and
/// `G-2.4`'s conflict key live here and nowhere else, so an entity that opts out is a schema change
/// once rows exist rather than an edit.
///
/// **`id` is non-optional, defaulted, and never unique.** `G-2.5`'s "optional *or defaulted*" is
/// satisfied by the default, which is what lets the column stay non-optional for `G-1.2`. What
/// `G-2.5` does cost is enforcement: with no `@Attribute(.unique)`, uniqueness is an invariant the
/// repository holds rather than one the store checks, and two rows may arrive sharing an `id`. A
/// read that must pick one resolves by `updatedAt` (`G-2.4`). Non-optional matters because entities
/// join by `UUID` field and declare no relationships — `id` is the only join key there is.
///
/// **The default mints identity, so nothing but `init` may reach it.** `= UUID()` is there to
/// satisfy CloudKit, not to supply a missing value: a row arriving without one is given an identity
/// rather than refused, which forks history instead of failing. Down the `init` path that identity
/// is minted per instance — but the **store's** default is frozen once per launch (see
/// ``SchemaDefaults``), so rows that reach it collide on one id rather than fork, and `G-2.5` forbids
/// the unique constraint that would notice. The same shape is a trap in migrations: a non-optional
/// `UUID` column added in a later schema version backfills every existing row from one evaluated
/// default.
///
/// **`updatedAt` is stamped by the save path**, not by callers — see `ModelContext.saveStamped(at:)`,
/// which every mutation reaches the store through. A bare `save()` writes a row whose `updatedAt`
/// describes the write before it, and is a lint error here for that reason.
///
/// **Enum-backed fields are stored as their raw `String`, never as the enum**, with a schema default
/// so an absent value resolves. A `String` column cannot fail to decode, which is what keeps one
/// unreadable field — a laterality or an `E1RMFormulaID` from a newer version — from costing the
/// whole row. Mapping to the domain type, and the fallback when it does not map, belong to the
/// repository layer (`TR-0.4.3`).
protocol StoredEntity: PersistentModel {
    /// Client-generated (`G-1.2`), defaulted rather than optional, and not unique (`G-2.5`).
    var id: UUID { get set }

    /// When the row was first created (`G-1.2`).
    var createdAt: Date { get set }

    /// Last write, and the field-level conflict key `G-2.4` resolves on.
    var updatedAt: Date { get set }

    /// When the row was soft-deleted (`G-1.3`), or `nil` while it is live.
    var deletedAt: Date? { get set }
}

extension StoredEntity {
    /// Whether the row has been soft-deleted.
    ///
    /// Not `isDeleted`: `PersistentModel` already declares one, meaning "deleted from the context
    /// in this transaction", and the two answer different questions.
    var isSoftDeleted: Bool { deletedAt != nil }

    /// Soft-deletes the row (`G-1.3`), leaving it readable to an explicit purge.
    ///
    /// Idempotent in the way that matters: re-deleting keeps the original `deletedAt`, so the time
    /// a row left the user's history survives a repeated call.
    func markDeleted(at now: Date = .now) {
        if deletedAt == nil { deletedAt = now }
        updatedAt = now
    }
}
