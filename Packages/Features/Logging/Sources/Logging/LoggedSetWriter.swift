import Foundation
import RepositoryInterface

/// Every write that changes a set which is **already logged** — `FR-1.2.7`'s edit and its delete.
///
/// **Below the workout in progress rather than on it, and that is the requirement's own word
/// "including past sessions".** `ActiveSessionStore` is one workout — every command on it is gated
/// on holding that workout — but a set logged three sessions ago belongs to no workout in progress
/// and is edited from History all the same. What such a screen needs is the repository and a set's
/// id, which is all this holds; the session store delegates to it rather than owning the writes, so
/// the two surfaces cannot come to disagree about what an edit does.
///
/// **It is also the one place `FR-1.6.4`'s recalculation is triggered from.** A set's load, reps,
/// kind or existence changing is what moves a personal record or an e1RM, and both calls that can do
/// it are here — a recompute hooked onto these two is hooked onto every edit and every deletion in
/// the app.
///
/// **Neither call reports a set it cannot find**, and that is the marking commands' rule rather than
/// a new one: the row was deleted underneath the screen, and a diagnostic would report a failure
/// against a set the user can no longer see. Both answer `false` instead, so a caller that needs to
/// tell "written" from "nothing to write" still can.
public struct LoggedSetWriter: Sendable {
    /// The sets, and the entries they are read by.
    private let repository: any WorkoutRepository

    /// Builds the writer over the repository the sets live in.
    ///
    /// - Parameter repository: Sessions, their entries and their sets.
    public init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    /// Rewrites a logged set's five editable fields (`FR-1.2.7`).
    ///
    /// **The five the editor collects, and nothing else.** `order`, `isCompleted`, `completedAt`,
    /// the two target columns, `rir` and all three timestamps are carried across untouched — the
    /// outcome has its own control (`FR-1.2.5`), the position is the card's, and `completedAt`
    /// records that the set was tracked live, which editing it afterwards does not undo. That is
    /// also what makes the retroactive correction `FR-1.2.5` needs a single edit: a set already
    /// marked failed keeps its outcome while its ``RepositoryInterface/SetEntry/reps`` come down to
    /// what was actually achieved.
    ///
    /// **A set that resolves to exactly what is stored is not written**, which is `G-2.4` rather
    /// than tidiness: every save restamps `updatedAt`, the conflict key, so a no-op local write
    /// would outrank a real remote edit. Opening the editor and confirming it unchanged is the
    /// ordinary way to reach that.
    ///
    /// - Parameters:
    ///   - setID: The set to rewrite.
    ///   - entryID: The exercise it belongs to — what the repository reads sets by.
    ///   - values: What it becomes.
    /// - Returns: Whether anything was written.
    /// - Throws: Whatever the repository throws reading the entry's sets or saving the row.
    @discardableResult
    public func edit(
        id setID: UUID, inEntryID entryID: UUID, to values: SetEntryValues
    ) async throws -> Bool {
        let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
        guard let target = stored.first(where: { $0.id == setID }) else { return false }
        let edited = Self.edited(target, to: values)
        guard edited != target else { return false }
        try await repository.save(edited)
        return true
    }

    /// Soft-deletes a logged set (`FR-1.2.7`, `G-1.3`).
    ///
    /// **Soft, and nothing here makes it so** — the repository stamps `deletedAt` and the row stays
    /// until an explicit purge (`G-1.3`). What that costs the caller is one thing worth knowing: the
    /// set is still in the store afterwards and is still read by anything passing
    /// `includingDeleted: true`.
    ///
    /// **The set is looked up before it is deleted**, so a row already gone answers `false` rather
    /// than raising `RepositoryError.recordNotFound` at a screen whose only remaining move is to
    /// re-read. Two thumbs on the same delete is the ordinary way to reach that.
    ///
    /// - Parameters:
    ///   - setID: The set to delete.
    ///   - entryID: The exercise it belongs to.
    /// - Returns: Whether anything was deleted.
    /// - Throws: Whatever the repository throws reading the entry's sets or deleting the row.
    @discardableResult
    public func delete(id setID: UUID, inEntryID entryID: UUID) async throws -> Bool {
        let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
        guard stored.contains(where: { $0.id == setID }) else { return false }
        try await repository.deleteSet(id: setID)
        return true
    }

    /// `set` carrying `values`, and every other field untouched.
    ///
    /// Rebuilt rather than mutated because the record is a value with `let` properties, and the
    /// three timestamps are carried across because the write path is an upsert that stamps
    /// `updatedAt` itself.
    private static func edited(_ set: SetEntry, to values: SetEntryValues) -> SetEntry {
        SetEntry(
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            entryID: set.entryID,
            order: set.order,
            weight: values.weight,
            reps: values.reps,
            rpe: values.rpe,
            rir: set.rir,
            isWarmup: values.isWarmup,
            isCompleted: set.isCompleted,
            targetWeight: set.targetWeight,
            targetReps: set.targetReps,
            modifiers: set.modifiers,
            notes: values.notes,
            completedAt: set.completedAt
        )
    }
}
