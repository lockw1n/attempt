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
// A LIST READ RESOLVES TOO, PER ID (FR-18.8.1). Rule 2 was implemented for the single-row read and
// left every list read returning both halves of a duplicate pair — which is how the author's phone
// came to list every built-in exercise twice, two synced installs having each seeded under the same
// permanent ids. The rule is the same rule; what a list needs is it applied per `id` rather than
// once. `resolvedRows` is that read and `allRows` is what a write and a purge keep, and the
// extension below says why neither may be the other's default.
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
    rows.max(by: loses)
}

/// Whether `left` loses to `right` under rule 2 — the one comparison, in one place.
///
/// `max(by:)` keeps the first of two rows this calls equal, which is what makes a fully tied pair
/// answer the same way here and in ``oneRowPerID(_:includingDeleted:)``.
private func loses<T: StoredEntity>(_ left: T, _ right: T) -> Bool {
    (left.updatedAt, left.id.uuidString) < (right.updatedAt, right.id.uuidString)
}

/// `rows` reduced to ``resolved(_:)``'s winner per `id`, in the order the store answered, with the
/// soft-delete filter applied to the winners.
///
/// **Resolve first and filter second; the order is the whole rule.** Filtering the match set before
/// resolving lets a live loser stand in for a deleted winner — and that is not a freak state, it is
/// what a mirrored delete looks like: the twins are separate CloudKit records, so a delete made on
/// another device lands on one of them. Filter-then-resolve would hide nothing there and the row
/// the lifter deleted would come back wearing its twin's contents. A soft delete restamps
/// `updatedAt` (`G-2.4`), so the row just deleted *is* the winner, and hiding the winner hides the
/// record.
///
/// **Linear in the rows fetched** — one dictionary, one pass, no second fetch. A group of one,
/// which is every row of a store nothing has duplicated, is carried through untouched.
///
/// **The fetch behind it is wider than it was, and that is what resolve-then-filter costs.** A
/// resolved read asks the store for the soft-deleted rows too and drops them here, where a
/// live-only read let the store drop them before they were ever materialised. Deletion is soft
/// (`G-1.3`) and nothing reclaims rows on a lifter's device, so that population only grows. No
/// requirement asks for a figure at the size this app is used at; the trade is written down so the
/// next reader weighs it rather than rediscovers it.
private func oneRowPerID<T: StoredEntity>(_ rows: [T], includingDeleted: Bool) -> [T] {
    var winner: [UUID: Int] = [:]
    var picked: [T] = []
    picked.reserveCapacity(rows.count)
    for row in rows {
        guard let index = winner[row.id] else {
            winner[row.id] = picked.count
            picked.append(row)
            continue
        }
        if loses(picked[index], row) { picked[index] = row }
    }
    return includingDeleted ? picked : picked.filter { !$0.isSoftDeleted }
}

extension ModelContext {
    // TWO NAMES AND NO DEFAULT, BECAUSE A READ AND A WRITE WANT OPPOSITE ANSWERS TO ONE QUESTION.
    // `resolvedRows` is what a caller is handed: one row per id. `allRows` is what a write needs —
    // a save writes every duplicate and a delete sweeps every duplicate, so neither leaves a twin
    // holding what the caller thought they had replaced — and what `PurgePlan` needs, where an id
    // is freed only when *every* row carrying it is eligible: a purge that resolved first would
    // hard-delete the winner and leave its twin behind. A single function with a flag would make
    // the wrong answer the quiet one at sixty-odd call sites, so there is no flag and no default.

    /// Every row of `type` carrying `id` — all of them, because two rows may.
    func allRows<T: StoredEntity>(
        _ type: T.Type,
        id: UUID,
        includingDeleted: Bool
    ) throws -> [T] {
        let matching = T.matchingID(id)
        return try fetch(
            includingDeleted
                ? FetchDescriptor<T>.includingDeleted(matching: matching)
                : FetchDescriptor<T>.notDeleted(matching: matching)
        )
    }

    /// The one row of `type` carrying `id`, by ``resolved(_:)``, or `nil` if none does.
    ///
    /// **The match set is always the whole one**, soft-deleted rows included, and the flag is
    /// applied to the winner — ``oneRowPerID(_:includingDeleted:)``'s rule, for the same reason.
    func row<T: StoredEntity>(
        _ type: T.Type,
        id: UUID,
        includingDeleted: Bool
    ) throws -> T? {
        guard let winner = resolved(try allRows(type, id: id, includingDeleted: true)) else {
            return nil
        }
        return includingDeleted || !winner.isSoftDeleted ? winner : nil
    }

    /// Every row of `type` matching `predicate`, duplicates and all.
    ///
    /// The one place the `includingDeleted:` flag every protocol carries becomes a choice of
    /// descriptor, so no repository method writes that branch itself.
    func allRows<T: StoredEntity>(
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

    /// Every row of `type`, duplicates and all.
    func allRows<T: StoredEntity>(_ type: T.Type, includingDeleted: Bool) throws -> [T] {
        try fetch(includingDeleted ? .includingDeleted() : .notDeleted())
    }

    /// The rows of `type` matching `predicate`, one per `id` (`FR-18.8.1`).
    ///
    /// **A list keyed on a join column needs this as much as a whole table does.** The entries of a
    /// session, the sets of an exercise, a routine's target groups — each is a set of *different*
    /// ids, any one of which may have been duplicated, so the rule applies per id there too.
    ///
    /// **`predicate` narrows the match set before the rule runs, and `deletedAt` is the only
    /// column exempt.** The deleted flag is held back until the winner is known because it is
    /// applied here, in Swift; every other column a caller filters on is applied by the store, so
    /// a pair whose halves *disagree* about that column is resolved among the halves that matched
    /// and a loser can stand in for a winner the predicate excluded. ``SwiftDataProgramRepository``
    /// has the reachable instance: twins where the winner carries `endedAt` and the stale twin does
    /// not make `currentRun()` answer with the ended run. **This is not decided here and is not
    /// fixed here** — closing it means fetching by `id` and re-applying `predicate` to the winner,
    /// which needs a fifth per-type predicate on ``StoredEntity``, since building one in this
    /// generic context is the `-O` crash that protocol's own comment measures.
    func resolvedRows<T: StoredEntity>(
        _ type: T.Type,
        matching predicate: Predicate<T>,
        includingDeleted: Bool
    ) throws -> [T] {
        oneRowPerID(
            try fetch(FetchDescriptor<T>.includingDeleted(matching: predicate)),
            includingDeleted: includingDeleted)
    }

    /// Every row of `type`, one per `id` (`FR-18.8.1`).
    func resolvedRows<T: StoredEntity>(_ type: T.Type, includingDeleted: Bool) throws -> [T] {
        oneRowPerID(try fetch(.includingDeleted()), includingDeleted: includingDeleted)
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
