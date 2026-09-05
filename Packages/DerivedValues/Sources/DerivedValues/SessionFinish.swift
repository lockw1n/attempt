import Foundation
import RepositoryInterface

/// Ending a workout, and the sets nobody attempted that have to be answered for first
/// (`FR-16.4.1`, `FR-16.4.4`).
///
/// **Here rather than on the logging store, because two features end a workout.** The workout in
/// progress is finished from the training tab, and a session left open for days — an import, or an
/// abandoned workout — is finished from its history card; `TR-1.3` forbids either feature package
/// depending on the other, so "resolve the pending sets, then end the session, then tell the record
/// cache" lives below both. A second copy of it is a second answer to what Finish does with a set
/// that was never attempted.
public struct SessionFinish: Sendable {
    /// What Finish does with the sets nobody attempted (`FR-16.4.4`).
    ///
    /// **There is no third case, and no default.** The whole of the requirement is that the choice
    /// is made rather than assumed: a pending set silently kept would become a missed lift the
    /// lifter never recorded, and one silently dropped would lose a miss they meant to record.
    public enum Resolution: Equatable, Sendable {
        /// The rows go (`G-1.3`, so they are soft-deleted).
        case remove

        /// The rows stay. Nothing is written — a set that is not completed inside a session that
        /// has ended *is* a failed set, so ending the session is the whole of the conversion.
        case keepAsFailed
    }

    /// Where the sessions, their entries and their sets come from.
    private let workouts: any WorkoutRepository

    /// What is told that a finished session's sets now count (`FR-1.6.4`).
    private let records: PersonalRecordRecomputer

    /// Builds the operation over the two things it needs.
    ///
    /// - Parameters:
    ///   - workouts: The sessions and what hangs off them.
    ///   - records: The recomputer to announce to once the session has ended.
    public init(workouts: any WorkoutRepository, records: PersonalRecordRecomputer) {
        self.workouts = workouts
        self.records = records
    }

    /// The sets of an open session nobody has attempted yet, in the order they were logged.
    ///
    /// **A finished session has none, by definition** (`FR-16.4.1`): pending is an uncompleted set
    /// *and* an open session, and once the session has ended the same row is a failed set. So this
    /// answers with nothing rather than refusing.
    ///
    /// - Parameter session: The session to look in.
    /// - Returns: Its pending sets.
    /// - Throws: Whatever the repository throws reading the entries or their sets.
    public func pendingSets(in session: WorkoutSession) async throws -> [SetEntry] {
        guard !session.isFinished else { return [] }
        var pending: [SetEntry] = []
        for entry in try await workouts.entries(forSessionID: session.id, includingDeleted: false) {
            pending += try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                .filter { !$0.isCompleted }
        }
        return pending
    }

    /// Ends the session, having resolved its pending sets.
    ///
    /// **The resolution is written before the end, and that order is not a preference.** Once
    /// `endedAt` is stored the rows are failed sets, so a removal running second would be deleting
    /// what the lifter has already been shown as failed.
    ///
    /// **The announcement is last and is not conditional.** A finished session's sets count towards
    /// records and e1RM where an open one's do not, so every exercise it touched has a stale cache
    /// the moment the column is written — whichever answer was given.
    ///
    /// - Parameters:
    ///   - session: The session to end.
    ///   - now: The instant it ended.
    ///   - resolution: What to do with the sets nobody attempted.
    /// - Returns: The session as stored, ended.
    /// - Throws: Whatever the repository throws deleting a set or saving the session.
    @discardableResult
    public func finish(
        _ session: WorkoutSession, at now: Date, resolving resolution: Resolution
    ) async throws -> WorkoutSession {
        if resolution == .remove {
            for set in try await pendingSets(in: session) {
                try await workouts.deleteSet(id: set.id)
            }
        }
        let ended = Self.ended(session, at: now)
        try await workouts.save(ended)
        await records.sessionDidChange(id: session.id)
        return ended
    }

    /// `session` with its end stamped, and every other field untouched.
    ///
    /// **Every column is named, and that is not tidiness.** `save(_:)` is an upsert over a value
    /// whose initialiser defaults `weekNumber` and `dayIndex` to `nil` (`FR-16.8.3`), so a rebuild
    /// that omitted one would not leave it alone — it would erase which day of a program the
    /// workout was. Check this when the record gains a column.
    ///
    /// - Parameters:
    ///   - session: The session being ended.
    ///   - moment: When it ended.
    /// - Returns: The rebuilt record.
    public static func ended(_ session: WorkoutSession, at moment: Date) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: session.date,
            startedAt: session.startedAt,
            endedAt: moment,
            notes: session.notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }
}
