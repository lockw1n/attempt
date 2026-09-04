import Foundation
import RepositoryInterface

// Which state the workout in progress is in, split from `ActiveSessionView` for
// `ActiveSessionCommands`' reason: that screen is what it draws, and this is the value it switches
// on. It is also the half of that screen a test can reach without a rendering.

/// Which of the pushed screen's four states is current (`FR-1.13.1`).
///
/// A value rather than a chain of `if`s, for ``TrainingHomeState``'s reason.
enum ActiveSessionState: Equatable {
    /// Nothing has looked for a workout yet.
    case loading

    /// The workout, and whether the last command against it failed.
    case inProgress(WorkoutSession, writeFailed: Bool)

    /// The read failed, so whether the workout is still in progress is not known.
    case readFailed

    /// There is no workout: it was finished or discarded.
    case ended

    /// The state to render.
    ///
    /// **A held workout outranks a failure**, and while one is held the failure can only be a
    /// write's — the screen keeps the workout and renders the failure beside the commands.
    ///
    /// **With no workout held, a failure is a read's, and it is not the same fact as "ended".** The
    /// store answers both with a `nil` session; reporting the first as the second tells a user
    /// whose workout is still in progress that it has been finished or discarded, and leaves them
    /// nothing to retry.
    ///
    /// - Parameters:
    ///   - hasChecked: ``ActiveSessionStore/hasCheckedForSession``.
    ///   - session: ``ActiveSessionStore/session``.
    ///   - failure: ``ActiveSessionStore/failure``.
    /// - Returns: The current state.
    static func current(hasChecked: Bool, session: WorkoutSession?, failure: String?) -> Self {
        if !hasChecked { return .loading }
        if let session { return .inProgress(session, writeFailed: failure != nil) }
        if failure != nil { return .readFailed }
        return .ended
    }
}
