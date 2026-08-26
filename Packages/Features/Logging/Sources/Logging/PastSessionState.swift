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

    /// The session's exercises and their sets, in entry order.
    ///
    /// **Beside ``phase`` rather than inside its loaded case**, because the two do not move
    /// together: a write re-reads the exercises and leaves the session record exactly as it was, so
    /// carrying them in the case would republish the whole screen on every corrected set.
    private(set) var exercises: [SessionExercise] = []

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

    /// The session this screen is about — what the route carried.
    @ObservationIgnored let sessionID: UUID

    /// What performs `FR-1.2.7`'s edit and delete.
    ///
    /// Built per call rather than stored, on ``ActiveSessionStore/setWriter``'s reason: it holds the
    /// repository and nothing else, so a second one is not a second writer.
    @ObservationIgnored private var setWriter: LoggedSetWriter { LoggedSetWriter(repository: workouts) }

    /// What performs `FR-1.2.9`'s note. Built per call, for ``setWriter``'s reason.
    @ObservationIgnored private var noteWriter: SessionNoteWriter { SessionNoteWriter(repository: workouts) }

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let catalogue: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the state over the session it is about and the three repositories it reads.
    ///
    /// - Parameters:
    ///   - sessionID: The session the route named.
    ///   - workouts: The sessions, their entries and their sets.
    ///   - catalogue: The exercises those entries name. A second protocol rather than a join,
    ///     because the schema declares no relationships (`G-2.5`) — see ``SessionExercise``.
    ///   - settings: The single settings row, for the unit the loads are shown in.
    init(
        sessionID: UUID,
        workouts: any WorkoutRepository,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.sessionID = sessionID
        self.workouts = workouts
        self.catalogue = catalogue
        self.settings = settings
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
        await loadDisplayUnit()
        do {
            guard let session = try await workouts.session(id: sessionID, includingDeleted: false)
            else {
                exercises = []
                phase = .missing
                return
            }
            exercises = try await readExercises()
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
    /// - Parameter write: The write to perform. Its answer — whether anything was written — is
    ///   deliberately unused: neither writer reports a row it could not find, and the re-read below
    ///   is what tells the user either way.
    private func write(_ write: () async throws -> Bool) async {
        do {
            _ = try await write()
            exercises = try await readExercises()
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
        }
    }

    /// The session's exercises, joined from the three tables a schema with no relationships needs
    /// (`G-2.5`).
    ///
    /// `includingDeleted: false` at every call site, which is what keeps a soft-deleted entry or set
    /// off this screen and agrees with what the session list already counted (`G-1.3`).
    private func readExercises() async throws -> [SessionExercise] {
        let entries = try await workouts.entries(forSessionID: sessionID, includingDeleted: false)
        var loaded: [SessionExercise] = []
        loaded.reserveCapacity(entries.count)
        for entry in entries {
            loaded.append(
                SessionExercise(
                    entry: entry,
                    exercise: try await catalogue.exercise(
                        id: entry.exerciseID, includingDeleted: false),
                    sets: try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                )
            )
        }
        return loaded
    }

    /// Reads the unit the loads are shown in. A failure leaves it as it was — see ``displayUnit``.
    private func loadDisplayUnit() async {
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
    }
}
