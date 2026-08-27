import Foundation
import RepositoryInterface

/// `FR-1.6.2`'s other half: turning a record's source set back into the session it was performed in.
///
/// A file of its own rather than more of ``PersonalRecordRecomputer``, which had reached SwiftLint's
/// length ceiling. It is the same actor and the same isolation.
extension PersonalRecordRecomputer {
    /// The session each of `setIDs` was performed in — `FR-1.6.2`'s "link to the source set".
    ///
    /// **The cache cannot answer this and deliberately does not try.** `PersonalRecordCacheEntity`
    /// stores the set, not the session, because the session is a *join* and a cached copy of one is a
    /// second source of truth for where a set was performed (`G-1.4`); a set moved to another entry
    /// would leave the stored answer pointing at a workout the set is no longer in.
    ///
    /// **A walk of the exercise's sets, because a set is not readable by id.** `WorkoutRepository`
    /// reads sets by entry or by exercise and never by their own identifier, so the exercise's list is
    /// what turns a record's `sourceSetID` into the entry naming its session. Only entries actually
    /// holding a record are resolved — at most eleven, whatever the history is, which is
    /// ``sessionDates(forEntryIDs:)``'s bound for its reason.
    ///
    /// **Best-effort, and a set that will not resolve is simply absent** rather than a failure or a
    /// sentinel: what is lost is a link on one row, and a screen reporting a read failure over a
    /// record it is displaying names the wrong thing as broken.
    ///
    /// - Parameters:
    ///   - setIDs: The sets to locate — a record's ``DatedRecord/sourceSetID``.
    ///   - exerciseID: The exercise they were logged against.
    /// - Returns: The session behind each set that resolves, keyed on the set.
    public func sessionIDs(
        forSetIDs setIDs: Set<UUID>, inExerciseID exerciseID: UUID
    ) async -> [UUID: UUID] {
        guard !setIDs.isEmpty,
            let stored = try? await workouts.sets(
                forExerciseID: exerciseID, includingDeleted: false)
        else { return [:] }
        let holding = stored.filter { setIDs.contains($0.id) }
        let sessions = await sessionIDs(forEntryIDs: Set(holding.map(\.entryID)))
        return holding.reduce(into: [:]) { found, set in
            found[set.id] = sessions[set.entryID]
        }
    }

    /// The session each of `entryIDs` belongs to, for the ones that resolve.
    ///
    /// Deleted entries are read, and a row that will not resolve is absent, both for
    /// ``sessionDates(forEntryIDs:)``'s reasons. The *session row* is not read at all: an entry names
    /// its session in a column, so nothing here has to fetch it to know which one it is.
    private func sessionIDs(forEntryIDs entryIDs: Set<UUID>) async -> [UUID: UUID] {
        var sessions: [UUID: UUID] = [:]
        for entryID in entryIDs {
            guard let entry = try? await workouts.entry(id: entryID, includingDeleted: true) else {
                continue
            }
            sessions[entryID] = entry.sessionID
        }
        return sessions
    }
}
