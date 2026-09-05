import DerivedValues
import Foundation
import PowerliftingCore
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
/// logged on the card that displays them — but through this object all the same, because the card
/// is drawn from ``exercises`` and a set written anywhere else would not appear in it. Anything a
/// *screen* alone needs — a date the user is choosing but has not started on, a confirmation that is
/// open, which cards are collapsed, what is half-typed into the set editor — belongs on that
/// screen's state instead.
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
    ///
    /// Settable across the module rather than only within this file, because every command that can
    /// set it lives in `ActiveSessionCommands.swift`. Nothing outside `Logging` can write it.
    public internal(set) var exercisesWriteFailure: String?

    /// The last attempt to store `FR-1.2.9`'s session note that failed, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and a third one rather than a reading of ``failure``
    /// for the reason the two above are kept apart: a failed note save leaves the workout, its
    /// cards and the typed text exactly as they were, and the retry the user reaches for is the
    /// **Save** beside the field rather than **Finish** at the foot of the screen.
    var noteWriteFailure: String?

    /// How many sets the workout still holds that nobody has attempted (`FR-16.4.4`) — `0` where
    /// there is nothing to answer for.
    ///
    /// **Set by ``finish(resolving:)`` from the read that declined to end the workout**, so the
    /// number in the alert and the rows it is about are one answer; see ``pendingSets()`` for why a
    /// projection of ``exercises`` is not.
    public private(set) var pendingSetCount = 0

    /// Why the program's day cursor did not move when the last workout was finished
    /// (`FR-16.8.4`), or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`): the workout *was* stored, and the screen that can say
    /// what was not is the one drawing the program's next day. **Not cleared by
    /// ``forgetExercises()``**, being set after that workout has been let go of; retired by
    /// ``retryProgramAdvance()``, the only thing that knows whether the cursor has since moved.
    public internal(set) var programAdvanceFailure: String?

    /// The finished workout the report above is owed to, held so it can be retried at all.
    var unadvancedSession: WorkoutSession?
    /// What each card's "last time" strip is drawn from (`FR-1.2.10`).
    ///
    /// One value rather than three properties — see ``PreviousPerformances``.
    var previous = PreviousPerformances()

    /// Which of the workout's sets hold a personal record (`FR-1.6.3`).
    ///
    /// **Refreshed inside ``loadExercises()`` rather than by a call of its own**, which is what makes
    /// the badge appear in the same interaction the set was logged in. Every writer of a set column
    /// already `await`s `PersonalRecordRecomputer.setDidChange(inEntryID:)` and *then* re-reads the
    /// list, so by the time this runs the recompute has written the cache and the read below is a
    /// cache hit — the confirmed answer, with no optimistic mark to correct afterwards.
    private(set) var personalRecords = SessionRecordMarks()

    /// The unit a load is entered and shown in (`G-3.1`, `G-3.2`, `FR-1.10.2`).
    ///
    /// **On this store rather than read by the editor, for the reason the exercises are here.** The
    /// set editor is presented over the workout and the cards under it render the same loads, so a
    /// unit read per surface is one settings row read three times and three chances to disagree
    /// about what a number on screen means.
    ///
    /// **Kilograms until the row has been read, and after a read that failed.** It is the schema's
    /// own default, so it is what a first launch would have found anyway; the alternative is a
    /// weight field with no unit on it, which is worse than one showing the majority default. A
    /// failure here is deliberately not a diagnostic — the workout is still loggable, and the
    /// screen has nothing useful to say about it that "kg" does not already say.
    public private(set) var displayUnit: MassUnit = .kilograms

    /// Sessions, their entries, their sets — and the targets a routine planned for them
    /// (`TR-15.3`).
    ///
    /// **Two protocols on one value rather than two properties**, which states the invariant
    /// instead of hoping for it: a planned target hangs off an entry, so a store that could hold
    /// one repository for the entries and another for their plans could be handed two different
    /// stores and would write half a session into each.
    ///
    /// Internal rather than private because the write commands live in `ActiveSessionCommands.swift`
    /// — `private` is file-scoped, and this type is three files.
    let repository: any WorkoutRepository & PlannedTargetRepository

    /// The exercises those entries name. See ``repository``.
    let catalogue: any ExerciseRepository

    /// What performs `FR-1.2.7`'s edit and delete — see ``LoggedSetWriter`` for why they are not
    /// this object's own writes.
    ///
    /// Built per call rather than stored: it holds ``repository`` and ``records`` and nothing else,
    /// so a second one is not a second writer.
    var setWriter: LoggedSetWriter {
        LoggedSetWriter(repository: repository, records: records)
    }

    /// What is told that a set moved (`FR-1.6.4`, `TR-1.6`).
    ///
    /// Internal for ``setWriter``'s reason — the three commands that write a set column themselves
    /// live in `ActiveSessionCommands.swift`, and `private` is file-scoped.
    let records: PersonalRecordRecomputer

    private let settings: any SettingsRepository

    /// Where `FR-16.7.1`'s training max comes from — see ``SessionTrainingMax``.
    let trainingMaxes: any TrainingMaxRepository

    /// The programs, their days and the run in force (`FR-16.8`) — **stored rather than passed in
    /// like ``start(on:fromRoutineID:in:)``'s routines**, the cursor moving at ``finish(resolving:)``, which
    /// every screen calls with no program in its hands.
    let programs: any ProgramRepository

    /// The chain every command in `ActiveSessionCommands.swift` runs in.
    ///
    /// **Two taps are two writes, not one.** Each command re-reads what it is about to extend when
    /// it runs, and every one of them suspends on the repository — so without this, a second tap
    /// arriving mid-write computes against the list the first one is about to replace, and one of
    /// the two is silently lost. Queued instead, the second sees what the first stored. Same idiom,
    /// same reason, as the exercise detail screen's notes chain.
    ///
    /// **One chain for the exercises and the sets together**, not one each: a set is written against
    /// an entry, and that entry can be moved or added by the same thumb between two taps of
    /// **Log set**.
    var pendingWrite: Task<Void, Never>?

    /// Builds the store over the three repositories the workout is assembled from.
    ///
    /// - Parameters:
    ///   - repository: Sessions, their entries, their sets and their planned targets — one value
    ///     answering two protocols, for the reason ``repository`` gives.
    ///   - catalogue: The exercises those entries name. A second protocol rather than a join,
    ///     because the schema declares no relationships (`G-2.5`) — see ``SessionExercise``.
    ///   - settings: The single settings row, for the unit a load is entered in. A third protocol
    ///     rather than a unit passed in, so that nothing above this has to know a preference decides
    ///     what a typed number means.
    ///   - records: The app's one recompute actor (`TR-1.6`). Not a repository: what a set changing
    ///     owes is a recomputation, and handing this store the cache instead would make it the
    ///     second thing in the app that knows how a personal record is derived.
    ///   - trainingMaxes: Where `FR-16.7.1`'s training max is stored — see ``SessionTrainingMax``.
    ///   - programs: The programs and the run in force (`FR-16.8`) — see ``programs``.
    public init(
        repository: any WorkoutRepository & PlannedTargetRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer,
        trainingMaxes: any TrainingMaxRepository,
        programs: any ProgramRepository
    ) {
        self.repository = repository
        self.catalogue = catalogue
        self.settings = settings
        self.records = records
        self.trainingMaxes = trainingMaxes
        self.programs = programs
    }

    /// Reads the unit a load is entered and shown in (`G-3.1`, `G-3.2`).
    ///
    /// **Read again whenever the screen appears, not once at launch.** The preference is changed in
    /// a different tab, and a store that cached it would show a workout in kilograms to a user who
    /// had just switched to pounds — with the ± controls still stepping by half a kilo.
    ///
    /// A failure leaves the unit as it was, for ``displayUnit``'s reason.
    public func loadDisplayUnit() async {
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
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
            try await persist(session)
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
        await start(on: day, stampedWith: nil)
    }

    /// ``start(on:)``, with the program run the workout belongs to written into the row it creates
    /// (`FR-16.8.3`) — at creation rather than in a second write, because a workout that existed
    /// for one write without its week is one a force-quit leaves belonging to none (`NFR-1.8`).
    ///
    /// - Parameters:
    ///   - day: The training day the workout belongs to.
    ///   - stamp: The run, week and day index, or `nil` outside a program.
    func start(on day: Date, stampedWith stamp: ProgramSessionStamp?) async {
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
            programRunID: stamp?.runID,
            scheduledWorkoutID: nil,
            weekNumber: stamp?.weekNumber,
            dayIndex: stamp?.dayIndex
        )
        do {
            try await persist(started)
            failure = nil
        } catch {
            failure = String(describing: error)
        }
        hasCheckedForSession = true
        forgetExercises()
    }

    /// Reads the workout's exercises, their sets and the catalogue rows they name (`FR-1.2.2`).
    ///
    /// **Three reads per call and two per exercise**, which is what a schema with no relationships
    /// costs (`G-2.5`) — the second of the two is the plan a routine left on the entry (`TR-15.3`),
    /// read here rather than once at start so that a card rebuilt after any write still has it. It
    /// is a small cost at this size: a workout is a handful of exercises, the
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
                        sets: try await repository.sets(forEntryID: entry.id, includingDeleted: false),
                        planned: try await repository.plannedTargets(
                            forEntryID: entry.id, includingDeleted: false),
                        trainingMax: try await SessionTrainingMax.inForce(
                            trainingMaxes, forExerciseID: entry.exerciseID, on: current.date)
                    )
                )
            }
            exercises = loaded
            personalRecords = await recordMarks(over: loaded)
            exercisesReadFailure = nil
        } catch {
            exercises = []
            personalRecords = SessionRecordMarks()
            exercisesReadFailure = String(describing: error)
        }
        hasLoadedExercises = true
    }

    /// Drops the exercise list, because the workout it belonged to is no longer the one held.
    ///
    /// **All three diagnostics go with it, and so do the previous-performance answer and the record
    /// marks.** A failure
    /// describes a read or a write against a workout, and carrying one across a change of session
    /// would report it against the next one; the "last time" strips are keyed on the *entries* of
    /// the workout just dropped, so keeping them would draw one workout's history on another's
    /// cards. The marks are keyed on sets that are not in the next workout at all, so they would
    /// answer nothing rather than answer wrongly — dropped anyway, because a badge is a claim about
    /// the workout on screen.
    ///
    /// The note's diagnostic is on that list rather than left to the screen that clears it on the
    /// next keystroke: two workouts whose notes are both empty produce no keystroke, so the field
    /// would open on the next workout already carrying the last one's failure.
    ///
    /// Every caller replaces the held session or drops it, which is what makes clearing all of them
    /// safe — nothing here runs while the workout a diagnostic belongs to is still on screen.
    private func forgetExercises() {
        exercises = []
        personalRecords = SessionRecordMarks()
        hasLoadedExercises = false
        exercisesReadFailure = nil
        exercisesWriteFailure = nil
        noteWriteFailure = nil
        previous = PreviousPerformances()
    }

    /// Writes one session record through and holds what the store kept.
    ///
    /// **The re-read is not a courtesy.** The save path stamps `updatedAt` itself, so the record
    /// handed in describes the write before this one; holding it would leave the store one version
    /// behind `G-2.4`'s conflict key. A row that is not live afterwards is a **failure** — it is the
    /// record this call just wrote, so it went away underneath a screen that is logging into it.
    ///
    /// Internal rather than private because the note command is in another file, and shared by all
    /// three writers rather than written out three times.
    ///
    /// - Parameter session: The record to store.
    func persist(_ session: WorkoutSession) async throws {
        try await repository.save(session)
        guard let stored = try await repository.session(id: session.id, includingDeleted: false)
        else {
            throw RepositoryError.recordNotFound(id: session.id)
        }
        self.session = stored
    }

    /// Adopts the row a write made elsewhere in this module produced, and retires the diagnostic.
    ///
    /// **Here rather than a wider setter on ``session``**, which is `private(set)` deliberately: one
    /// object with one writer is what keeps two screens from holding two versions of a workout.
    /// These two name the transitions another file in this module needs, and nothing else.
    ///
    /// - Parameter stored: The session as the store holds it.
    func adopt(stored: WorkoutSession) {
        session = stored
        failure = nil
    }

    /// Records what ``finish(resolving:)``'s read found, so the screen can ask about it.
    ///
    /// - Parameter count: The sets nobody attempted, or `0` once nothing is owed an answer.
    func notePendingSets(_ count: Int) { pendingSetCount = count }

    /// Lets go of the workout that has just ended or been discarded, and of everything drawn from
    /// it.
    func releaseHeldSession() {
        session = nil
        failure = nil
        pendingSetCount = 0
        forgetExercises()
    }

    /// Reports a write that did not land. The held workout is left alone; see ``update(_:)``.
    ///
    /// - Parameter error: What the store said.
    func report(_ error: any Error) {
        failure = String(describing: error)
    }
}
