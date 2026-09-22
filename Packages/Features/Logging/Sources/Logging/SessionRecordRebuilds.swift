import Foundation
import RepositoryInterface

/// The workout's own row, rebuilt with one field changed (`FR-1.2.9`, `FR-1.2.11`).
///
/// **The danger is what a rebuild leaves out.** `WorkoutSession` is a value with `let` properties,
/// so a command that moves one column rebuilds the whole record — and `save(_:)` is an **upsert**,
/// so a column the rebuild does not name is not left alone, it is overwritten with whatever the
/// initialiser defaults to. `weekNumber` and `dayIndex` default to `nil` (`FR-16.8.3`), which is how
/// finishing a workout came to be able to erase the week it belonged to. The other two sites are
/// ``SessionNoteWriter``, being a past session's rather than this store's, and
/// ``DerivedValues/SessionFinish/ended(_:at:)``, which two features end a workout through.
///
/// The three timestamps are carried across in both because the write path stamps `updatedAt`
/// itself.
extension ActiveSessionStore {
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

    /// `session` on another training day, and every other field untouched.
    ///
    /// Every column is named, on ``DerivedValues/SessionFinish/ended(_:at:)``'s rule: `save(_:)` is
    /// an upsert over a value whose initialiser defaults the program stamp to `nil`, so a rebuild
    /// that omitted it would erase which day of which week this workout is.
    ///
    /// **Here rather than beside ``changeDate(to:)``, and internal rather than private**, on
    /// ``noted(_:as:)``'s rule and for its reason: `FR-18.7.4` re-dates a session from History,
    /// where there is no store holding it (``PastSessionState``), and a second rebuild written
    /// there would be a second place for the program stamp to be dropped.
    ///
    /// - Parameters:
    ///   - session: The workout.
    ///   - day: The training day it moves to.
    /// - Returns: The record to store.
    static func dated(_ session: WorkoutSession, to day: Date) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: Calendar.current.startOfDay(for: day),
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: session.notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }
}
