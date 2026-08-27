import Foundation
import RepositoryInterface

/// `PersonalRecordCacheRepository` over a dictionary (`TR-0.4.2`, `TR-1.6`).
struct InMemoryPersonalRecordCacheRepository: PersonalRecordCacheRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// One exercise's cached records, ascending by rep count.
    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] {
        await store.personalRecords(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    /// Every cached record, newest first.
    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        await store.personalRecords(includingDeleted: includingDeleted)
    }

    /// Reconciles the exercise's rows against `values`.
    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws {
        await store.replacePersonalRecords(forExerciseID: exerciseID, with: values)
    }
}

extension InMemoryRepositoryStore {
    /// One exercise's cached records, ascending by rep count.
    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) -> [PersonalRecordCache] {
        personalRecordCache.values
            .filter { $0.exerciseID == exerciseID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.repCount, $0.id.uuidString) }
    }

    /// Every cached record, newest first — see the protocol for why the sort is written out here.
    func personalRecords(includingDeleted: Bool) -> [PersonalRecordCache] {
        personalRecordCache.values
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically(
                by: { ($0.achievedAt, $0.id.uuidString) }, descending: true)
    }

    /// Makes the exercise's live rows say exactly what `values` says.
    ///
    /// **Keyed on rep count, so a record that did not move keeps its row and its id** — see the
    /// protocol, which is where the reconciliation is specified. A row this leaves alone keeps its
    /// `updatedAt` too, which is the half a fake is easiest to get wrong: `upserted(_:into:at:)`
    /// restamps unconditionally, so the unchanged rows must not go through it at all.
    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) {
        let now = Date.now
        let live = personalRecordCache.values.filter {
            $0.exerciseID == exerciseID && !$0.isSoftDeleted
        }
        let byRepCount = Dictionary(grouping: live, by: \.repCount)

        for value in values {
            guard let rows = byRepCount[value.repCount] else {
                let fresh = PersonalRecordCache(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    exerciseID: exerciseID,
                    repCount: value.repCount,
                    weight: value.weight,
                    sourceSetID: value.sourceSetID,
                    achievedAt: value.achievedAt,
                    computationVersion: value.computationVersion
                )
                personalRecordCache[fresh.id] = fresh
                continue
            }
            for row in rows where !row.states(value) {
                personalRecordCache[row.id] = row.stating(value, at: now)
            }
        }

        let held = Set(values.map(\.repCount))
        for row in live where !held.contains(row.repCount) {
            personalRecordCache[row.id] = row.stamped(
                createdAt: row.createdAt, updatedAt: now, deletedAt: now)
        }
    }
}

extension PersonalRecordCache {
    /// Whether this row already says what `values` says — every column but the audit four.
    func states(_ values: PersonalRecordCacheValues) -> Bool {
        repCount == values.repCount
            && weight == values.weight
            && sourceSetID == values.sourceSetID
            && achievedAt == values.achievedAt
            && computationVersion == values.computationVersion
    }

    /// This row carrying `values`, stamped as written at `now`.
    func stating(_ values: PersonalRecordCacheValues, at now: Date) -> PersonalRecordCache {
        PersonalRecordCache(
            id: id,
            createdAt: createdAt,
            updatedAt: now,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            repCount: values.repCount,
            weight: values.weight,
            sourceSetID: values.sourceSetID,
            achievedAt: values.achievedAt,
            computationVersion: values.computationVersion
        )
    }
}
