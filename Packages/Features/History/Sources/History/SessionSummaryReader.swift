import Foundation
import PowerliftingCore
import RepositoryInterface

/// Turns one stored session into the row the list, the calendar and the search results all draw
/// (`FR-1.5.1`, `FR-1.5.3`, `FR-1.5.4`).
///
/// **Extracted so no two of them can disagree about what a row says.** All three build the same
/// `SessionSummary` from the same three reads; a second copy of the walk would be a second answer to
/// what a session's tonnage is, which is the one thing `SessionSummary`'s own doc comment says must
/// not happen.
///
/// It holds the name lookup rather than the catalogue repository: names are read once per screen
/// load, and a reader that read them per row would be the eager per-row load `NFR-1.5` cannot
/// survive.
struct SessionSummaryReader {
    /// Where the entries and their sets come from.
    private let workouts: any WorkoutRepository

    /// What each exercise is called, keyed by its identifier.
    private let names: [UUID: String]

    /// Builds a reader over one screen's already-read catalogue.
    ///
    /// - Parameters:
    ///   - workouts: The sessions' entries and sets.
    ///   - names: The name lookup, as ``SessionListState/names(in:)`` builds it.
    init(workouts: any WorkoutRepository, names: [UUID: String]) {
        self.workouts = workouts
        self.names = names
    }

    /// One session's row: its exercises, its working sets and what they weighed.
    ///
    /// - Parameter session: The session to summarise.
    /// - Returns: The row.
    func summary(for session: WorkoutSession) async throws -> SessionSummary {
        try await indexed(for: session).summary
    }

    /// One session's row, plus the per-set notes only `FR-1.5.4` reads.
    ///
    /// **The single walk, and ``summary(for:)`` is a projection of it.** Both callers need the same
    /// three reads in the same order; two walks that filtered differently would be two answers to
    /// what a session contains, which is the thing this type exists to prevent. Search pays for the
    /// notes it looks in, and the list pays for an array of the ones a session has — which is almost
    /// always none, `SetEntry/notes` being the exception rather than the column's normal value.
    ///
    /// - Parameter session: The session to read.
    /// - Returns: Its row and its searchable notes.
    func indexed(for session: WorkoutSession) async throws -> IndexedSession {
        let entries = try await workouts.entries(
            forSessionID: session.id, includingDeleted: false)

        var exerciseNames: [String] = []
        var seen: Set<UUID> = []
        var setCount = 0
        var tonnage = Weight.zero
        var setNotes: [String] = []

        for entry in entries {
            if seen.insert(entry.exerciseID).inserted {
                exerciseNames.append(names[entry.exerciseID] ?? Self.unnamedExercise)
            }
            let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
            setCount += sets.count(where: Tonnage.counts)
            tonnage += Tonnage.of(sets)
            // Every set's note, warmups and incomplete ones included: `Tonnage.counts` partitions
            // what was *lifted*, and a note written on a warmup is still a note the user typed and
            // expects to find again (`FR-1.5.4`). Soft-deleted sets are already out — the read
            // above excludes them (`G-1.3`).
            setNotes.append(contentsOf: sets.map(\.notes).filter { !$0.isEmpty })
        }

        let summary = SessionSummary(
            id: session.id,
            date: session.date,
            exerciseNames: exerciseNames,
            setCount: setCount,
            tonnage: tonnage,
            notes: session.notes
        )
        return IndexedSession(summary: summary, setNotes: setNotes)
    }

    /// What a row calls an exercise whose catalogue row is gone.
    ///
    /// Not localized, and not shown: the catalogue is read including deleted rows, so this is
    /// reachable only from a store missing a row a session references — a dangling reference the
    /// repository refuses to create. An empty name renders as nothing rather than as a translated
    /// apology for a case that cannot happen.
    private static let unnamedExercise = ""
}
