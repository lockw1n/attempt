import Foundation
import RepositoryInterface

/// `ExerciseRepository` over a dictionary (`TR-0.4.2`).
///
/// A facade: the rules are on ``InMemoryRepositoryStore`` below, because every check a save makes
/// reaches a table another repository owns.
struct InMemoryExerciseRepository: ExerciseRepository, Sendable {
    let store: InMemoryRepositoryStore

    /// Every exercise, by name then id. Archived ones are listed — filtering them is the caller's.
    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        await store.allExercises(includingDeleted: includingDeleted)
    }

    /// The exercise carrying `id`, or `nil`.
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        await store.exercise(id: id, includingDeleted: includingDeleted)
    }

    /// Inserts or replaces the exercise, refusing a `parentExerciseID` that names no row and one
    /// that names this exercise.
    func save(_ exercise: Exercise) async throws {
        try await store.saveExercise(exercise)
    }

    /// The configuration in force on `date`, by the latest `effectiveFrom` at or before it.
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        await store.trainingMax(forExerciseID: exerciseID, on: date)
    }

    /// Every configuration written for the exercise, newest effective first.
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        await store.trainingMaxHistory(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    /// Appends a configuration, refusing one whose exercise does not exist.
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {
        try await store.saveTrainingMax(entry)
    }
}

extension InMemoryRepositoryStore {
    /// Every exercise a read may return, ordered by name then id.
    func allExercises(includingDeleted: Bool) -> [Exercise] {
        exercises.values
            .live(includingDeleted: includingDeleted)
            .sortedDeterministically { ($0.name, $0.id.uuidString) }
    }

    /// The exercise carrying `id`, subject to the flag.
    func exercise(id: UUID, includingDeleted: Bool) -> Exercise? {
        exercises[id].flatMap { includingDeleted || !$0.isSoftDeleted ? $0 : nil }
    }

    /// Inserts or replaces `exercise`, checking the one join key it carries.
    ///
    /// **Self-reference is checked separately from existence, and it has to be.** Existence alone
    /// accepts an exercise naming itself the moment the row exists, so the identical record would be
    /// refused on the save that created it and accepted on the next one, leaving `FR-1.1.4`'s
    /// variation tree with a one-row cycle.
    ///
    /// - Throws: ``RepositoryInterface/RepositoryError/danglingReference(recordID:referencing:)``
    ///   when `parentExerciseID` names this exercise or no row at all.
    func saveExercise(_ exercise: Exercise) throws {
        if let parentID = exercise.parentExerciseID {
            guard parentID != exercise.id else {
                throw RepositoryError.danglingReference(
                    recordID: exercise.id, referencing: parentID)
            }
            try requireReferenced(exercises, id: parentID, from: exercise.id)
        }
        upserted(exercise, into: &exercises, at: .now)
    }

    /// The live configuration with the latest `effectiveFrom` at or before `date`.
    ///
    /// Two entries may share an effective date — `FR-1.5.1.4` keeps every change and `G-2.5` forbids
    /// the constraint that would make a tie impossible — so the pick continues into `updatedAt` and
    /// then the id, which is the same total key the reads on the other side use.
    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) -> TrainingMaxEntry? {
        trainingMaxes.values
            .filter { $0.exerciseID == exerciseID && $0.effectiveFrom <= date }
            .live(includingDeleted: false)
            .max {
                ($0.effectiveFrom, $0.updatedAt, $0.id.uuidString)
                    < ($1.effectiveFrom, $1.updatedAt, $1.id.uuidString)
            }
    }

    /// Every configuration written for the exercise, newest effective first.
    func trainingMaxHistory(
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
    func saveTrainingMax(_ entry: TrainingMaxEntry) throws {
        try requireReferenced(exercises, id: entry.exerciseID, from: entry.id)
        upserted(entry, into: &trainingMaxes, at: .now)
    }
}
