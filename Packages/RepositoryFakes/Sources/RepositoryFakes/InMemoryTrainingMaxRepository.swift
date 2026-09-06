import Foundation
import RepositoryInterface

/// `TrainingMaxRepository` over two dictionaries (`TR-0.4.2`).
///
/// A facade: the rules are on ``InMemoryRepositoryStore`` below, because both saves check a table
/// the exercise repository owns.
struct InMemoryTrainingMaxRepository: TrainingMaxRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// The configuration in force on `date`, by the latest `effectiveFrom` at or before it.
    func configuration(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        await store.trainingMaxConfiguration(forExerciseID: exerciseID, on: date)
    }

    /// Every configuration written for the exercise, newest effective first.
    func configurationHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        await store.trainingMaxConfigurationHistory(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    /// Appends a configuration, refusing one whose exercise does not exist.
    func saveConfiguration(_ entry: TrainingMaxEntry) async throws {
        try await store.saveTrainingMaxConfiguration(entry)
    }

    /// The training max in force on `date`, by the latest `effectiveFrom` at or before it.
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxHistoryEntry? {
        await store.trainingMax(forExerciseID: exerciseID, on: date)
    }

    /// Every change written for the exercise, newest effective first.
    func history(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxHistoryEntry] {
        await store.trainingMaxHistory(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    /// Records a change, refusing one whose exercise does not exist.
    func save(_ entry: TrainingMaxHistoryEntry) async throws {
        try await store.saveTrainingMaxHistory(entry)
    }

    /// Soft-deletes one change.
    func deleteEntry(id: UUID) async throws {
        try await store.deleteTrainingMaxHistory(id: id)
    }
}

extension InMemoryRepositoryStore {
    /// The live configuration with the latest `effectiveFrom` at or before `date`.
    ///
    /// Two entries may share an effective date — `FR-1.5.1.4` keeps every change and `G-2.5` forbids
    /// the constraint that would make a tie impossible — so the pick continues into `updatedAt` and
    /// then the id, which is the same total key the reads on the other side use.
    func trainingMaxConfiguration(forExerciseID exerciseID: UUID, on date: Date) -> TrainingMaxEntry? {
        trainingMaxes.values
            .filter { $0.exerciseID == exerciseID && $0.effectiveFrom <= date }
            .live(includingDeleted: false)
            .max {
                ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                    < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
            }
    }

    /// Every configuration written for the exercise, newest effective first.
    func trainingMaxConfigurationHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) -> [TrainingMaxEntry] {
        trainingMaxes.values
            .filter { $0.exerciseID == exerciseID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically(by: { ($0.effectiveFrom, $0.id.uuidString) }, descending: true)
    }

    /// Appends or replaces a training-max configuration.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when `exerciseID` names no row.
    func saveTrainingMaxConfiguration(_ entry: TrainingMaxEntry) throws {
        try requireReferenced(exercises, id: entry.exerciseID, from: entry.id)
        upserted(entry, into: &trainingMaxes, at: .now)
    }

    /// The live training max with the latest `effectiveFrom` at or before `date`, resolved the way
    /// the configuration above is.
    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) -> TrainingMaxHistoryEntry? {
        trainingMaxEntries.values
            .filter { $0.exerciseID == exerciseID && $0.effectiveFrom <= date }
            .live(includingDeleted: false)
            .max {
                ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                    < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
            }
    }

    /// Every change written for the exercise, newest effective first.
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) -> [TrainingMaxHistoryEntry] {
        trainingMaxEntries.values
            .filter { $0.exerciseID == exerciseID }
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically(by: { ($0.effectiveFrom, $0.id.uuidString) }, descending: true)
    }

    /// Records a change, and writes nothing else (`NFR-15.2`).
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when `exerciseID` names no row.
    func saveTrainingMaxHistory(_ entry: TrainingMaxHistoryEntry) throws {
        try requireReferenced(exercises, id: entry.exerciseID, from: entry.id)
        upserted(entry, into: &trainingMaxEntries, at: .now)
    }

    /// Soft-deletes one change.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/recordNotFound(id:)`` when no live entry
    ///   carries `id`.
    func deleteTrainingMaxHistory(id: UUID) throws {
        try softDelete(id: id, in: &trainingMaxEntries, at: .now)
    }
}
