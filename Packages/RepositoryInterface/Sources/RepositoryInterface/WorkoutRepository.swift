import Foundation
import PowerliftingCore

/// Sessions, the exercises performed in them, and the sets logged against those (`TR-0.4.1`,
/// `FR-1.2`).
///
/// Three levels rather than one nested tree, because the schema declares no relationships
/// (`G-2.5`) and a repository that returned a tree would be inventing one. What it does own is the
/// **order**: see ``sets(forExerciseID:includingDeleted:)``.
public protocol WorkoutRepository: Sendable {
    /// Sessions whose ``WorkoutSession/date`` falls in `range`, newest first (`FR-1.2.1`).
    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession]

    /// One session, or `nil` if no row carries that id.
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession?

    /// Inserts or replaces the session, keyed on ``WorkoutSession/id``.
    func save(_ session: WorkoutSession) async throws

    /// Soft-deletes the session and, with it, its entries and their sets (`FR-1.2.12`).
    ///
    /// The cascade is deliberate and is rule 3 in this module's header: nothing in the store
    /// performs it, so a session deleted alone would leave its sets live, readable and eligible to
    /// hold a personal record belonging to a workout the user discarded.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live session carries that id.
    func deleteSession(id: UUID) async throws

    /// The exercises performed in one session, in ``ExerciseEntry/order`` (`FR-1.2.2`).
    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry]

    /// Inserts or replaces the entry, keyed on ``ExerciseEntry/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the session or the
    ///   exercise does not exist.
    func save(_ entry: ExerciseEntry) async throws

    /// Soft-deletes the entry and its sets. See ``deleteSession(id:)`` for why it cascades.
    ///
    /// Named for its record type rather than `deleteEntry`, which
    /// ``BodyweightRepository/deleteEntry(id:)`` already spells with an identical signature — one
    /// type conforming to both would satisfy the two with a single implementation, and the two
    /// mean different things (this one cascades).
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live entry carries that id.
    func deleteExerciseEntry(id: UUID) async throws

    /// The sets logged against one entry, in ``SetEntry/order`` (`FR-1.2.3`).
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry]

    /// Inserts or replaces the set, keyed on ``SetEntry/id`` (`FR-1.2.6`, `FR-1.2.7`).
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the entry does not
    ///   exist.
    func save(_ set: SetEntry) async throws

    /// Soft-deletes one set (`FR-1.2.7`). Nothing cascades from here.
    ///
    /// - Throws: ``RepositoryError/recordNotFound(id:)`` if no live set carries that id.
    func deleteSet(id: UUID) async throws

    /// Every set ever logged against one exercise, **oldest first**, ordered by
    /// `(session date, entry order, set order)` and stably.
    ///
    /// This is the collection `PersonalRecordCalculator` is handed, and the order is a correctness
    /// obligation rather than a convenience. `PowerliftingCore` has no `Date`, so `TR-0.2.8`'s
    /// "ties resolve to the earlier set" means *earlier in the collection supplied*, and a
    /// `PersonalRecord` reports an offset into it rather than an identity — which is how
    /// `TR-0.3.9`'s source set and `FR-1.6.2`'s link back to it are resolved. Get the order wrong
    /// and every answer is still plausible: only the tie-break moves, and only between two sets
    /// that weigh the same.
    ///
    /// **Warmups and incomplete sets are included.** The calculator excludes them itself, and
    /// pre-filtering here would shift every offset — a wrong answer, not an optimisation. The
    /// caller must not re-filter or re-sort before reading offsets out of the result.
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry]
}
