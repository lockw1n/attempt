import Foundation
import RepositoryInterface
import SwiftData

/// `TrainingMaxRepository` over SwiftData (`TR-0.4.2`, `TR-16.3`, `FR-15.1`, `FR-16.7`).
///
/// **Two tables behind one actor**, because the pair is one contract: the configuration says how a
/// number is derived and the history says what it was, and a caller resolving a training max asks
/// both. Splitting them across actors would put the two halves of one answer behind two
/// serialisation domains.
@ModelActor
actor SwiftDataTrainingMaxRepository: TrainingMaxRepository {
    /// The configuration in force, by the latest ``TrainingMaxConfigEntity/effectiveFrom`` at or
    /// before `date`.
    ///
    /// **Two entries may share an effective date**, so the pick is `effectiveFrom` first and then
    /// rule 2's own order — the same total key, with the lookup's key in front of it. Nothing here
    /// leans on a unique constraint: `FR-1.5.1.4` keeps every change, and `G-2.5` forbids the
    /// constraint that would make one of them impossible.
    func configuration(forExerciseID exerciseID: UUID, on date: Date) throws -> TrainingMaxEntry? {
        let inForce = try modelContext.rows(
            TrainingMaxConfigEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID && $0.effectiveFrom <= date },
            includingDeleted: false
        )
        return inForce.max {
            ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
        }?.record
    }

    func configurationHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) throws -> [TrainingMaxEntry] {
        try modelContext.rows(
            TrainingMaxConfigEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        .sortedDeterministically(by: { ($0.effectiveFrom, $0.id.uuidString) }, descending: true)
        .map(\.record)
    }

    func saveConfiguration(_ entry: TrainingMaxEntry) throws {
        try modelContext.requireReferenced(
            ExerciseEntity.self, id: entry.exerciseID, from: entry.id)
        try modelContext.upsert(entry, as: TrainingMaxConfigEntity.self)
        try modelContext.saveStamped()
    }

    /// The training max in force, resolved the way the configuration above is and over the other
    /// table.
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) throws -> TrainingMaxHistoryEntry? {
        let inForce = try modelContext.rows(
            TrainingMaxHistoryEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID && $0.effectiveFrom <= date },
            includingDeleted: false
        )
        return inForce.max {
            ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
        }?.record
    }

    func history(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) throws -> [TrainingMaxHistoryEntry] {
        try modelContext.rows(
            TrainingMaxHistoryEntity.self,
            matching: #Predicate { $0.exerciseID == exerciseID },
            includingDeleted: includingDeleted
        )
        // The key `trainingMax(forExerciseID:on:)` maximises, reversed — so two changes dated the
        // same day list in the order they resolve and the one in force is the one on top. Ordered
        // on `(effectiveFrom, id)` alone, a same-day correction could list *under* the typo it
        // replaced while outranking it in force.
        .sorted {
            ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                > ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
        }
        .map(\.record)
    }

    /// Writes one history row and nothing else (`NFR-15.2`).
    func save(_ entry: TrainingMaxHistoryEntry) throws {
        try modelContext.requireReferenced(
            ExerciseEntity.self, id: entry.exerciseID, from: entry.id)
        try modelContext.upsert(entry, as: TrainingMaxHistoryEntity.self)
        try modelContext.saveStamped()
    }

    func deleteEntry(id: UUID) throws {
        let entries = try modelContext.rows(
            TrainingMaxHistoryEntity.self, id: id, includingDeleted: false)
        guard !entries.isEmpty else { throw RepositoryError.recordNotFound(id: id) }

        let now = Date.now
        for entry in entries { entry.markDeleted(at: now) }
        try modelContext.saveStamped(at: now)
    }
}
