import Foundation
import RepositoryInterface

/// One exercise and the two relationships `FR-1.1.7` makes visible, as the detail screen shows them.
///
/// A value rather than three properties on the state, so a loaded screen cannot hold a variation
/// list belonging to a different exercise.
public struct ExerciseDetail: Sendable, Equatable {
    /// The exercise the screen is about.
    public let exercise: Exercise

    /// The exercise this one varies, if it varies one (`FR-1.1.7`).
    ///
    /// **An archived parent is still shown**, unlike an archived variation below: archiving removes
    /// an exercise from the pickers (`FR-1.1.5`), and dropping it here would not hide a row, it
    /// would assert that this exercise is a root when it is not.
    public let parent: Exercise?

    /// The exercises that name this one as their parent, in ``ExerciseOrder`` (`FR-1.1.7`).
    ///
    /// Archived ones are excluded, on the same rule the list applies: this is a browsable surface
    /// into other detail screens, and `FR-1.1.5` is what takes an exercise out of those.
    public let variations: [Exercise]

    /// Whether any set has ever been logged against this exercise (`FR-1.13.3`).
    ///
    /// **What the three derived sections' copy is conditioned on**, and the reason it is a fact
    /// about the workout store rather than about the catalogue: "log a set and its history appears
    /// here" is true only while no set can exist, and it stops being true the moment one does. A
    /// user who has logged sets and is told to log one has been told the display is missing data it
    /// already has.
    ///
    /// Deleted sets do not count: a set the user removed is not history.
    public let hasLoggedSets: Bool

    /// Whether there is any relationship to show at all.
    ///
    /// The screen omits the variations section when this is `false` — a heading over nothing claims
    /// a relationship that does not exist, and a root exercise with no variations is the ordinary
    /// case rather than a missing one.
    public var hasRelationships: Bool { parent != nil || !variations.isEmpty }
}

/// The exercise detail screen, as state rather than as a view model (`TR-1.2`, `FR-1.1.6`,
/// `FR-1.1.7`).
///
/// `SettingsLandingState`'s pattern, and this is the second screen to take the half of it the list
/// did not need: **a write**, and by `FR-1.1.5` two of them. ``phase``, ``writeFailure`` and
/// ``archiveFailure`` are separate properties because they are separate facts — a save that fails
/// leaves the exercise on screen and the draft in the field, so the next attempt is another tap
/// rather than a relaunch, and one write failing says nothing about the other.
///
/// **The route carries an identifier, so resolving it is this screen's first job and can fail two
/// ways.** ``Phase/failed(_:)`` is a read that went wrong and retries; ``Phase/missing`` is an
/// identifier that named nothing, which a restored navigation stack can do after the exercise is
/// gone, and which retrying cannot fix.
@Observable
public final class ExerciseDetailState {
    /// What the screen has to show, as one value rather than four flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet. ``ExerciseDetailState/load()`` moves out of this.
        case idle

        /// A read is in flight.
        case loading

        /// The exercise and its relationships.
        case loaded(ExerciseDetail)

        /// The identifier resolved to no live exercise. **Terminal**: reading again resolves to
        /// nothing again, so the screen offers no retry.
        case missing

        /// The read failed, carrying the error's description.
        ///
        /// A **diagnostic**, not copy (`G-3.4`). **Recoverable**: ``ExerciseDetailState/load()``
        /// runs again from here.
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The last notes write that failed, as the error's description, or `nil` once one succeeds.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and deliberately not a ``Phase`` — see the type's own
    /// documentation for why a failed write must not cost the screen its read.
    public private(set) var writeFailure: String?

    /// The last archive write that failed, as the error's description, or `nil` once one succeeds.
    ///
    /// A **diagnostic**, not copy (`G-3.4`), and separate from ``writeFailure`` rather than sharing
    /// it: that one is retired by the next keystroke in the notes field, which is right for the
    /// write it describes and would silently drop this one. The two writes fail independently and
    /// are reported independently.
    public private(set) var archiveFailure: String?

    /// What is in the notes field (`FR-1.1.6`).
    ///
    /// The draft, not the stored value: it is set from the record on a read, and diverges from it
    /// while the user types. ``hasUnsavedNotes`` is that divergence.
    ///
    /// **Editing retires ``writeFailure``.** The banner describes one attempt to store one piece of
    /// text, so the next keystroke — including the one that puts the stored value back — is what
    /// ends it. Without that it outlives the edit it belongs to, leaving a retry on screen with
    /// nothing left to write and no way for the user to be rid of it but to leave the screen.
    public var notesDraft: String = "" {
        didSet {
            if notesDraft != oldValue { writeFailure = nil }
        }
    }

    /// Which exercise this screen is about.
    public let exerciseID: UUID

    private let repository: any ExerciseRepository
    private let workouts: any WorkoutRepository

    /// The write chain. See ``saveNotes()``.
    private var pendingWrite: Task<Void, Never>?

    /// Builds the state over the identifier the route carried and the repository it reads through.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise to show. Not the record: a restored stack is decoded before any
    ///     store has been read, and a route holding a copy of a row would be a second source of
    ///     truth for it (`G-1.4`).
    ///   - repository: Where the exercise and the catalogue come from.
    ///   - workouts: Where the sets logged against it come from — read for a count and nothing
    ///     else, which is what ``ExerciseDetail/hasLoggedSets`` needs and all `FR-1.1.6`'s derived
    ///     sections can say until T-1.36, T-1.41 and T-1.43 build them.
    public init(
        exerciseID: UUID,
        repository: any ExerciseRepository,
        workouts: any WorkoutRepository
    ) {
        self.exerciseID = exerciseID
        self.repository = repository
        self.workouts = workouts
    }

    /// Reads the exercise and its relationships, on first appearance and on every retry.
    ///
    /// Re-entrant only through ``Phase/loading``, for the reason `SettingsLandingState.load()`
    /// gives. ``Phase/missing`` is not repeated either, which is what keeps a `.task` that SwiftUI
    /// re-runs from re-reading a store to be told the same absence.
    ///
    /// **Two reads, not one.** The exercise itself answers `FR-1.1.6`; the catalogue answers
    /// `FR-1.1.7`, whose variation list is every row naming this one as its parent and which no
    /// repository method asks for directly. 116 rows filtered in memory is well inside `NFR-1.1`,
    /// and the alternative is a query the repository protocol does not have.
    public func load() async {
        switch phase {
        case .loading, .loaded, .missing: return
        case .idle, .failed: break
        }
        phase = .loading
        do {
            try await publishRead()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Re-reads the exercise and its relationships, keeping what is on screen until they land.
    ///
    /// **This is what the screen's `.task` calls**, not ``load()``, and for the reason
    /// `ExerciseListState.refresh()` gives: an edit made above this screen (`FR-1.1.4`) must be
    /// visible on the way back down, and ``load()`` refuses to run again once it has succeeded.
    ///
    /// **An unsaved note survives it.** The draft follows the record only when the two already
    /// agreed — see ``publishRead(confirming:)`` — so a refresh cannot silently overwrite text the
    /// user has typed and not yet saved.
    ///
    /// ``Phase/missing`` stays terminal: it is not a stale reading, and re-reading resolves to the
    /// same absence.
    public func refresh() async {
        switch phase {
        case .idle, .failed:
            await load()
            return
        case .loading, .missing:
            return
        case .loaded:
            break
        }
        do {
            try await publishRead()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Commits the edited notes (`FR-1.1.6`).
    ///
    /// **The text is taken here, when the command is issued — not when the write reaches the
    /// store.** A save commits what was on screen at the moment it was asked for; anything typed
    /// after that is the next edit and stays on screen as one. Reading the field at write time
    /// instead makes what gets stored depend on where a keystroke fell inside the write, which is
    /// not something a user can see or control.
    ///
    /// **Writes are serialized, for `SettingsLandingState.setDisplayUnit(_:)`'s reason**: the guard
    /// in ``writeNotes(_:)`` decides against ``phase``, which only moves once the write it describes
    /// has landed, so two overlapping saves would both decide against the same stale record and the
    /// second would store again what the first had already stored.
    ///
    /// A save whose text already matches the stored notes writes nothing: every save restamps
    /// `updatedAt`, which is `G-2.4`'s conflict key, so a local no-op would outrank a real remote
    /// edit.
    public func saveNotes() async {
        let submitted = notesDraft
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeNotes(submitted)
        }
        pendingWrite = write
        await write.value
    }

    /// Archives or un-archives the exercise (`FR-1.1.5`).
    ///
    /// **The state is the argument, not a toggle**, which is what makes the command idempotent: two
    /// taps before the first write lands both ask for the same thing, and the second is refused by
    /// the guard in ``writeArchived(_:)`` instead of putting the exercise back.
    ///
    /// **Un-archiving is offered even though `FR-1.1.5` asks only for archiving.** An archive with
    /// no reverse is a one-way door on a screen the user reached to look at an exercise, and the
    /// column it writes is a plain boolean the seed importer keeps rather than re-supplies — so
    /// nothing about the store makes it one-way.
    ///
    /// Serialized behind the notes chain, for ``saveNotes()``'s reason: both writes rebuild the
    /// whole record from the one the screen is showing, so an archive that overlapped a notes save
    /// would store the record as it was before that save and undo it.
    ///
    /// - Parameter archived: What ``RepositoryInterface/Exercise/isArchived`` should become.
    public func setArchived(_ archived: Bool) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeArchived(archived)
        }
        pendingWrite = write
        await write.value
    }

    /// Puts the stored notes back into the field, discarding the edit.
    public func discardNoteEdits() {
        guard case .loaded(let detail) = phase else { return }
        notesDraft = detail.exercise.notes
        writeFailure = nil
    }

    /// Whether the field differs from what is stored — what enables the save and the discard.
    public var hasUnsavedNotes: Bool {
        guard case .loaded(let detail) = phase else { return false }
        return notesDraft != detail.exercise.notes
    }

    /// One link of ``saveNotes()``'s chain: decide against the record as it stands now, then write.
    ///
    /// **The write and the re-read are reported apart, because they fail differently.** A failed
    /// write is ``writeFailure``: nothing reached the store, and the screen keeps both the exercise
    /// and the text. A read that fails *after* the write landed is a failed **read** — the notes are
    /// stored, and what is gone is the screen's picture of them — so it becomes ``Phase/failed(_:)``
    /// and retries through ``load()``. Reporting that one as a failed write would tell the user an
    /// edit was lost when it was not, and its retry would then store the same text a second time,
    /// restamping `G-2.4`'s key for a write that changed nothing.
    ///
    /// - Parameter submitted: The text ``saveNotes()`` was asked to store.
    private func writeNotes(_ submitted: String) async {
        guard case .loaded(let detail) = phase, submitted != detail.exercise.notes else { return }
        do {
            try await repository.save(Self.withNotes(submitted, on: detail.exercise))
        } catch {
            writeFailure = String(describing: error)
            return
        }
        writeFailure = nil
        do {
            // Re-read rather than publish what was handed in: the save path stamps `updatedAt`
            // itself, and the variation list is a second row's business either way.
            try await publishRead(confirming: submitted)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// One link of ``setArchived(_:)``'s chain: decide against the record as it stands, then write.
    ///
    /// A write that would change nothing is skipped, for the reason ``writeNotes(_:)`` gives: every
    /// save restamps `updatedAt`, which is `G-2.4`'s conflict key, so a local no-op would outrank a
    /// real remote edit.
    ///
    /// **The stored notes are carried, not the draft.** Archiving is not a way to commit an edit the
    /// user has not saved — and the re-read that follows keeps that draft on screen.
    ///
    /// The write and the re-read are reported apart, on ``writeNotes(_:)``'s split: a failed write
    /// is ``archiveFailure`` and costs the screen nothing, where a read that fails after the write
    /// landed is a failed read and becomes ``Phase/failed(_:)``.
    ///
    /// - Parameter archived: What ``RepositoryInterface/Exercise/isArchived`` should become.
    private func writeArchived(_ archived: Bool) async {
        guard case .loaded(let detail) = phase, detail.exercise.isArchived != archived else { return }
        do {
            try await repository.save(Self.archived(archived, on: detail.exercise))
        } catch {
            archiveFailure = String(describing: error)
            return
        }
        archiveFailure = nil
        do {
            try await publishRead()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    /// Reads the exercise and the catalogue and publishes the result, or `missing`.
    ///
    /// The notes draft follows the record rather than the other way round, so a save that the store
    /// altered — trimming, a concurrent edit — leaves the field showing what is actually stored.
    ///
    /// - Parameter submitted: The text a write just stored, when this read follows one. The draft
    ///   gives way to the record only while it still holds exactly that text: keystrokes made
    ///   *during* the write are a fresh edit and survive it, where overwriting them would drop them
    ///   silently and clear the ``hasUnsavedNotes`` that was the only sign they existed. `nil` on a
    ///   plain read, where the same question is asked of the record instead — a first read has no
    ///   draft to protect, and a ``refresh()`` has one exactly when ``hasUnsavedNotes`` says so.
    private func publishRead(confirming submitted: String? = nil) async throws {
        // Both are asked before the read: `hasUnsavedNotes` compares the draft against the record
        // this screen is currently showing, and that record is about to be replaced.
        let draftAtStart = notesDraft
        let hadUnsavedNotes = hasUnsavedNotes
        guard let exercise = try await repository.exercise(id: exerciseID, includingDeleted: false)
        else {
            phase = .missing
            return
        }
        let catalogue = try await repository.exercises(includingDeleted: false)
        phase = .loaded(
            Self.detail(for: exercise, in: catalogue, hasLoggedSets: await hasLoggedSets()))
        // A keystroke that landed while the read was in flight is a fresh edit and survives it,
        // whichever kind of read this was. Failing that, the draft gives way to the record only if
        // the two already agreed when the read began.
        let typedDuringRead = notesDraft != draftAtStart
        let keepsDraft = typedDuringRead || (submitted.map { draftAtStart != $0 } ?? hadUnsavedNotes)
        if !keepsDraft {
            notesDraft = exercise.notes
        }
    }

    /// Whether any set has ever been logged against this exercise, or `false` where the workout
    /// store could not answer.
    ///
    /// **Its own failure, and swallowed on purpose.** This read decides which of two sentences three
    /// derived sections carry, and nothing else on the screen depends on it — so taking the whole
    /// screen to its error state for it would let a workout-store fault hide the movement, equipment
    /// and notes the catalogue answered for perfectly well. The quiet wrong answer is the sentence
    /// the screen showed before this read existed, which is the smaller of the two mistakes.
    private func hasLoggedSets() async -> Bool {
        let logged = try? await workouts.sets(forExerciseID: exerciseID, includingDeleted: false)
        return !(logged?.isEmpty ?? true)
    }

    /// Pairs an exercise with its parent and its variations, from the whole catalogue.
    private static func detail(
        for exercise: Exercise,
        in catalogue: [Exercise],
        hasLoggedSets: Bool
    ) -> ExerciseDetail {
        ExerciseDetail(
            exercise: exercise,
            parent: exercise.parentExerciseID.flatMap { parentID in
                catalogue.first { $0.id == parentID }
            },
            variations:
                catalogue
                .filter { $0.parentExerciseID == exercise.id && !$0.isArchived }
                .sorted(by: ExerciseOrder.precedes),
            hasLoggedSets: hasLoggedSets
        )
    }

    /// `exercise` with `isArchived` set, and every other field untouched.
    ///
    /// Rebuilt rather than mutated, and the timestamps carried across, for the reason
    /// ``withNotes(_:on:)`` gives.
    private static func archived(_ archived: Bool, on exercise: Exercise) -> Exercise {
        Exercise(
            id: exercise.id,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt,
            name: exercise.name,
            movement: exercise.movement,
            parentExerciseID: exercise.parentExerciseID,
            equipment: exercise.equipment,
            laterality: exercise.laterality,
            barType: exercise.barType,
            implementCount: exercise.implementCount,
            isCustom: exercise.isCustom,
            isArchived: archived,
            notes: exercise.notes,
            manualE1RM: exercise.manualE1RM)
    }

    /// `exercise` with `notes` in place of its own, and every other field untouched.
    ///
    /// The record is rebuilt rather than mutated because it is a value with `let` properties — and
    /// the three timestamps are carried across because the write path is an upsert that stamps
    /// ``RepositoryInterface/StoredRecord/updatedAt`` itself and honours `createdAt` only when the
    /// row is new.
    private static func withNotes(_ notes: String, on exercise: Exercise) -> Exercise {
        Exercise(
            id: exercise.id,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt,
            name: exercise.name,
            movement: exercise.movement,
            parentExerciseID: exercise.parentExerciseID,
            equipment: exercise.equipment,
            laterality: exercise.laterality,
            barType: exercise.barType,
            implementCount: exercise.implementCount,
            isCustom: exercise.isCustom,
            isArchived: exercise.isArchived,
            notes: notes,
            manualE1RM: exercise.manualE1RM)
    }
}
