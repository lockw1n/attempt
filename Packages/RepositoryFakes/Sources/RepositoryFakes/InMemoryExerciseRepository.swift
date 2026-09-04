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
}
