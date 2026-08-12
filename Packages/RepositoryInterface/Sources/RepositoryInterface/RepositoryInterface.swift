// The storage boundary: five repository protocols (TR-0.4.1) and the record types their
// signatures are written in (TR-0.4.3, TR-0.4.4).
//
// Constraints on everything in this module:
//
// - No SwiftData, and no dependency on `Persistence`. A consumer reaches storage through these
//   protocols and never through a `@Model` (TR-0.1.2). The direction of the dependency is what
//   enforces it: `Persistence` depends on this package, so no entity type is nameable here even
//   by accident — and every entity is `internal` besides. Verified by the Linux CI job, where
//   SwiftData does not exist at all.
// - A record is a value type mirroring one stored row, column for column. It is not a validated
//   domain type and must not become one — see the refusal rule below.
// - Weights are Int grams (G-1.1), carried as `Weight`, which is a lossless total wrapper over
//   the stored column. A record never holds a `Double` mass.
// - Records and protocols are Sendable (TR-0.1.3), declared explicitly.
//
// Four rules the five protocols share, stated once here rather than eight times in doc comments:
//
// 1. READS RETURN LIVE ROWS. Deletion is soft (G-1.3) and the store filters nothing on its own, so
//    a read that enumerates rows, or fetches one by id, takes `includingDeleted:` and it has no
//    default value. The verbosity is the point: a defaulted flag is one a caller can pass by
//    omission, and the omission would be the reading that returns a user's deleted history.
//
//    THREE READS DO NOT TAKE IT, and each says so on itself rather than relying on this list.
//    `SettingsRepository.settings()`, because a soft-deleted settings row is a withdrawn identity
//    and no requirement describes one. `ExerciseRepository.trainingMax(forExerciseID:on:)` and
//    `EquipmentRepository.defaultProfile()`, because both *resolve* to the one row in force rather
//    than enumerating: a deleted configuration is a configuration the user replaced, and a deleted
//    profile is a gym they left, so including either would answer a question nobody asked with a
//    row the store keeps only for a purge. Their history-shaped siblings — `trainingMaxHistory` and
//    `profiles` — do take the flag, which is where an export or a diagnostic goes.
//
// 2. TWO ROWS MAY SHARE AN id, AND THE TIEBREAK IS FIXED. `G-2.5` forbids `@Attribute(.unique)`,
//    so uniqueness is this layer's invariant rather than the store's and a synced or re-imported
//    row can produce a duplicate. Where a read must return one row it returns the one with the
//    later `updatedAt` (G-2.4); if those are equal it returns the one whose `id.uuidString` sorts
//    later. The second clause is not decoration — `updatedAt` ties are what two devices writing in
//    the same second produce, and "whichever the store returned first" varies between runs. The
//    same order resolves two `EquipmentProfile`s claiming `isDefault` and two `UserSettings` rows.
//    Writes upsert by `id`; nothing here inserts blind.
//
// 3. A SOFT DELETE CASCADES DOWNWARDS AND NEVER UPWARDS. The schema joins by UUID and declares no
//    relationships (G-2.5), so nothing cascades on its own: deleting a session would otherwise
//    leave its sets live, readable, and eligible for a personal record (FR-1.6.x) belonging to a
//    workout the user discarded (FR-1.2.12). So deleting a session deletes its entries and their
//    sets, deleting an entry deletes its sets, and deleting a set touches nothing else. There is
//    no undelete: no requirement asks for one, and a cascade cannot be inverted without recording
//    what it swept.
//
// 4. AN UNREADABLE FIELD COSTS THAT FIELD, NEVER THE ROW; A CROSS-COLUMN CONTRADICTION COSTS
//    NEITHER. A stored enum spelling this version cannot map resolves to the same value the schema
//    defaults that column to, and no read fails because of one — the alternative routes a user's
//    logged history into an error through whichever vocabulary happens to lack a fallback case.
//    A row whose columns contradict each other — a plate inventory with a repeated denomination, a
//    training-max row whose source names a payload column that is nil — is returned intact and
//    refuses only when something asks to *interpret* it. That is why a record mirrors its row
//    rather than embedding a validating domain type: `TR-0.4.4` makes these the future wire format
//    and `FR-1.11.3` a full backup, and a shape that cannot represent a corrupt row cannot export
//    one for repair. The interpreting projections, and the errors they raise, are T-0.41's.
//
// This file declares no types on purpose: a type sharing its module's name causes Swift lookup
// ambiguity. It exists to carry the rules above, which are otherwise recorded nowhere in the
// source tree.
