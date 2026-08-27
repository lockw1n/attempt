import Foundation
import RepositoryInterface
import SwiftData

/// `PersonalRecordCacheRepository` over SwiftData (`TR-1.6`, `TR-0.3.9`).
///
/// The only table in the schema holding nothing but values something else computed, which is what
/// makes ``replacePersonalRecords(forExerciseID:with:)`` a reconciliation rather than a save.
@ModelActor
actor SwiftDataPersonalRecordCacheRepository: PersonalRecordCacheRepository {
    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) throws -> [PersonalRecordCache] {
        try modelContext.rows(
            PersonalRecordCacheEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically { ($0.repCount, $0.id.uuidString) }
        .map(\.record)
    }

    /// Every cached record, newest first.
    ///
    /// **Sorted here rather than by the descriptor**, which is what the tie-break costs: `achievedAt`
    /// is a stored column and `id.uuidString` is not, so a store-side sort could order the dates and
    /// nothing else — and the ties are the common case, since every record a session set carries that
    /// session's date.
    func personalRecords(includingDeleted: Bool) throws -> [PersonalRecordCache] {
        try modelContext.rows(PersonalRecordCacheEntity.self, includingDeleted: includingDeleted)
            .map(\.record)
            .sortedDeterministically(
                by: { ($0.achievedAt, $0.id.uuidString) }, descending: true)
    }

    /// Makes the exercise's live rows say exactly what `values` says.
    ///
    /// **Every duplicate of a rep count is rewritten, not just the tiebreak winner** — the same rule
    /// a save follows everywhere in this module. Rewriting one of a duplicate pair would leave the
    /// other holding a record the recompute has already superseded, readable the next time it won.
    ///
    /// **Nothing is saved unless something moved.** The `changed` flag is not an optimisation: a
    /// recompute runs on every logged set and almost all of them beat nothing, so an unconditional
    /// save would restamp ten rows' `updatedAt` — `G-2.4`'s conflict key — per set logged.
    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) throws {
        let stored = try modelContext.rows(
            PersonalRecordCacheEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: false
        )
        let byRepCount = Dictionary(grouping: stored, by: \.repCount)
        let now = Date.now
        var changed = false

        for value in values {
            guard let rows = byRepCount[value.repCount] else {
                modelContext.insert(
                    PersonalRecordCacheEntity(
                        exerciseID: exerciseID,
                        repCount: value.repCount,
                        weightGrams: value.weight.grams,
                        sourceSetID: value.sourceSetID,
                        achievedAt: value.achievedAt,
                        computationVersion: value.computationVersion,
                        createdAt: now,
                        updatedAt: now
                    ))
                changed = true
                continue
            }
            for row in rows where !row.states(value) {
                row.apply(value)
                changed = true
            }
        }

        let held = Set(values.map(\.repCount))
        for row in stored where !held.contains(row.repCount) {
            row.markDeleted(at: now)
            changed = true
        }

        if changed { try modelContext.saveStamped(at: now) }
    }
}

extension PersonalRecordCacheEntity {
    /// Whether this row already says what `values` says — every column but the audit four.
    ///
    /// `exerciseID` is not compared: the row was fetched *by* it.
    func states(_ values: PersonalRecordCacheValues) -> Bool {
        repCount == values.repCount
            && weightGrams == values.weight.grams
            && sourceSetID == values.sourceSetID
            && achievedAt == values.achievedAt
            && computationVersion == values.computationVersion
    }

    /// Overwrites this row's computed columns from `values`.
    func apply(_ values: PersonalRecordCacheValues) {
        repCount = values.repCount
        weightGrams = values.weight.grams
        sourceSetID = values.sourceSetID
        achievedAt = values.achievedAt
        computationVersion = values.computationVersion
    }
}
