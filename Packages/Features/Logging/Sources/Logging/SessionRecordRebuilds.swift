import Foundation
import RepositoryInterface

/// The workout's own row, rebuilt with one field changed (`FR-1.2.9`, `FR-1.2.11`).
///
/// **One file for both, because the danger is what they leave out.** `WorkoutSession` is a value
/// with `let` properties, so a command that moves one column rebuilds the whole record — and
/// `save(_:)` is an **upsert**, so a column the rebuild does not name is not left alone, it is
/// overwritten with whatever the initialiser defaults to. `weekNumber` and `dayIndex` default to
/// `nil` (`FR-16.8.3`), which is how finishing a workout came to be able to erase the week it
/// belonged to. Two sites in one file is one place to check when the record gains a column;
/// ``SessionNoteWriter`` is the third and cannot be here, being a past session's rather than this
/// store's.
///
/// The three timestamps are carried across in both because the write path stamps `updatedAt`
/// itself.
extension ActiveSessionStore {
    /// `session` with `endedAt` set, and every other field untouched.
    ///
    /// - Parameters:
    ///   - session: The workout being finished.
    ///   - moment: When it ended.
    /// - Returns: The record to store.
    static func ended(_ session: WorkoutSession, at moment: Date) -> WorkoutSession {
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

    /// `session` with its note replaced, and every other field untouched.
    ///
    /// - Parameters:
    ///   - session: The workout.
    ///   - text: Its new note.
    /// - Returns: The record to store.
    static func noted(_ session: WorkoutSession, as text: String) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: session.date,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: text,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }
}
