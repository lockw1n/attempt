// How every repository read in this module picks and orders rows, and why none of it is a
// `FetchDescriptor` (TR-0.4.2, G-2.4, G-2.5).
//
// THE TIEBREAK IS NOT EXPRESSIBLE IN A DESCRIPTOR, AND THE SPELLING THAT LOOKS LIKE IT IS WRONG IN
// TWO INDEPENDENT WAYS. Rule 2 of the RepositoryInterface header — later `updatedAt`, then greater
// `id.uuidString` — reads like `sortBy:` plus `fetchLimit = 1`. Both halves were measured against
// the real store before anything here was written:
//
//   - `SortDescriptor(\.id.uuidString)` TYPE-CHECKS AND THEN TRAPS. `UUID` is not `Comparable`, so
//     the second clause has no direct spelling; reaching through to `uuidString` compiles and then
//     kills the process at fetch time — "Invalid KeyPath id.uuidString ... points to a value type:
//     UUID but has additional descendant: uuidString". A crash with no compile-time warning and no
//     error to catch is the worst available failure mode for a rule that only fires on duplicates.
//   - `fetchLimit = 1` OVER `updatedAt` DESCENDING RETURNS AN ARBITRARY ROW UNDER A TIE. Two rows
//     sharing an id and an `updatedAt`, 40 runs over two passes: 13/7 then 12/8, tracking neither
//     insert order nor run index. It is not "whatever the store returns first" — it is not stable
//     within one process either.
//
// So the shape of every read here is FETCH THE WHOLE MATCH SET, RESOLVE IN SWIFT. `fetchLimit`
// appears nowhere in this module, and neither does `sortBy:`:
//
//   - FILTERING IS THE PREDICATE'S. `FetchDescriptor.notDeleted(…)` and its siblings, always —
//     never a hand-built descriptor, which returns soft-deleted history (G-1.3).
//   - ORDERING AND PICKING ARE SWIFT'S, on a key that ends in `id.uuidString` and is therefore
//     total. A descriptor cannot express a total order over these entities, so its order is never
//     the last word; leaving it half-sorted in the descriptor would only hide where the answer is
//     actually decided.
//
// WHAT RULE 2 DOES NOT DECIDE, AND IT IS THE CASE IT WAS WRITTEN FOR. Two rows sharing an `id` also
// share an `id.uuidString`, so the second clause is empty exactly when the first one ties — and
// "two devices writing in the same second" is how the header motivates that clause. The residual is
// two rows with one id, one `updatedAt` and different contents, and no column left to separate
// them: `G-2.4` names `updatedAt` as the conflict key and says nothing about a tie in it. This
// layer does not invent a third clause — it implements the stated order, and ``resolved(_:)``'s own
// note says where the residual goes.

import Foundation
import RepositoryInterface
import SwiftData

/// The row rule 2 picks out of a match set that may hold more than one.
///
/// Later `updatedAt` wins; on a tie, the greater `id.uuidString`. The second clause decides the
/// cross-row cases the rule names — two `EquipmentProfileEntity` rows claiming `isDefault`, two
/// `UserSettingsEntity` rows — where the ids differ and the order is total.
///
/// **It cannot decide rows that share an `id`,** which is the case rule 2 opens with: equal ids have
/// equal `uuidString`s, so a duplicate pair tied on `updatedAt` is tied on the whole key. The
/// answer is then one of the two and this layer does not say which — a fourth clause with no
/// requirement behind it would be a policy invented here, and `G-2.4` is where the silence is.
/// Everything else about such a pair is decided: it is never dropped, both rows are written by a
/// save, and both are swept by a delete.
///
/// - Returns: The winning row, or `nil` when `rows` is empty.
func resolved<T: StoredEntity>(_ rows: [T]) -> T? {
    rows.max { left, right in
        (left.updatedAt, left.id.uuidString) < (right.updatedAt, right.id.uuidString)
    }
}

extension ModelContext {
    /// Every row of `type` carrying `id` — all of them, because two rows may.
    ///
    /// The plural is the point. A save writes each of them and a delete sweeps each of them, so
    /// neither leaves a duplicate holding the value the caller thought they had replaced.
    func rows<T: StoredEntity>(
        _ type: T.Type,
        id: UUID,
        includingDeleted: Bool
    ) throws -> [T] {
        let matching = #Predicate<T> { $0.id == id }
        return try fetch(
            includingDeleted
                ? FetchDescriptor<T>.includingDeleted(matching: matching)
                : FetchDescriptor<T>.notDeleted(matching: matching)
        )
    }

    /// The one row of `type` carrying `id`, by ``resolved(_:)``, or `nil` if none does.
    func row<T: StoredEntity>(
        _ type: T.Type,
        id: UUID,
        includingDeleted: Bool
    ) throws -> T? {
        resolved(try rows(type, id: id, includingDeleted: includingDeleted))
    }

    /// Every row of `type` matching `predicate`, soft-deleted ones included only if asked.
    ///
    /// The one place the `includingDeleted:` flag every protocol carries becomes a choice of
    /// descriptor, so no repository method writes that branch itself.
    func rows<T: StoredEntity>(
        _ type: T.Type,
        matching predicate: Predicate<T>,
        includingDeleted: Bool
    ) throws -> [T] {
        try fetch(
            includingDeleted
                ? FetchDescriptor<T>.includingDeleted(matching: predicate)
                : FetchDescriptor<T>.notDeleted(matching: predicate)
        )
    }

    /// Every row of `type`, soft-deleted ones included only if asked.
    func rows<T: StoredEntity>(_ type: T.Type, includingDeleted: Bool) throws -> [T] {
        try fetch(includingDeleted ? .includingDeleted() : .notDeleted())
    }

    /// Refuses a write whose join key names no row at all.
    ///
    /// **A soft-deleted target is not dangling.** The question is whether the row exists, and rule 3
    /// deletes a session's entries and their sets — so requiring a *live* target would make
    /// re-saving a set inside a deleted session throw `danglingReference`, which describes a
    /// different fault entirely. What the sentinel `SchemaDefaults.unlinkedID` marks, and what this
    /// refuses, is a key pointing at nothing.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when no row of `type` carries `id`.
    func requireReferenced<T: StoredEntity>(_ type: T.Type, id: UUID, from recordID: UUID) throws {
        guard try row(type, id: id, includingDeleted: true) != nil else {
            throw RepositoryError.danglingReference(recordID: recordID, referencing: id)
        }
    }
}

extension Sequence {
    /// `self` ordered by a key that ends in `id.uuidString`, and therefore deterministically.
    ///
    /// Every list a repository returns goes through here. A `SortDescriptor` would put half the
    /// answer in the store and half in Swift while still leaving equal keys in whatever order the
    /// store happened to produce — which is the same defect ``resolved(_:)``'s note measures, one
    /// level up.
    ///
    /// Two overloads rather than one generic over `Key: Comparable`, because **a tuple is not
    /// `Comparable`** — the stdlib gives `<` on tuples of up to six comparable elements as free
    /// operators and no conformance, so a composite key cannot be passed through a constrained
    /// generic at all.
    ///
    /// Both compute each key **once** and sort the pairs. Calling `key` inside the comparator is the
    /// shorter spelling and evaluates it 2·n·log n times instead of n — which the feed's key, a
    /// fresh `id.uuidString` allocation, would pay for on every read of a lifter's whole history.
    func sortedDeterministically<A: Comparable, B: Comparable>(
        by key: (Element) -> (A, B),
        descending: Bool = false
    ) -> [Element] {
        map { (key: key($0), element: $0) }
            .sorted { descending ? $0.key > $1.key : $0.key < $1.key }
            .map { $0.element }
    }

    /// The form for a key with more members than a tuple may carry here.
    func sortedDeterministically<Key: Comparable>(by key: (Element) -> Key) -> [Element] {
        map { (key: key($0), element: $0) }
            .sorted { $0.key < $1.key }
            .map { $0.element }
    }
}
