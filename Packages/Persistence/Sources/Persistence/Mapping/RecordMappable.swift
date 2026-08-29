import Foundation
import RepositoryInterface
import SwiftData

/// An entity that has a record, in both directions (`TR-0.4.3`, `TR-0.4.4`).
///
/// The three members already exist on all nine entities; this states them as a shape so the upsert
/// every `save(_:)` performs can be written **once**. Five hand-written copies of "fetch by id,
/// insert if absent, update every row if not" would be five places for the id rule and the
/// soft-deleted-target rule to differ, and both are decisions rather than mechanics — see
/// `ModelContext.upsert(_:as:onInsert:)`.
protocol RecordMappable: StoredEntity {
    /// The record shape mirroring this entity's columns.
    associatedtype Record: StoredRecord

    /// The row as a record. Total — no column can make it fail.
    var record: Record { get }

    /// A new row carrying `record`, including its `createdAt`.
    init(record: Record)

    /// Overwrites this row from `record`, leaving the four audit columns alone.
    func update(from record: Record)
}

extension ModelContext {
    /// Inserts `record` as a new row, or overwrites **every** row already carrying its id.
    ///
    /// Two decisions live here rather than in five save methods, and neither is visible in a
    /// protocol signature:
    ///
    /// **Every duplicate is written, not just the one a read would return.** Updating only the
    /// tiebreak winner leaves the loser holding what the caller thought they had replaced, and a
    /// later sync touching the loser's `updatedAt` makes it win — so the user's edit reverts on its
    /// own, long afterwards. Writing all of them converges instead, and it is a write doing it: no
    /// read repairs the store.
    ///
    /// **A soft-deleted row is found and overwritten, and stays deleted.** The lookup includes
    /// deleted rows because the alternative is inserting a second row under an id the store already
    /// holds — a duplicate manufactured by the one operation that exists to prevent them.
    /// `update(from:)` does not touch `deletedAt` (rule 7), so nothing is resurrected: rule 3 says
    /// there is no undelete, and a save is not a request for one.
    ///
    /// - Parameters:
    ///   - record: The record to store.
    ///   - type: The entity to store it as.
    ///   - onInsert: Applied to a newly built row before it is inserted. `EquipmentRepository` is
    ///     the one caller that needs it — see its `save(_:)`.
    func upsert<T: RecordMappable>(
        _ record: T.Record,
        as type: T.Type,
        onInsert: (T) -> Void = { _ in }
    ) throws {
        let existing = try rows(type, id: record.id, includingDeleted: true)
        guard !existing.isEmpty else {
            let entity = T(record: record)
            onInsert(entity)
            insert(entity)
            return
        }
        for row in existing { row.update(from: record) }
    }
}
