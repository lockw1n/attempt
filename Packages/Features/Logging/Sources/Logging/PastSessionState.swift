import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One past session's data and the reads and writes behind it (`FR-1.2.7`, `FR-1.2.9`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on `SessionListState`'s rule: nothing
/// here outlives the screen. That is the whole difference from ``ActiveSessionStore``, which exists
/// because the workout in progress is shown by several screens at once; a session finished last
/// Tuesday is shown by this one.
///
/// **It carries the session's identifier and reads it, rather than being handed a record**
/// (`G-1.4`). The route carries an id; a stale or foreign one resolves to nothing, and that is
/// ``Phase/missing`` rather than a failure — reading again resolves to nothing again.
///
/// **Two writers rather than commands of its own**, both below the workout in progress and for the
/// reason each gives: ``LoggedSetWriter`` for `FR-1.2.7`'s edit and delete, ``SessionNoteWriter``
/// for `FR-1.2.9`'s note. What is left here is the re-read after one, which is what puts the
/// corrected row on screen.
@Observable
final class PastSessionState {
    /// What the screen has to show, as one value rather than four flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The first read is in flight.
        case loading

        /// The session. Its exercises are ``exercises`` — see that property for why they are not in
        /// here.
        case loaded(WorkoutSession)

        /// The identifier resolved to no live session. **Terminal**: reading again resolves to
        /// nothing again, so the screen offers no retry.
        case missing

        /// The read failed, carrying the error's description — a **diagnostic**, not copy (`G-3.4`).
        /// Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// The session this screen holds, or `nil` in every state where it holds none.
    ///
    /// **A re-read answers `nil` here for as long as it is out**, ``Phase/loading`` carrying no
    /// record — which is why the note draft follows this through
    /// ``SessionNoteDraft/follow(holding:)`` rather than through ``SessionNoteDraft/follow(_:)``: the gap is the
    /// screen reading, not the session going away.
    var session: WorkoutSession? {
        guard case .loaded(let session) = phase else { return nil }
        return session
    }

    /// The session's exercises and their sets, in entry order.
    ///
    /// **Beside ``phase`` rather than inside its loaded case**, because the two do not move
    /// together: a write re-reads the exercises and leaves the session record exactly as it was, so
    /// carrying them in the case would republish the whole screen on every corrected set.
    private(set) var exercises: [SessionExercise] = []

    /// Which of the session's sets hold a record, and at which schemes (`FR-17.7.2`).
    ///
    /// **Read once per read of the exercises, not once per row** — ``SessionRecordMarks/read(over:from:)``,
    /// shared with the workout in progress so the two screens say the same thing about one set.
    ///
    /// **Before the first read it is a value that knows it has not looked**, which is what keeps a
    /// session drawn mid-read from reading as one with no records in it.
    private(set) var personalRecords = SessionRecordMarks()

    /// The last edit or deletion that failed, as the error's description, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and deliberately not a ``Phase``: a failed write leaves
    /// every row on screen exactly as it was, where a failed read leaves the screen unable to vouch
    /// for what it is showing. It is `ActiveSessionStore`'s split between its two, kept here.
    private(set) var writeFailure: String?

    /// The last attempt to store `FR-1.2.9`'s note that failed, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`). A third one rather than a reading of ``writeFailure``
    /// for `ActiveSessionStore`'s reason: the retry a failed note offers is the **Save note** beside
    /// the field, not the set editor.
    ///
    /// Settable from the screen, which retires it on the next keystroke — the banner describes one
    /// attempt to store one piece of text.
    var noteWriteFailure: String?

    /// The unit a load is shown in (`G-3.1`, `G-3.2`).
    ///
    /// **Kilograms until the settings row has been read, and after a read that failed** — the
    /// schema's own default, on `ActiveSessionStore`'s argument: a load with no unit on it is worse
    /// than one showing the majority default, and a failure here is nothing this screen can say
    /// anything useful about.
    private(set) var displayUnit: MassUnit = .kilograms

    /// Whether this session was a day of a program (`FR-17.7.6`).
    ///
    /// **The stamp decides the shape of the screen**, and it is the session's own columns rather
    /// than the presence of planned targets: a workout started from a routine outside a program has
    /// a plan and is not a day, and a day whose every exercise the lifter replaced has no planned
    /// targets left and still is one.
    var isPlannedDay: Bool { session?.programPosition != nil }

    /// The day's rows, as the checklist draws them (`FR-17.7.6`).
    ///
    /// **Derived rather than kept**, which is ``DayStore/rows``' rule and its reason: a write here
    /// re-reads ``exercises``, and a second stored copy would be a second answer to keep in step.
    var dayRows: [DayRow] {
        exercises.map { DayRow.performed($0, marks: personalRecords) }
    }

    /// How much of what the routine prescribed was performed as prescribed (`FR-17.7.3`,
    /// `FR-15.3.3`), or `nil` where there is nothing to report.
    ///
    /// **Only once the day is done**, which is what `FR-17.7.3` was rewritten to say (`D-17.6`): a
    /// day still being answered has rows nobody has reached, and a ratio counting those against the
    /// lifter would fall as the plan was performed. `nil` for a workout that prescribed nothing, on
    /// ``SessionAdherence``'s own rule.
    var adherence: SessionAdherence? {
        guard let session, session.isFinished else { return nil }
        return SessionAdherence(exercises)
    }

    /// The session this screen is about — what the route carried.
    @ObservationIgnored let sessionID: UUID

    /// What performs `FR-1.2.7`'s edit and delete.
    ///
    /// Built per call rather than stored, on ``ActiveSessionStore/setWriter``'s reason: it holds the
    /// repository and nothing else, so a second one is not a second writer.
    @ObservationIgnored private var setWriter: LoggedSetWriter {
        LoggedSetWriter(repository: workouts, records: records)
    }

    /// What performs `FR-1.2.9`'s note. Built per call, for ``setWriter``'s reason.
    @ObservationIgnored private var noteWriter: SessionNoteWriter { SessionNoteWriter(repository: workouts) }

    /// Sessions, their entries, their sets **and their planned targets** — one value conforming to
    /// both, as ``ActiveSessionStore/repository`` is.
    ///
    /// **Widened for `FR-15.3.1`**: a past day draws each row's plan beside its actual, and the
    /// plan is the snapshot `TR-15.3` hangs off the entry. Two properties would be two ways to
    /// reach one store.
    @ObservationIgnored private let workouts: any WorkoutRepository & PlannedTargetRepository
    @ObservationIgnored private let catalogue: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// What is told that a set moved (`FR-1.6.4`). A past session's sets are edited from here, which
    /// is the History-side half of the trigger `LoggedSetWriter` carries.
    @ObservationIgnored private let records: PersonalRecordRecomputer

    /// Where `FR-16.7.1`'s training max comes from — read at the session's own day.
    @ObservationIgnored private let trainingMaxes: any TrainingMaxRepository

    /// Builds the state over the session it is about and the three repositories it reads.
    ///
    /// - Parameters:
    ///   - sessionID: The session the route named.
    ///   - workouts: The sessions, their entries and their sets.
    ///   - catalogue: The exercises those entries name. A second protocol rather than a join,
    ///     because the schema declares no relationships (`G-2.5`) — see ``SessionExercise``.
    ///   - settings: The single settings row, for the unit the loads are shown in.
    ///   - records: The app's one recompute actor (`TR-1.6`).
    ///   - trainingMaxes: Where `FR-16.7.1`'s training max is stored.
    init(
        sessionID: UUID,
        workouts: any WorkoutRepository & PlannedTargetRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer,
        trainingMaxes: any TrainingMaxRepository
    ) {
        self.sessionID = sessionID
        self.workouts = workouts
        self.catalogue = catalogue
        self.settings = settings
        self.records = records
        self.trainingMaxes = trainingMaxes
    }

    /// Reads the session, its exercises and the display unit.
    ///
    /// **Re-read on every appearance**, on `SessionListState`'s rule — this screen is returned to
    /// from the exercise detail T-1.36 will link to, and the unit is changed in another tab.
    ///
    /// **A read already in flight is skipped**, so an appearance arriving while the first read is
    /// out does not run it twice.
    ///
    /// A read that fails costs the screen its rows, on the exercise library's rule: it can no longer
    /// vouch for what it is showing, and the state with the retry in it is the one that has nothing.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        // Both diagnostics are retired here: each describes one attempt against rows this read is
        // about to replace, so a banner that outlived it would be reporting a failure the user can
        // no longer act on against a screen that has since been rebuilt.
        writeFailure = nil
        noteWriteFailure = nil
        await loadDisplayUnit()
        do {
            guard let session = try await workouts.session(id: sessionID, includingDeleted: false)
            else {
                exercises = []
                phase = .missing
                return
            }
            exercises = try await readExercises(on: session.date)
            phase = .loaded(session)
        } catch {
            exercises = []
            phase = .failed(String(describing: error))
        }
    }

    /// Rewrites one logged set (`FR-1.2.7`).
    ///
    /// **The rows are re-read whether or not anything was written**, on `ActiveSessionStore`'s rule:
    /// a set the writer could not find is a set still drawn on the card, and the re-read is what
    /// sweeps it off.
    ///
    /// - Parameters:
    ///   - setID: The set to rewrite.
    ///   - entryID: The exercise it belongs to.
    ///   - values: What it becomes.
    func editSet(id setID: UUID, inEntryID entryID: UUID, to values: SetEntryValues) async {
        await write { try await setWriter.edit(id: setID, inEntryID: entryID, to: values) }
    }

    /// Soft-deletes one logged set (`FR-1.2.7`, `G-1.3`).
    ///
    /// - Parameters:
    ///   - setID: The set to delete.
    ///   - entryID: The exercise it belongs to.
    func deleteSet(id setID: UUID, inEntryID entryID: UUID) async {
        await write { try await setWriter.delete(id: setID, inEntryID: entryID) }
    }

    /// Rewrites one row's whole answer to what the Log sheet now says (`FR-17.7.5`).
    ///
    /// **``SetGroupRewrite`` and nothing beside it**, which is what makes the past day's edit the
    /// same write the day's own checklist makes: position by position, a lowered count
    /// soft-deletes the trailing rows and a raised one appends, nothing unchanged is written
    /// (`G-2.4`), and every member it touches is marked performed — a member left pending would
    /// make the answer read as **Skipped** (`TR-17.4`).
    ///
    /// **It writes the *performed* sets and never the planned rows.** `FR-16.8.3` keeps a past
    /// session out of a later plan edit's way, and the converse holds here: correcting what was
    /// lifted last Tuesday must not change what `FR-16.8.4`'s **Start next week** would have
    /// proposed from the plan that day was started with.
    ///
    /// **The row is marked done, and only where it is not already.** A row being corrected stays
    /// answered; writing the mark it already carries would restamp `updatedAt`, which is `G-2.4`'s
    /// conflict key.
    ///
    /// **A rowID this screen does not hold writes nothing.** A past day's rows are always entries —
    /// the session exists by definition, so `DayStore`'s slot-to-entry translation has no work to
    /// do here — but the row can still have gone away under a stale sheet, and the absent case is
    /// its own branch rather than a comparison that reads it as answered.
    ///
    /// - Parameters:
    ///   - rowID: The row being answered — an entry, on this screen.
    ///   - group: What the sheet collected.
    func log(rowID: UUID, group: ResolvedSetGroup) async {
        guard let entry = exercises.first(where: { $0.id == rowID })?.entry else { return }
        await write {
            try await SetGroupRewrite(repository: workouts, records: records)
                .rewrite(inEntryID: entry.id, to: group.rows)
            if !entry.isMarkedDone { try await workouts.save(entry.markedDone) }
            return true
        }
        await endDayIfComplete()
    }

    /// Ends the day once its last row has been answered (`FR-17.9.8`).
    ///
    /// **The same rule the checklist applies, because it is the same day.** `DayStore` ends a day
    /// at its last answer, and a row answered from here would otherwise leave `endedAt` unwritten
    /// for good — taking `FR-17.7.3`'s adherence with it, which is withheld until the day is done,
    /// and leaving every unattempted set on it reading as *pending* rather than failed
    /// (`FR-16.4.1`).
    ///
    /// **Nothing to do on a day that was already over**, which is every ordinary correction: a
    /// second `endedAt` is a rewrite of a fact that has not changed (`G-2.4`).
    ///
    /// **`.keepAsFailed`**, which is the checklist's answer and the only one available here: a
    /// past day offers no **Finish**, so there is nobody to ask `FR-16.4.3`'s question of.
    private func endDayIfComplete() async {
        guard let current = session, current.endedAt == nil, !exercises.isEmpty,
            exercises.allSatisfy(\.entry.isMarkedDone)
        else {
            return
        }
        do {
            let ended = try await SessionFinish(workouts: workouts, records: records)
                .finish(current, at: .now, resolving: .keepAsFailed)
            phase = .loaded(
                try await workouts.session(id: ended.id, includingDeleted: false) ?? ended)
        } catch {
            writeFailure = String(describing: error)
        }
    }

    /// What the Log sheet opens over `rowID` (`FR-17.7.5`), or `nil` where the screen has no such
    /// row.
    ///
    /// ``DayStore/editorRow(forRow:)``'s answer read off this screen's own join — the plan and the
    /// sets already stored, which is the whole of what the sheet's row mode needs.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The row, or `nil`.
    func editorRow(forRow rowID: UUID) -> SetEditorRow? {
        guard let exercise = exercises.first(where: { $0.id == rowID }) else { return nil }
        return SetEditorRow(
            plan: exercise.planned.map {
                WeekPlanTarget(
                    id: $0.id, weight: $0.targetWeight, reps: $0.targetReps, sets: $0.targetSets)
            },
            logged: exercise.sets)
    }

    /// Stores the session's note (`FR-1.2.9`, `NFR-1.8`).
    ///
    /// **The session record is re-read on success and only on success**, which is what puts the
    /// stored text where the field's draft compares itself against it. A failure leaves both the
    /// record and the typed text alone, so the retry is another tap at the same command rather than
    /// a note the user has to retype.
    ///
    /// - Parameter text: What the field held when **Save note** was tapped.
    func saveNote(_ text: String) async {
        do {
            let wrote = try await noteWriter.save(id: sessionID, notes: text)
            if wrote, let session = try await workouts.session(id: sessionID, includingDeleted: false) {
                phase = .loaded(session)
            }
            noteWriteFailure = nil
        } catch {
            noteWriteFailure = String(describing: error)
        }
    }

    /// Runs one write and re-reads the exercises behind it.
    ///
    /// **The two are caught separately, because they fail into different states.** A write the
    /// repository turned down leaves every row exactly as it was and is ``writeFailure``'s whole
    /// case. A *re-read* that fails comes after a change that is already stored, so reporting it as
    /// the write's failure would send the user to make a correction that already landed; what it
    /// actually costs is the screen's claim to be showing the session, which is ``Phase/failed(_:)``
    /// and carries the retry.
    ///
    /// - Parameter write: The write to perform. Its answer — whether anything was written — is
    ///   deliberately unused: neither writer reports a row it could not find, and the re-read below
    ///   is what tells the user either way.
    private func write(_ write: () async throws -> Bool) async {
        do {
            _ = try await write()
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
            return
        }
        // No session, nothing to re-read: the screen is already showing `missing` or `failed`, and
        // the day is what every training max here is resolved at.
        guard let day = session?.date else { return }
        do {
            exercises = try await readExercises(on: day)
        } catch {
            exercises = []
            phase = .failed(String(describing: error))
        }
    }

    /// The session's exercises, joined from the three tables a schema with no relationships needs
    /// (`G-2.5`).
    ///
    /// `includingDeleted: false` at every call site, which is what keeps a soft-deleted entry or
    /// set off this screen and agrees with what the session list already counted (`G-1.3`) — and,
    /// for the catalogue, is what ``ActiveSessionStore`` reads the same rows with. `FR-17.7.6` puts
    /// the two screens over one day, so the flag has to be the same on both or one lift changes its
    /// name between them.
    ///
    /// **An archived exercise still names the row it was lifted under, and that costs no flag.**
    /// `FR-1.1.5` archives with a column of its own — `ExerciseRepository` offers no delete at all —
    /// so a lift retired since is read back here whichever way this is set.
    ///
    /// - Parameter day: The session's training day, which `FR-16.7.1`'s annotation is resolved at
    ///   — not today, so a training max raised since does not rewrite what this workout's loads
    ///   were a share of.
    /// - Returns: The join.
    private func readExercises(on day: Date) async throws -> [SessionExercise] {
        let entries = try await workouts.entries(forSessionID: sessionID, includingDeleted: false)
        var loaded: [SessionExercise] = []
        loaded.reserveCapacity(entries.count)
        for entry in entries {
            loaded.append(
                SessionExercise(
                    entry: entry,
                    exercise: try await catalogue.exercise(
                        id: entry.exerciseID, includingDeleted: false),
                    sets: try await workouts.sets(forEntryID: entry.id, includingDeleted: false),
                    planned: try await workouts.plannedTargets(
                        forEntryID: entry.id, includingDeleted: false),
                    trainingMax: try await SessionTrainingMax.inForce(
                        trainingMaxes, forExerciseID: entry.exerciseID, on: day)
                )
            )
        }
        personalRecords = await SessionRecordMarks.read(over: loaded, from: records)
        return loaded
    }

    /// Reads the unit the loads are shown in. A failure leaves it as it was — see ``displayUnit``.
    private func loadDisplayUnit() async {
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
    }
}
