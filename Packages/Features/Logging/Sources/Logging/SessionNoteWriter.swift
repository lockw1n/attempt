import Foundation
import RepositoryInterface

/// The one write a past session carries on its own record (`FR-1.2.9`).
///
/// **Below the workout in progress rather than on it**, which is ``LoggedSetWriter``'s argument
/// applied to the session's own row: `ActiveSessionStore` is one workout and every command on it is
/// gated on holding that workout, so the note on a session finished three weeks ago has no writer
/// there. What such a screen needs is the repository and a session's id, which is all this holds.
///
/// **Only the note.** Every other column is carried across untouched — the day, both lifecycle
/// timestamps, the bodyweight, the two program keys and the week and day a program run stamped
/// (`FR-16.8.3`) — because a screen for correcting the record after the fact offers none of them,
/// and rebuilding a record from a partial view of it is how a finished session gets its `endedAt`
/// put back to `nil`. **The upsert is what makes an omission here a silent wipe rather than a
/// no-op**, so a nullable column added to this record owes every rebuild site an edit, not only
/// its mapping.
///
/// **Text the record already carries is not written.** Every save restamps `updatedAt`, which is
/// `G-2.4`'s conflict key, so a no-op local write would outrank a real remote edit — the ordinary
/// way to reach that is tapping **Save note** twice.
///
/// **A session it cannot find is not reported**, on ``LoggedSetWriter``'s rule: the row was deleted
/// underneath the screen, and a diagnostic would report a failure against a session the user can no
/// longer see. It answers `false` instead, so a caller that needs to tell "written" from "nothing to
/// write" still can.
public struct SessionNoteWriter: Sendable {
    /// The sessions this writes to.
    private let repository: any WorkoutRepository

    /// Builds the writer over the repository the sessions live in.
    ///
    /// - Parameter repository: Sessions, their entries and their sets.
    public init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    /// Stores one session's note (`FR-1.2.9`, `NFR-1.8`).
    ///
    /// - Parameters:
    ///   - sessionID: The session to note.
    ///   - notes: What the field held when **Save note** was tapped. Taken then rather than read at
    ///     write time, so what is stored is what was on screen when it was asked for.
    /// - Returns: Whether anything was written.
    /// - Throws: Whatever the repository throws reading the session or saving the row.
    @discardableResult
    public func save(id sessionID: UUID, notes: String) async throws -> Bool {
        guard let stored = try await repository.session(id: sessionID, includingDeleted: false),
            stored.notes != notes
        else {
            return false
        }
        try await repository.save(Self.noted(stored, as: notes))
        return true
    }

    /// `session` with its note replaced and every other field untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties; the three
    /// timestamps are carried across because the write path is an upsert that stamps `updatedAt`
    /// itself.
    private static func noted(_ session: WorkoutSession, as notes: String) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: session.date,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }
}
