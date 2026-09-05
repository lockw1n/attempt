import Foundation
import RepositoryInterface

/// What saving a workout as a routine did (`FR-15.2.6`).
///
/// **Three answers, one of them a success**, which is the difference from every other outcome on
/// this screen — see ``PastSessionState/saveAsRoutineOutcome``. The two failures stay apart on
/// `RoutineManagementFailure`'s argument: an empty name names something the lifter can fix, and a
/// refused write names only the store.
enum SaveAsRoutineOutcome: Equatable {
    /// A routine was written, under the name the lifter gave it.
    case saved(String)

    /// Nothing was written: the prompt's field held no name.
    case nameRequired

    /// Nothing was written: the store refused. The diagnostic stays with it (`G-3.4`).
    case writeFailed
}

/// `FR-15.2.6`'s command, over the session this screen already holds.
///
/// A file of its own for `ActiveSessionRoutineStart`'s reason: it writes into a repository the
/// screen otherwise only carries, and ``PastSessionState`` is long enough.
extension PastSessionState {
    /// Writes this workout's exercises and the loads it logged as a new routine (`FR-15.2.6`).
    ///
    /// **What it copies, and what it deliberately does not, is ``SessionAsRoutine``'s** — the sets
    /// that were performed rather than the plan the session was given.
    ///
    /// **Trimmed, and an empty name is refused**, the routine editor's own rule applied where a
    /// name is typed into a prompt instead of a form: a routine stored under whitespace is the row
    /// the library draws **Unnamed routine** for.
    ///
    /// **The write itself is ``SessionAsRoutineWriter``'s**, shared with `FR-16.8.4`'s
    /// *Start next week* — including the rollback that keeps ``SaveAsRoutineOutcome/writeFailed``
    /// meaning what it says.
    ///
    /// **Nothing on this screen is re-read afterwards.** The workout is untouched by this command;
    /// what it produced is in another tab, and the outcome is what says so.
    ///
    /// - Parameter name: What the lifter called it.
    func saveAsRoutine(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveAsRoutineOutcome = .nameRequired
            return
        }
        do {
            try await SessionAsRoutineWriter(repository: routines)
                .write(SessionAsRoutine(exercises), named: trimmed)
        } catch {
            saveAsRoutineOutcome = .writeFailed
            return
        }
        saveAsRoutineOutcome = .saved(trimmed)
    }
}
