import Foundation
import PowerliftingCore

/// The exercise catalogue (`TR-0.4.1`, `FR-1.1`).
///
/// **Training maxes are ``TrainingMaxRepository``'s**, not this protocol's — see its note for why
/// two tables with their own history do not belong on the catalogue.
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
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if
    ///   ``Exercise/parentExerciseID`` names an exercise that does not exist. A variation is
    ///   therefore saved after its parent — the same ordering an entry owes its session.
    func save(_ exercise: Exercise) async throws
}
