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
/// **The lifecycle is here, and so is anything a screen pushed *above* the workout can change.**
/// Starting a workout, finding the one left in progress, finishing it and discarding it are this
/// object's (`FR-1.2.1`, `FR-1.2.11`, `FR-1.2.12`), and so are its exercises (`FR-1.2.2`) — the
/// chooser that adds one is a screen of its own, so a list held on the session screen would be
/// rebuilt after the write it is meant to show. The sets inside one exercise are not: they are
/// logged on the card that displays them, with nothing above it. Anything a *screen* alone needs —
/// a date the user is choosing but has not started on, a confirmation that is open, which cards are
/// collapsed — belongs on that screen's state instead.
///
/// **Every mutation is written through before it is held** (`NFR-1.8`). Nothing here batches, and
/// nothing waits for a "save" the user never presses: the app is force-quit mid-set as a matter of
/// course, and a workout that only existed in memory is a workout that did not happen. That posture
/// is this task's to establish and the rest of the logging track's to inherit.
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

    /// Whether the store has looked for a workout in progress yet (`FR-1.2.11`).
    ///
    /// **The difference between "no workout" and "not asked yet"**, which ``session`` alone cannot
    /// carry: both are `nil` there, and a screen that read the first as the second would offer to
    /// start a workout for a moment before the one already in progress appeared. It stays `true`
    /// once ``resume()`` has answered, including when it answered with a failure — a screen deciding
    /// what to show needs to know the read is over, not whether it went well.
    public private(set) var hasCheckedForSession = false

    /// The workout's exercises, in ``RepositoryInterface/ExerciseEntry/order`` (`FR-1.2.2`).
    ///
    /// **On the store rather than on the session screen, and that is what the picker decides.**
    /// Choosing an exercise happens on a screen pushed *above* the workout, so the write and the
    /// list that shows it are on opposite sides of a navigation push — held on the screen, the list
    /// would be built after the write it is supposed to display. It is the same argument that puts
    /// the session here at all.
    public private(set) var exercises: [SessionExercise] = []

    /// Whether the exercises have been read for the session currently held.
    ///
    /// Separate from ``hasCheckedForSession`` for that property's own reason: an empty workout and
    /// one whose exercises have not been read are both an empty array, and a screen that read the
    /// second as the first would announce "no exercises yet" over a workout that has six.
    public private(set) var hasLoadedExercises = false

    /// The last *read* of the exercises that failed, as the error's description, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`). Kept apart from ``exercisesWriteFailure`` deliberately:
    /// one diagnostic read as two facts is the defect T-1.20's review found on this store, and the
    /// two say opposite things here — a failed read costs the screen its list, a failed write costs
    /// it nothing.
    public private(set) var exercisesReadFailure: String?

    /// The last *write* against the exercises that failed, as the error's description, or `nil`.
    ///
    /// See ``exercisesReadFailure``. A **diagnostic**, not copy (`G-3.4`).
    public private(set) var exercisesWriteFailure: String?

    private let repository: any WorkoutRepository
    private let catalogue: any ExerciseRepository

    /// Builds the store over the two repositories the workout is assembled from.
    ///
    /// - Parameters:
    ///   - repository: Sessions, their entries and their sets.
    ///   - catalogue: The exercises those entries name. A second protocol rather than a join,
    ///     because the schema declares no relationships (`G-2.5`) — see ``SessionExercise``.
    public init(repository: any WorkoutRepository, catalogue: any ExerciseRepository) {
        self.repository = repository
        self.catalogue = catalogue
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
        forgetExercises()
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
        defer { hasCheckedForSession = true }
        guard session == nil else { return }
        do {
            session =
                try await repository
                .sessions(in: Date.distantPast...Date.distantFuture, includingDeleted: false)
                .first { $0.endedAt == nil }
            failure = nil
        } catch {
            session = nil
            failure = String(describing: error)
        }
        forgetExercises()
    }

    /// Starts a workout on `day` and holds it (`FR-1.2.1`).
    ///
    /// **The row is written before it is held, and before the user has logged anything into it**
    /// (`NFR-1.8`): a session that existed only in memory until the first set would lose the whole
    /// workout to a force-quit before that set, and would also be invisible to ``resume()``.
    ///
    /// **`date` is the training day, normalised to its start**, so a workout backdated to a past
    /// date and one started today are the same kind of value — the day, not the moment the form was
    /// filled in. The moment is ``RepositoryInterface/WorkoutSession/startedAt``, which is `.now`
    /// either way: the app is tracking this workout live from here, whichever day it belongs to.
    ///
    /// A second workout is refused while one is in progress. There is one active session by
    /// construction — that is what makes this a store rather than a screen's state — and the way to
    /// start another is to finish or discard this one.
    ///
    /// - Parameter day: The training day the workout belongs to. Today, unless the user backdated.
    public func start(on day: Date) async {
        guard session == nil else { return }
        let now = Date.now
        let started = WorkoutSession(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            date: Calendar.current.startOfDay(for: day),
            startedAt: now,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        do {
            try await repository.save(started)
            // Re-read rather than hold what was handed in, for ``update(_:)``'s reason: the save
            // path stamps `updatedAt` itself. A row that is not there afterwards is the same failure
            // it is there — the record this call just wrote is gone.
            guard let stored = try await repository.session(id: started.id, includingDeleted: false)
            else {
                throw RepositoryError.recordNotFound(id: started.id)
            }
            session = stored
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasCheckedForSession = true
        forgetExercises()
    }

    /// Finishes the workout in progress (`FR-1.2.11`).
    ///
    /// The row stays: finishing is what `endedAt` records, and a finished session is the history
    /// every later track reads. What ends is this store holding it — ``resume()`` will not find it
    /// again, which is the whole of "incomplete sessions resume on next launch".
    ///
    /// A write that fails keeps the workout held and reports the failure, so the next tap is another
    /// attempt at the same command rather than a lost session.
    public func finish() async {
        guard let current = session, current.endedAt == nil else { return }
        await update(Self.ended(current, at: .now))
        guard failure == nil else { return }
        session = nil
        forgetExercises()
    }

    /// Discards the workout in progress (`FR-1.2.12`).
    ///
    /// **Soft, like every deletion here** (`G-1.3`): the repository stamps `deletedAt` and cascades
    /// to the entries and sets underneath, and nothing is removed from the store until an explicit
    /// purge runs. The confirmation `FR-1.2.12` asks for is the screen's — a store cannot ask.
    public func discard() async {
        guard let current = session else { return }
        do {
            try await repository.deleteSession(id: current.id)
            session = nil
            failure = nil
            forgetExercises()
        } catch {
            failure = String(describing: error)
        }
    }

    /// Reads the workout's exercises, their sets and the catalogue rows they name (`FR-1.2.2`).
    ///
    /// **Three reads per call and one per exercise**, which is what a schema with no relationships
    /// costs (`G-2.5`). It is a small cost at this size: a workout is a handful of exercises, the
    /// store is local and synchronous under the `async` signature (`G-2.2`, `G-2.3`), and the
    /// alternative — caching a join across a screen boundary — is a second source of truth for rows
    /// the picker above is writing (`G-1.4`).
    ///
    /// **No workout means no list**, and it is not a failure: the screen showing it has its own
    /// state for a workout that has ended.
    ///
    /// A read that fails **does** cost the list its rows, on the exercise library's rule: the screen
    /// can no longer vouch for what it is showing, and the state with the retry in it is the one
    /// that has nothing.
    public func loadExercises() async {
        guard let current = session else {
            forgetExercises()
            return
        }
        do {
            let entries = try await repository.entries(forSessionID: current.id, includingDeleted: false)
            var loaded: [SessionExercise] = []
            loaded.reserveCapacity(entries.count)
            for entry in entries {
                loaded.append(
                    SessionExercise(
                        entry: entry,
                        exercise: try await catalogue.exercise(id: entry.exerciseID, includingDeleted: false),
                        sets: try await repository.sets(forEntryID: entry.id, includingDeleted: false)
                    )
                )
            }
            exercises = loaded
            exercisesReadFailure = nil
        } catch {
            exercises = []
            exercisesReadFailure = String(describing: error)
        }
        hasLoadedExercises = true
    }

    /// Appends `exerciseID` to the workout (`FR-1.2.2`, `FR-1.2.13`).
    ///
    /// **Appended, never inserted.** `FR-1.2.13` says so outright, and the reason is the scroll
    /// position: an exercise that landed next to whichever card the user was looking at would move
    /// the list under their thumb mid-workout. The new entry's order is one past the highest in the
    /// workout rather than the count, so a list that has already been reordered — or that has a gap
    /// a soft-deleted entry left — still gets a position no other row holds.
    ///
    /// **Written through before it is held** (`NFR-1.8`), like every other mutation here, and the
    /// list is then re-read rather than appended to in memory: the entry's stored `updatedAt` is the
    /// save path's, and the sets and catalogue row it is shown with are reads of their own.
    ///
    /// - Parameter exerciseID: The catalogue row to add. A dangling one is refused by the
    ///   repository and reported as a failed write.
    public func addExercise(id exerciseID: UUID) async {
        guard let current = session else { return }
        do {
            // Read for the highest position rather than measuring the held list: the chooser can be
            // reached by a restored navigation stack that never drew the workout, in which case
            // nothing has been loaded and every exercise would be added at position zero.
            let stored = try await repository.entries(forSessionID: current.id, includingDeleted: false)
            let now = Date.now
            try await repository.save(
                ExerciseEntry(
                    id: UUID(),
                    createdAt: now,
                    updatedAt: now,
                    deletedAt: nil,
                    sessionID: current.id,
                    exerciseID: exerciseID,
                    order: (stored.map(\.order).max() ?? -1) + 1,
                    notes: ""
                )
            )
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Moves the exercise at `source` to `destination`, renumbering the workout (`FR-1.2.2`).
    ///
    /// **Only the rows whose position actually changed are written.** Saving all of them would
    /// restamp `updatedAt` on rows that did not move — and `updatedAt` is `G-2.4`'s conflict key, so
    /// a no-op local write outranks a real remote edit. Moving the first of six to the end is five
    /// writes, not six.
    ///
    /// **A partial write is left visible rather than rolled back.** There is no transaction across
    /// repository calls, so a failure halfway leaves some rows renumbered; the list is re-read
    /// afterwards either way, so what the user sees is what is stored, with the failure beside it.
    /// Rolling back by hand would be a second unprotected sequence of writes with the same problem.
    ///
    /// - Parameters:
    ///   - source: The position the exercise is at now.
    ///   - destination: The position it should be at. Out-of-range or unchanged positions do
    ///     nothing, which is what makes a "move up" on the first card a no-op rather than a guard on
    ///     every caller.
    public func moveExercise(from source: Int, to destination: Int) async {
        guard source != destination,
            exercises.indices.contains(source),
            exercises.indices.contains(destination)
        else { return }
        var reordered = exercises
        reordered.insert(reordered.remove(at: source), at: destination)
        do {
            for (position, item) in reordered.enumerated() where item.entry.order != position {
                try await repository.save(Self.renumbered(item.entry, to: position))
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Whether a workout is in progress — what the screen-wake policy and every entry point read.
    public var isActive: Bool { session != nil }

    /// How far through the workout the user is (`FR-1.2.13`).
    public var progress: SessionProgress { SessionProgress(exercises) }

    /// Drops the exercise list, because the workout it belonged to is no longer the one held.
    ///
    /// **Both diagnostics go with it.** A failure describes a read or a write against a workout, and
    /// carrying one across a change of session would report it against the next one.
    private func forgetExercises() {
        exercises = []
        hasLoadedExercises = false
        exercisesReadFailure = nil
        exercisesWriteFailure = nil
    }

    /// `entry` at a new position, and every other field untouched.
    ///
    /// Rebuilt rather than mutated for ``ended(_:at:)``'s reason: the record is a value with `let`
    /// properties, and the write path stamps `updatedAt` itself.
    private static func renumbered(_ entry: ExerciseEntry, to order: Int) -> ExerciseEntry {
        ExerciseEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            sessionID: entry.sessionID,
            exerciseID: entry.exerciseID,
            order: order,
            notes: entry.notes
        )
    }

    /// `session` with `endedAt` set, and every other field untouched.
    ///
    /// Rebuilt rather than mutated because the record is a value with `let` properties, and the
    /// three timestamps are carried across because the write path is an upsert that stamps
    /// `updatedAt` itself.
    private static func ended(_ session: WorkoutSession, at moment: Date) -> WorkoutSession {
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
            scheduledWorkoutID: session.scheduledWorkoutID
        )
    }
}
