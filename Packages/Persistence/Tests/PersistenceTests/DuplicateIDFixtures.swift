import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// The pair-building scaffolding the duplicate-id suites share (`FR-18.8.1`).
//
// Split out of the suites because the rule is applied at every list read in the module and the
// tests that pin it do not fit in one file. Both halves of a pair are built the same way whatever
// the table: one record, two rows, one `id`, two `updatedAt` stamps.

/// The losing half's stamp — earlier `updatedAt`, so rule 2 does not pick it.
let twinOlder = Date(timeIntervalSince1970: 1_600_000_000)

/// The winning half's stamp.
let twinNewer = Date(timeIntervalSince1970: 1_600_003_600)

/// A row carrying `record`, stamped `updatedAt` — one half of a duplicate pair.
///
/// Built through `init(record:)` so the pair differs in the column the test reads back and in
/// nothing else, whatever the table.
func twin<T: RecordMappable>(
    _ record: T.Record, as type: T.Type, updatedAt: Date
) -> T {
    let row = T(record: record)
    row.updatedAt = updatedAt
    return row
}

/// `row` carrying `id` and stamped `updatedAt` — the entity-built half of a duplicate pair.
///
/// The record-built ``twin(_:as:updatedAt:)`` above cannot reach the tables whose repositories take
/// their rows from an entity initialiser rather than from a record.
func stamped<T: StoredEntity>(_ row: T, id: UUID, updatedAt: Date) -> T {
    row.id = id
    row.updatedAt = updatedAt
    return row
}

/// One cached record row, built through the entity because the cache is written by a
/// reconciliation rather than from a record.
func cachedRecord(
    id: UUID, exerciseID: UUID, grams: Int, updatedAt: Date
) -> PersonalRecordCacheEntity {
    let row = PersonalRecordCacheEntity(
        exerciseID: exerciseID,
        repCount: 5,
        setCount: 1,
        weightGrams: grams,
        sourceSetID: UUID(),
        achievedAt: twinOlder,
        previousWeightGrams: nil,
        computationVersion: 1,
        createdAt: twinOlder,
        updatedAt: updatedAt
    )
    row.id = id
    return row
}
