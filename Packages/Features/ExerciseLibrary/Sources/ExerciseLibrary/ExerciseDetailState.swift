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
/// did not need: **a write**. ``phase`` and ``writeFailure`` are separate properties because they
/// are separate facts — a notes save that fails leaves the exercise on screen and the draft in the
/// field, so the next attempt is another tap rather than a relaunch.
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

    /// What is in the notes field (`FR-1.1.6`).
    ///
    /// The draft, not the stored value: it is set from the record on every successful read and
    /// write, and diverges from it while the user types. ``hasUnsavedNotes`` is that divergence.
    public var notesDraft: String = ""

    /// Which exercise this screen is about.
    public let exerciseID: UUID

    private let repository: any ExerciseRepository

    /// The write chain. See ``saveNotes()``.
    private var pendingWrite: Task<Void, Never>?

    /// Builds the state over the identifier the route carried and the repository it reads through.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise to show. Not the record: a restored stack is decoded before any
    ///     store has been read, and a route holding a copy of a row would be a second source of
    ///     truth for it (`G-1.4`).
    ///   - repository: Where the exercise and the catalogue come from.
    public init(exerciseID: UUID, repository: any ExerciseRepository) {
        self.exerciseID = exerciseID
        self.repository = repository
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

    /// Commits the edited notes (`FR-1.1.6`).
    ///
    /// **Writes are serialized, for `SettingsLandingState.setDisplayUnit(_:)`'s reason**: the guard
    /// below reads ``phase``, which only moves once the write it describes has landed, so two
    /// overlapping saves would both decide against the same stale record and the second would
    /// compare the user's newest text against the value the first is in the middle of replacing.
    ///
    /// A save whose text already matches the stored notes writes nothing: every save restamps
    /// `updatedAt`, which is `G-2.4`'s conflict key, so a local no-op would outrank a real remote
    /// edit.
    public func saveNotes() async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeNotes()
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
    private func writeNotes() async {
        guard case .loaded(let detail) = phase, notesDraft != detail.exercise.notes else { return }
        do {
            try await repository.save(Self.withNotes(notesDraft, on: detail.exercise))
            // Re-read rather than publish what was handed in: the save path stamps `updatedAt`
            // itself, and the variation list is a second row's business either way.
            try await publishRead()
            writeFailure = nil
        } catch {
            writeFailure = String(describing: error)
        }
    }

    /// Reads the exercise and the catalogue and publishes the result, or `missing`.
    ///
    /// The notes draft follows the record rather than the other way round, so a save that the store
    /// altered — trimming, a concurrent edit — leaves the field showing what is actually stored.
    private func publishRead() async throws {
        guard let exercise = try await repository.exercise(id: exerciseID, includingDeleted: false)
        else {
            phase = .missing
            return
        }
        let catalogue = try await repository.exercises(includingDeleted: false)
        phase = .loaded(Self.detail(for: exercise, in: catalogue))
        notesDraft = exercise.notes
    }

    /// Pairs an exercise with its parent and its variations, from the whole catalogue.
    private static func detail(for exercise: Exercise, in catalogue: [Exercise]) -> ExerciseDetail {
        ExerciseDetail(
            exercise: exercise,
            parent: exercise.parentExerciseID.flatMap { parentID in
                catalogue.first { $0.id == parentID }
            },
            variations:
                catalogue
                .filter { $0.parentExerciseID == exercise.id && !$0.isArchived }
                .sorted(by: ExerciseOrder.precedes)
        )
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
            notes: notes
        )
    }
}
