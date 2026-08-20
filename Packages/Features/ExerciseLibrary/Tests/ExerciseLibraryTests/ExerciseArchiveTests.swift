import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.1.5` as claims about *what reaches the store and what the screens then show*: archiving is
/// a write of one column, un-archiving is the same write back, and neither may take anything else
/// with it.
///
/// The fixtures and `ScriptedExerciseRepository` are `ExerciseListStateTests`', which is also where
/// the argument for a scripted fake over the in-memory one lives.
@MainActor
@Suite("Archive an exercise")
struct ExerciseArchiveTests {
    // MARK: - The write

    @Test("Archiving stores the row with only isArchived changed")
    func archivingWritesOneColumn() async {
        let repository = ScriptedExerciseRepository(exercises: [DetailFixtures.backSquat])
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()

        await state.setArchived(true)

        let written = await repository.savedRecords
        #expect(written.count == 1)
        // Every other field against the record as it was read, so a write that quietly dropped one
        // fails here rather than showing up as a lost note or a moved exercise three tasks later.
        #expect(written.first == DetailFixtures.archived(DetailFixtures.backSquat, true))
        #expect(state.detail?.exercise.isArchived == true)
    }

    @Test("Un-archiving is the same write back (FR-1.1.5's reverse)")
    func unarchivingRestoresTheRow() async {
        let archived = DetailFixtures.archived(DetailFixtures.backSquat, true)
        let repository = ScriptedExerciseRepository(exercises: [archived])
        let state = ExerciseDetailState(exerciseID: archived.id, repository: repository)
        await state.load()
        #expect(state.detail?.exercise.isArchived == true)

        await state.setArchived(false)

        #expect(await repository.savedRecords.map(\.isArchived) == [false])
        #expect(state.detail?.exercise.isArchived == false)
    }

    @Test("A built-in exercise archives, and stays built-in")
    func aBuiltInCanBeArchived() async {
        let repository = ScriptedExerciseRepository(exercises: [DetailFixtures.backSquat])
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()

        await state.setArchived(true)

        // `isCustom` decides whether the launch merge re-supplies the seed-owned columns; flipping
        // it here would take a built-in out of that merge for good.
        #expect(await repository.savedRecords.map(\.isCustom) == [false])
    }

    @Test("Archiving what is already archived writes nothing")
    func aNoOpArchiveDoesNotWrite() async {
        let archived = DetailFixtures.archived(DetailFixtures.backSquat, true)
        let repository = ScriptedExerciseRepository(exercises: [archived])
        let state = ExerciseDetailState(exerciseID: archived.id, repository: repository)
        await state.load()

        await state.setArchived(true)

        // Every save restamps `updatedAt`, which is `G-2.4`'s conflict key: a local no-op would
        // outrank a real remote edit.
        #expect(await repository.attemptedRecords.isEmpty)
    }

    @Test("An unsaved note is neither committed by archiving nor lost to it")
    func archivingLeavesTheDraftAlone() async {
        let repository = ScriptedExerciseRepository(exercises: [DetailFixtures.backSquat])
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        state.notesDraft = "Typed and not saved."

        await state.setArchived(true)

        #expect(await repository.savedRecords.map(\.notes) == [DetailFixtures.backSquat.notes])
        #expect(state.notesDraft == "Typed and not saved.")
        #expect(state.hasUnsavedNotes)
    }

    // MARK: - Failure

    @Test("A failed archive keeps the exercise on screen and retries")
    func aFailedArchiveIsRecoverable() async {
        let repository = ScriptedExerciseRepository(
            exercises: [DetailFixtures.backSquat],
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()

        await state.setArchived(true)

        #expect(state.archiveFailure?.contains("recordNotFound") == true)
        // Nothing was stored, so the screen still shows a live exercise and the button still asks
        // for the same direction.
        #expect(state.detail?.exercise.isArchived == false)

        await repository.recoverWrites()
        await state.setArchived(true)
        #expect(state.archiveFailure == nil)
        #expect(state.detail?.exercise.isArchived == true)
    }

    @Test("A write that lands but cannot be read back is a failed read, not a failed write")
    func aFailedReadAfterAWriteIsAReadFailure() async {
        let repository = ScriptedExerciseRepository(exercises: [DetailFixtures.backSquat])
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        await repository.failReads(.recordNotFound(id: UUID()))

        await state.setArchived(true)

        #expect(await repository.savedRecords.map(\.isArchived) == [true])
        // The archive landed; what is gone is the screen's picture of it. Reporting a failed write
        // would tell the user nothing had happened when something had.
        #expect(state.archiveFailure == nil)
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(diagnostic.contains("recordNotFound"))
    }

    @Test("Typing in the notes field does not retire a failed archive")
    func theTwoFailuresAreIndependent() async {
        let repository = ScriptedExerciseRepository(
            exercises: [DetailFixtures.backSquat],
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()

        await state.setArchived(true)
        state.notesDraft = "An unrelated edit."

        // The keystroke retires the *notes* failure, which is the write it belongs to. An archive
        // that failed is still a fact about the exercise and still has a retry on screen.
        #expect(state.writeFailure == nil)
        #expect(state.archiveFailure != nil)
    }

    // MARK: - What the list does with it (FR-1.1.5's "hidden from pickers")

    @Test("An archived exercise leaves the list, and comes back when it is shown")
    func theListHidesAndRevealsIt() async {
        let archived = Fixtures.exercise(name: "Retired Machine Press", movement: .bench, isArchived: true)
        let state = ExerciseListState(
            repository: ScriptedExerciseRepository(exercises: Fixtures.catalogue + [archived])
        )
        await state.load()
        #expect(!state.names.contains("Retired Machine Press"))

        state.showsArchived = true
        #expect(state.names.contains("Retired Machine Press"))
        #expect(state.names.count == 6)
    }

    @Test("Showing archived rows is not a filter, so clearing the filters does not hide them")
    func clearingFiltersLeavesTheArchiveControlAlone() async {
        let archived = Fixtures.exercise(name: "Retired Machine Press", movement: .bench, isArchived: true)
        let state = ExerciseListState(
            repository: ScriptedExerciseRepository(exercises: Fixtures.catalogue + [archived])
        )
        await state.load()
        state.showsArchived = true
        state.searchText = "Retired"

        state.clearFilters()

        #expect(state.showsArchived)
        #expect(state.names.contains("Retired Machine Press"))
    }

    @Test("A catalogue of nothing but archived rows is its own empty state, not an empty catalogue")
    func everythingArchivedIsItsOwnState() async {
        let rows = Fixtures.catalogue.map { DetailFixtures.archived($0, true) }
        let state = ExerciseListState(repository: ScriptedExerciseRepository(exercises: rows))
        await state.load()

        #expect(state.isEverythingArchived)
        // Not the empty-catalogue state: there is nothing to create, and the way out is the control
        // rather than the create form.
        #expect(!state.isCatalogueEmpty)
        #expect(state.groups.isEmpty)

        state.showsArchived = true
        #expect(!state.isEverythingArchived)
        #expect(state.names.count == 5)
    }

    @Test("A store with no exercises at all is the empty catalogue, not the archived state")
    func anEmptyStoreIsNotTheArchivedState() async {
        let state = ExerciseListState(repository: ScriptedExerciseRepository(exercises: []))
        await state.load()

        #expect(state.isCatalogueEmpty)
        #expect(!state.isEverythingArchived)
    }

    @Test("One live row among archived ones is neither empty state")
    func aLiveRowIsNeitherEmptyState() async {
        let rows = Fixtures.catalogue.dropFirst().map { DetailFixtures.archived($0, true) }
        let state = ExerciseListState(
            repository: ScriptedExerciseRepository(exercises: [Fixtures.catalogue[0]] + rows)
        )
        await state.load()

        #expect(!state.isEverythingArchived)
        #expect(!state.isCatalogueEmpty)
        #expect(state.names == [Fixtures.catalogue[0].name])
    }

    // MARK: - What the parent picker does with it (FR-1.1.7's picker is one of FR-1.1.5's)

    @Test("Un-archiving returns an exercise to the parent picker")
    func theParentPickerFollowsTheColumn() async {
        let candidate = Fixtures.exercise(name: "Box Squat", movement: .squat, isArchived: true)
        let subject = Fixtures.exercise(name: "Back Squat", movement: .squat)
        let repository = ScriptedExerciseRepository(exercises: [candidate, subject])
        let archivedForm = ExerciseFormState(mode: .edit(exerciseID: subject.id), repository: repository)
        await archivedForm.load()
        #expect(!archivedForm.parentCandidates.map(\.name).contains("Box Squat"))

        try? await repository.save(DetailFixtures.archived(candidate, false))
        let liveForm = ExerciseFormState(mode: .edit(exerciseID: subject.id), repository: repository)
        await liveForm.load()
        #expect(liveForm.parentCandidates.map(\.name).contains("Box Squat"))
    }
}

extension DetailFixtures {
    /// `exercise` with `isArchived` set and nothing else touched — the record the write is expected
    /// to produce, and the fixture the archived cases start from.
    static func archived(_ exercise: Exercise, _ isArchived: Bool) -> Exercise {
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
            isArchived: isArchived,
            notes: exercise.notes
        )
    }
}
