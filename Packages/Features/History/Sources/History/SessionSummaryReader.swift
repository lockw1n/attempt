import Foundation
import PowerliftingCore
import RepositoryInterface

/// Turns one stored session into the row two screens draw (`FR-1.5.1`, `FR-1.5.3`).
///
/// **Extracted so the list and the calendar cannot disagree about what a row says.** Both build the
/// same `SessionSummary` from the same three reads; a second copy of the walk would be a second
/// answer to what a session's tonnage is, which is the one thing `SessionSummary`'s own doc comment
/// says must not happen.
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
        let entries = try await workouts.entries(
            forSessionID: session.id, includingDeleted: false)

        var exerciseNames: [String] = []
        var seen: Set<UUID> = []
        var setCount = 0
        var tonnage = Weight.zero

        for entry in entries {
            if seen.insert(entry.exerciseID).inserted {
                exerciseNames.append(names[entry.exerciseID] ?? Self.unnamedExercise)
            }
            let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
            setCount += sets.count(where: Tonnage.counts)
            tonnage += Tonnage.of(sets)
        }

        return SessionSummary(
            id: session.id,
            date: session.date,
            exerciseNames: exerciseNames,
            setCount: setCount,
            tonnage: tonnage,
            notes: session.notes
        )
    }

    /// What a row calls an exercise whose catalogue row is gone.
    ///
    /// Not localized, and not shown: the catalogue is read including deleted rows, so this is
    /// reachable only from a store missing a row a session references — a dangling reference the
    /// repository refuses to create. An empty name renders as nothing rather than as a translated
    /// apology for a case that cannot happen.
    private static let unnamedExercise = ""
}
