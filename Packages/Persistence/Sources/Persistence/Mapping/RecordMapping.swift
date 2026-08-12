// Entity ↔ record mapping, one pair of directions per entity (TR-0.4.3, TR-0.4.4). This is the only
// place a `@Model` and a record are named in the same file, which is what makes it the only place
// either shape can be got wrong.
//
// Each entity gets three members and they do different jobs:
//
//   `var record`             — the row as a record. Total: no column can make it fail, because rule
//                              4 says an unreadable field costs that field and never the row.
//   `init(record:)`          — a NEW row carrying the record.
//   `update(from:)`          — an EXISTING row, overwritten from the record.
//
// THE ROUND TRIP THIS LAYER GUARANTEES IS `entity → record → update(that same entity)`, and it is
// exact for every column of all nine entities, for every value a row can hold — a repeated plate
// denomination and a vocabulary spelling from a newer version included. That is the claim
// `RecordMappingTests` makes, and the two things below are what make it true rather than nearly
// true.
//
// 1. THE FOUR AUDIT COLUMNS ARE NOT WRITTEN BY `update(from:)` AT ALL. `id`, `createdAt`,
//    `updatedAt` and `deletedAt` stay whatever the row already holds, which is rule 7 of the
//    RepositoryInterface header made structural rather than remembered: `updatedAt` belongs to
//    `saveStamped(at:)`, `deletedAt` to `markDeleted(at:)`, and `createdAt` to the insert. A save
//    path that had to restore three columns after every update would be five chances to forget.
//    `init(record:)` does honour `createdAt`, because there the row is new and the record's history
//    is the only history there is (`FR-1.11.3`) — but it leaves `deletedAt` nil, so **a restore
//    that must reinstate soft-deleted rows needs a writer this layer does not provide.** Filed for
//    whoever builds `FR-1.11.3`'s restore; nothing in Phase 0 needs it.
//
// 2. AN UNMAPPABLE VOCABULARY SPELLING IS NOT REWRITTEN ON THE WAY BACK — ON THE THREE COLUMNS
//    WHERE THAT IS SAFE. Reading degrades it, which is the settled fallback rule and
//    `RecordVocabulary` is its table; ``preservingRawValue`` then keeps the stored string whenever
//    the record carries the value that string already resolves to. So a `movementRawValue` of
//    "kettlebellSwing" read on a version that has no such case, and saved back after the user
//    edited the name, is still "kettlebellSwing" — and still correct on the device that wrote it.
//    `G-1.6` forbids modifying logged data, and silently relabelling a column as "other" during an
//    edit to a different column is exactly that.
//
//    **It applies only where the fallback claims nothing**, which is `Movement`, `Equipment` and
//    `BarType` and nothing else. Preservation cannot tell "the caller left this column alone" from
//    "the caller chose the value it already reads as", and where the fallback is a real answer that
//    makes the answer unreachable: a settings column holding a spelling this version cannot read
//    resolves to kilograms, so a user tapping Kilograms writes a record that agrees with the store,
//    so nothing changes, for ever. `RecordVocabulary.Fallback.isUnknownMarker` is where the
//    distinction lives and ``preservingRawValue`` is the only thing that reads it.
//
// 3. TWO MORE COLUMNS ARE NOT WRITTEN BY `update(from:)`, AND BOTH ARE CROSS-ROW INVARIANTS.
//    `UserSettingsEntity.userID` (`TR-1.10` mints it once; the setter is `private(set)`, so the
//    compiler holds this one) and `EquipmentProfileEntity.isDefault` (only `makeDefault(profileID:)`
//    may write it, and `G-2.5` forbids the constraint that would notice two rows claiming it).
//    Neither can be held by a record, because a record is a mirror of one row and these are facts
//    about the *set* of rows — so the mapping declines to write them and a repository's save keeps
//    its promise by doing nothing. `init(record:)` writes both: a new row has no previous value to
//    keep, and a restore has to reinstate what the backup carried.
//
// WHAT IS STILL LOST, AND IT IS THE EXPORT DIRECTION RATHER THAN THIS ONE: a record does not carry
// the original spelling, so `entity → record → a DIFFERENT, NEW entity` writes the fallback. That
// is a backup file's shape, not a defect in this mapping, and it is the cost `Movement.init(from:)`
// already documents. See `RecordVocabulary`.

import Foundation
import PowerliftingCore
import RepositoryInterface

/// The spelling to store for `value`, keeping `stored` when it already means `value` **and** the
/// meaning they share is "unrecognised" rather than a real answer.
///
/// The whole of point 2 above, in one expression and used by all eleven vocabulary columns.
///
/// **The second condition is not a refinement, it is what stops the rule destroying a user's edit.**
/// Preservation works by not being able to tell "the caller left this column alone" from "the caller
/// set it to the value the column already reads as" — which is harmless exactly when that value
/// claims nothing, and a bug when it does not. Only `Movement`, `Equipment` and `BarType` degrade to
/// a case meaning *unrecognised*; the other seven degrade to ordinary answers a user also picks by
/// hand, and preserving those makes the answer **unreachable**: a settings column holding a foreign
/// spelling resolves to kilograms, so a user tapping Kilograms writes a record that agrees with what
/// is stored, so nothing is written, so every later save preserves it again. Same for the default
/// formula, the theme, both rounding strategies, both `.manual` sources and bilateral.
///
/// Where the flag says the fallback is a real answer, the record wins outright: the cost is that a
/// spelling a newer version wrote is overwritten, but only on a row the user actually saved, having
/// been shown the resolved value while they did it.
///
/// - Parameters:
///   - value: What the record says the column now holds.
///   - stored: What the column holds today, mappable or not.
///   - fallback: The `RecordVocabulary` constant for this vocabulary — the same one the read
///     direction resolves through, so the two cannot disagree about what `stored` means, and the
///     only place the marker-versus-answer distinction is recorded.
/// - Returns: `stored` when it resolves to `value` through an unknown marker, otherwise `value`'s
///   own raw spelling.
func preservingRawValue<T>(_ value: T, stored: String, fallback: RecordVocabulary.Fallback<T>) -> String {
    guard fallback.isUnknownMarker else { return value.rawValue }
    return RecordVocabulary.resolve(stored, or: fallback) == value ? stored : value.rawValue
}
