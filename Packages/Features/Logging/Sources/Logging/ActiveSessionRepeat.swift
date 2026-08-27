import Foundation
import RepositoryInterface

/// `FR-1.9.2`'s repeat: a fresh workout holding a past one's exercises.
///
/// A file of its own rather than more of ``ActiveSessionStore``, which had reached SwiftLint's length
/// ceiling — ``ActiveSessionCommands``' reason, and the same store.
extension ActiveSessionStore {
    /// Starts a workout on `day` carrying the exercises `sessionID` held, in the same order
    /// (`FR-1.9.2`).
    ///
    /// **The exercises and nothing else.** Phase 1 has no prescription layer (`OUT-1.1`), so there
    /// are no targets to pre-fill and copying the sets would be claiming work that was not done. The
    /// per-exercise notes are left behind too: they are commentary on the workout that happened, and
    /// carrying them forward would put last week's remarks on this week's empty cards.
    ///
    /// **It refuses while a workout is in progress**, which is ``start(on:)``'s invariant rather than
    /// a new one — there is one active session by construction. A caller that has not looked yet
    /// should ``resume()`` first, or it will start a second workout on top of one already open.
    ///
    /// **The copy is best-effort and the workout is kept either way.** A repeat whose entries could
    /// not be written leaves the user in an empty workout they can add to, which is what
    /// ``start(on:)`` would have given them; discarding it to report the failure would throw away a
    /// session row `NFR-1.8` has already persisted.
    ///
    /// - Parameters:
    ///   - day: The training day the new workout belongs to.
    ///   - sessionID: The workout to copy the exercises from.
    /// - Returns: Whether a workout is now in progress.
    @discardableResult
    public func start(on day: Date, repeating sessionID: UUID) async -> Bool {
        guard session == nil else { return false }
        await start(on: day)
        guard let current = session else { return false }
        do {
            let source =
                try await repository
                .entries(forSessionID: sessionID, includingDeleted: false)
                .sorted { $0.order < $1.order }
            let now = Date.now
            for (position, entry) in source.enumerated() {
                try await repository.save(
                    ExerciseEntry(
                        id: UUID(),
                        createdAt: now,
                        updatedAt: now,
                        deletedAt: nil,
                        sessionID: current.id,
                        exerciseID: entry.exerciseID,
                        order: position,
                        notes: ""
                    )
                )
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
        return true
    }
}
