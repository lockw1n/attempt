import Foundation
import PowerliftingCore

/// The exercise catalogue and each exercise's training-max history (`TR-0.4.1`, `FR-1.1`,
/// `FR-1.5.1`).
///
/// **There is no delete.** `FR-1.1.5` forbids hard-deleting an exercise with logged sets and gives
/// archiving as the mechanism instead, so an exercise leaves the pickers through
/// ``Exercise/isArchived`` and stays in history. The soft delete every other protocol here offers
/// would orphan every set logged against the row.
public protocol ExerciseRepository: Sendable {
    /// Every exercise, archived ones included (`FR-1.1.1`).
    ///
    /// Filtering archived exercises out is the caller's: `FR-1.1.2` makes it one of several filters
    /// over the same list, and a repository that pre-applied one of them would make the others
    /// inconsistent.
    func exercises(includingDeleted: Bool) async throws -> [Exercise]

    /// One exercise, or `nil` if no row carries that id.
    ///
    /// Two rows may carry it; see the tiebreak rule in this module's header.
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise?

    /// Inserts or replaces the exercise, keyed on ``Exercise/id`` (`FR-1.1.3`, `FR-1.1.4`).
    ///
    /// **Upsert rather than insert**, which is what keeps a seed re-import (`TR-0.5.1`) or a
    /// restore from forking history into a second row sharing an id. ``Exercise/createdAt`` is
    /// honoured only when the row is new; ``Exercise/updatedAt`` and ``Exercise/deletedAt`` are
    /// ignored.
    func save(_ exercise: Exercise) async throws

    /// The training-max configuration in force for `exerciseID` on `date` — the latest entry
    /// effective on or before it, or `nil` if the user has configured none.
    ///
    /// A lookup rather than a read of one row: `FR-1.5.1.4` keeps every change, so the history has
    /// many entries per exercise and the newest applicable one wins.
    ///
    /// **No `includingDeleted:`, and it is not an omission.** This resolves to the configuration in
    /// force; a soft-deleted entry is one the user replaced, and letting it win a date comparison
    /// would recompute their training max from a setting they removed.
    /// ``trainingMaxHistory(forExerciseID:includingDeleted:)`` is where deleted entries are
    /// reachable.
    func trainingMax(forExerciseID exerciseID: UUID, on date: Date) async throws -> TrainingMaxEntry?

    /// Every training-max entry for one exercise, newest ``TrainingMaxEntry/effectiveFrom`` first —
    /// the history `FR-1.5.1.4` displays.
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry]

    /// Appends a training-max configuration to the exercise's history (`FR-1.5.1.4`).
    ///
    /// **Appends.** Saving a configuration that supersedes another does not overwrite it: the
    /// history is what `FR-1.5.1.4` requires and what makes `FR-2.3.2`'s past sessions explicable.
    /// Re-saving an entry that already exists updates that entry, by ``TrainingMaxEntry/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the exercise does
    ///   not exist.
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws
}
