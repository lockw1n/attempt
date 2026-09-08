import Foundation
import RepositoryInterface

/// Which workout a screen is asking ``ActiveSessionStore`` to hold (`FR-17.9.5`, `OUT-17.3`).
///
/// **The store's session read was "the one open session", and a day beside a free workout is two.**
/// A lifter can have a program day part-answered and a workout no program planned open at the same
/// time; neither is more current than the other, and a read that took the first unfinished row
/// would hand a day's session to the screen that draws the free workout. So the read becomes a
/// question with an argument: a day is located by the stamp it was written with, a free workout by
/// being unfinished and belonging to no run.
///
/// **A finished session still answers.** A day that is done is still the day's session — its rows
/// are what the checklist draws and what **Log** edits — where a free workout that has ended is
/// simply over. The two clauses differ for that reason rather than by oversight.
enum SessionLocator: Equatable, Sendable {
    /// The workout in progress that no program planned (`FR-17.8.3`).
    case freeWorkout

    /// The session stamped with one day of one week of one run (`FR-16.8.3`).
    case day(runID: UUID, week: Int, dayIndex: Int)

    /// The session this names, or `nil` where there is none.
    ///
    /// **The free workout's read is unbounded, and that is ``ActiveSessionStore/resume()``'s own
    /// argument carried across**: `WorkoutRepository` has no "incomplete sessions" query, and any
    /// date window narrow enough to be cheap is one a backdated session can fall outside of and
    /// never be seen again. The day's read is not — `TR-17.5` answers it with one query.
    ///
    /// **A day with two sessions takes the newest**, which is ``WeekState``'s rule for the same
    /// rows: the query orders newest first, one day is one session, and a second is a row this app
    /// did not write.
    ///
    /// - Parameter workouts: Where the sessions are read from.
    /// - Returns: The session, or `nil`.
    /// - Throws: Whatever the repository throws.
    func session(in workouts: any WorkoutRepository) async throws -> WorkoutSession? {
        switch self {
        case .freeWorkout:
            return
                try await workouts
                .sessions(in: Date.distantPast...Date.distantFuture, includingDeleted: false)
                .first { $0.endedAt == nil && $0.programRunID == nil }
        case .day(let runID, let week, let dayIndex):
            return
                try await workouts
                .sessions(forProgramRunID: runID, week: week, includingDeleted: false)
                .first { $0.dayIndex == dayIndex }
        }
    }
}

// `ActiveSessionStore`'s side of the locator, in this file rather than beside the store's other
// lifecycle methods: that file is at `file_length`'s ceiling, and these two belong to the question
// above rather than to the workout's lifetime.

extension ActiveSessionStore {
    /// Adopts the workout left in progress, if there is one (`FR-1.2.11`).
    ///
    /// **What "in progress" means is `endedAt == nil`, and nothing else.** Not a flag, and not a
    /// date window: a session is finished when it has been finished, so a workout backdated to last
    /// month and never finished is still the one this app is in the middle of. That is also why the
    /// read is unbounded — `WorkoutRepository` has no "incomplete sessions" query, so this is every
    /// live session filtered here, and any window narrow enough to be cheap is a window a real
    /// backdated session can fall outside of and never be seen again. The rows are dated training
    /// days, one per workout, so reading them all at launch is a small read rather than a scan of
    /// the sets.
    ///
    /// **Newest first is the repository's order**, so the first match is the most recent day —
    /// which is the workout a user who force-quit mid-set is coming back to.
    ///
    /// A session already held is kept and nothing is read: this runs from a screen's `.task`, which
    /// SwiftUI re-runs on every tab switch and restored push, and a re-read would race the record
    /// ``update(_:)`` publishes. ``hasCheckedForSession`` is still set, because the question that
    /// property answers — has anything looked? — has been answered either way.
    public func resume() async {
        // A free workout already held is kept and nothing is read, which is this method's own
        // guard narrowed rather than dropped: the re-read it prevents would race the record
        // ``update(_:)`` publishes. What it no longer keeps is a *day's* session — another screen
        // pointed this store at that one, and the root asking for the free workout is asking for a
        // different row.
        if session?.programRunID == nil, session != nil {
            // The held list is kept along with the workout: this returned without reading, so
            // nothing about that workout has changed.
            noteChecked()
            return
        }
        await open(.freeWorkout)
    }

    /// Holds the session `locator` names, or none (`FR-17.9.5`, `OUT-17.3`).
    ///
    /// **The store holds whichever workout the screen that asked is about, and there are now two it
    /// could be.** A day's session and a free workout can both be open at once, so "the one open
    /// session" is no longer a question with an answer — see ``SessionLocator``. Nothing here reads
    /// more than the one it was asked for.
    ///
    /// A read that finds nothing is **not** a failure, on ``adopt(sessionID:)``'s rule: a day
    /// nobody has logged into has no session, which is the ordinary state of most of a week.
    ///
    /// - Parameter locator: Which workout to hold.
    func open(_ locator: SessionLocator) async {
        do {
            adopt(located: try await locator.session(in: repository), failure: nil)
        } catch {
            adopt(located: nil, failure: String(describing: error))
        }
    }
}
