import Foundation
import RepositoryInterface

/// The workout in progress — the first of the two stateful stores `TR-1.2` allows, and the reason
/// the rule is written as an exception rather than as a default (`FR-1.2.1`).
///
/// **What earns a store here is not complexity but lifetime.** A screen's `@Observable` state is
/// created with the screen and speaks for it alone; the session in progress outlives every screen
/// that shows it — the tab it was started from, the exercise picker pushed on top, the plate
/// calculator presented over that — and each of those mutates the same workout. One object with one
/// writer is what keeps two of them from holding two versions of the same session.
///
/// **This is the shape, not the content.** The session's exercises, its sets and the lifecycle that
/// starts and ends one arrive with the logging screens; what is here is the part every one of those
/// needs — a held projection, a read that adopts it, and a write that goes through
/// ``RepositoryInterface/WorkoutRepository``. Anything a *screen* alone needs belongs on that
/// screen's state instead.
@Observable
public final class ActiveSessionStore {
    /// The session being logged, or `nil` when no workout is in progress.
    ///
    /// **Deliberately not a phase enum**, unlike a screen's state: "no workout in progress" is a
    /// normal, long-lived condition of the app rather than a step on the way to showing something,
    /// and every caller has to handle it whatever the read did.
    public private(set) var session: WorkoutSession?

    /// The last read or write that failed, as the error's description, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`).
    public private(set) var failure: String?

    private let repository: any WorkoutRepository

    /// Builds the store over the repository the session is read and written through.
    public init(repository: any WorkoutRepository) {
        self.repository = repository
    }

    /// Holds the session with that id, if a live one exists.
    ///
    /// An unknown or soft-deleted id leaves ``session`` `nil` and is **not** a failure: a stored
    /// navigation position can name a workout the user has since discarded (`TR-1.1` restores one),
    /// and a restored stack must not open on an error.
    public func adopt(sessionID: UUID) async {
        do {
            session = try await repository.session(id: sessionID, includingDeleted: false)
            failure = nil
        } catch {
            session = nil
            failure = String(describing: error)
        }
    }

    /// Replaces the held session with `session` and writes it through.
    ///
    /// The caller supplies the mutated projection: *which* field moved is the screen's business,
    /// and the store's is that exactly one writer reaches storage and that what is held afterwards
    /// is what the store kept.
    ///
    /// Two records are refused rather than written, and neither is defensive.
    ///
    /// - A record equal to the one held: every save restamps `updatedAt`, which is `G-2.4`'s
    ///   conflict key, so a no-op local write would outrank a real remote edit.
    /// - A record carrying a different `id`: ``adopt(sessionID:)`` is how the session in progress
    ///   is chosen, and a write that could also switch it would let a stale screen adopt one.
    ///
    /// A row that is no longer live after its own write is a **failure**, unlike the same answer
    /// from ``adopt(sessionID:)``. There the id came from a restored navigation position and may
    /// name a workout the user discarded long ago; here it names the record this call just wrote,
    /// so it went away underneath a screen that is logging into it, and reporting nothing would
    /// empty the store silently.
    public func update(_ session: WorkoutSession) async {
        guard let current = self.session, current.id == session.id, current != session else { return }
        do {
            try await repository.save(session)
            // Re-read for the same reason the settings screen does: the save path stamps
            // `updatedAt` itself, so the record handed in describes the write before this one.
            guard let stored = try await repository.session(id: session.id, includingDeleted: false) else {
                throw RepositoryError.recordNotFound(id: session.id)
            }
            self.session = stored
            failure = nil
        } catch {
            // The held session is left alone: it is stale, but a screen mid-set has to keep
            // rendering something, and ``adopt(sessionID:)`` is what changes which session that is.
            failure = String(describing: error)
        }
    }
}
