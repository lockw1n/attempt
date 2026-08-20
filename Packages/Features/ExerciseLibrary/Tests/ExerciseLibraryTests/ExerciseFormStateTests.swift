import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.1.3`/`FR-1.1.4` as claims about *what reaches the store*: which record a form produces,
/// which fields it may not touch, and which exercises it will offer as a parent. None of them
/// renders a view, which is the property `TR-1.2`'s pattern exists to buy.
///
/// The fixtures and `ScriptedExerciseRepository` are `ExerciseListStateTests`'. Two tests here use
/// `RepositoryFakes` instead, and say why at the point of use: they are the two that assert
/// something about the *store's* behaviour rather than the form's.
@MainActor
@Suite("Exercise form state")
struct ExerciseFormStateTests {
    // MARK: - Reading

    @Test("A create form opens on the schema's defaults, with no name")
    func createOpensOnSchemaDefaults() async {
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        await state.load()
        #expect(state.phase == .ready)
        #expect(state.name.isEmpty)
        #expect(state.movement == .other)
        #expect(state.equipment == .other)
        #expect(state.barType == .other)
        #expect(state.laterality == .bilateral)
        #expect(state.parentExerciseID == nil)
    }

    @Test("An edit form opens on the record's own fields")
    func editOpensOnTheRecord() async {
        let state = await FormFixtures.editing(DetailFixtures.everyFieldDistinct)
        #expect(state.phase == .ready)
        #expect(state.name == "Anderson Squat")
        #expect(state.movement == .squat)
        #expect(state.equipment == .machine)
        #expect(state.barType == .swiss)
        #expect(state.laterality == .alternating)
        #expect(state.parentExerciseID == DetailFixtures.backSquat.id)
    }

    @Test("An identifier that names nothing is missing, not a failed read")
    func unknownIdentifierIsMissing() async {
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.identifier("F")),
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        await state.load()
        #expect(state.phase == .missing)
        #expect(state.canSave == false)
    }

    @Test("A failed read is recoverable, and the retry populates the form")
    func failedReadRetries() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            readError: .recordNotFound(id: UUID())
        )
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id), repository: repository)
        await state.load()
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(diagnostic.contains("recordNotFound"))
        #expect(state.name.isEmpty)

        await repository.recover()
        await state.load()
        #expect(state.name == "Back Squat")
    }

    @Test("A second read never lands on a form the user has already typed into")
    func readyFormIsNotRepopulated() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id), repository: repository)
        await state.load()
        state.name = "Back Squat, high bar"
        state.equipment = .machine

        // SwiftUI re-runs `.task` whenever the view's identity is re-established. On a read-only
        // screen that is a wasted read; here it would be the user's edits reverting under them.
        await state.load()
        #expect(state.name == "Back Squat, high bar")
        #expect(state.equipment == .machine)
        #expect(await repository.reads == 2)
    }

    // MARK: - Validation

    @Test("A name is required, and whitespace is not a name", arguments: ["", " ", "\n  \t "])
    func nameIsRequired(typed: String) async {
        let state = await FormFixtures.creating()
        state.name = typed
        #expect(state.isNameValid == false)
        #expect(state.canSave == false)
    }

    @Test("Nothing else blocks the save — every other field has a default")
    func onlyTheNameBlocksTheSave() async {
        let state = await FormFixtures.creating()
        state.name = "Belt Squat"
        #expect(state.canSave)
    }

    @Test("A save the form refuses writes nothing")
    func refusedSaveWritesNothing() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        await state.save()
        #expect(await repository.savedRecords.isEmpty)
        #expect(state.didSave == false)
    }

    @Test("A form that never read anything cannot save, even with a name")
    func unreadFormCannotSave() {
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        state.name = "Belt Squat"
        #expect(state.canSave == false)
    }

    // MARK: - Creating (FR-1.1.3)

    @Test("A created exercise carries the chosen fields and the flags FR-1.1.3 implies")
    func createStoresTheChosenFields() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        state.movement = .squat
        state.equipment = .machine
        state.barType = .noBar
        state.laterality = .unilateral
        state.parentExerciseID = DetailFixtures.backSquat.id
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.name == "Belt Squat")
        #expect(saved.movement == .squat)
        #expect(saved.equipment == .machine)
        #expect(saved.barType == .noBar)
        #expect(saved.laterality == .unilateral)
        #expect(saved.parentExerciseID == DetailFixtures.backSquat.id)
        // The three the form does not ask about. `isCustom` is what stops a seed re-import from
        // overwriting the row; the notes belong to the detail screen's editor; the implement count
        // is the schema's own default and a factor in tonnage.
        #expect(saved.isCustom == true)
        #expect(saved.isArchived == false)
        #expect(saved.notes.isEmpty)
        #expect(saved.implementCount == 1)
        #expect(state.didSave)
    }

    @Test("The stored name is trimmed, so a stray space is not part of it")
    func nameIsTrimmed() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "  Belt Squat "
        await state.save()
        #expect(await repository.savedRecords.map(\.name) == ["Belt Squat"])
    }

    @Test("Retrying a failed create upserts the same row rather than forking a second one")
    func retriedCreateKeepsItsIdentifier() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        await state.save()
        #expect(state.writeFailure?.contains("recordNotFound") == true)
        #expect(state.didSave == false)
        // The form is still there, and so is what was typed into it.
        #expect(state.name == "Belt Squat")

        await repository.recoverWrites()
        await state.save()
        // Two attempts, one row: an identifier minted per save would fork the exercise the moment a
        // write that had actually landed reported a failure.
        let attempts = await repository.attemptedRecords
        #expect(attempts.count == 2)
        #expect(Set(attempts.map(\.id)).count == 1)
        #expect(state.didSave)
    }

    @Test("Editing a field retires the banner the last failed save left behind")
    func editingClearsTheWriteFailure() async {
        let state = await FormFixtures.creating(
            writeError: .recordNotFound(id: UUID()))
        state.name = "Belt Squat"
        await state.save()
        #expect(state.writeFailure != nil)

        state.equipment = .machine
        #expect(state.writeFailure == nil)
    }

    @Test("Rewriting a field with the value it already has leaves the banner alone")
    func unchangedFieldKeepsTheWriteFailure() async {
        let state = await FormFixtures.creating(
            writeError: .recordNotFound(id: UUID()))
        state.name = "Belt Squat"
        await state.save()
        #expect(state.writeFailure != nil)

        // A binding rewriting the same value is not an edit, and the banner describes an attempt
        // that is still the last one made.
        state.name = "Belt Squat"
        #expect(state.writeFailure != nil)
    }

    @Test("A save already in flight refuses the second tap")
    func overlappingSavesAreRefused() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"

        async let first: Void = state.save()
        async let second: Void = state.save()
        _ = await (first, second)
        #expect(await repository.savedRecords.count == 1)
    }

    @Test("A created exercise is in the list the next time it reads (FR-1.1.3)")
    func createdExerciseReachesTheList() async throws {
        // `RepositoryFakes` rather than the scripted fake: the claim is that the *store* now holds a
        // row the list's own read returns, and a fake that returns what a test handed it could not
        // fail this.
        let repository = InMemoryRepositoryStack().exercises
        let form = ExerciseFormState(mode: .create, repository: repository)
        await form.load()
        form.name = "Belt Squat"
        form.movement = .squat
        await form.save()
        #expect(form.didSave)

        let list = ExerciseListState(repository: repository)
        await list.load()
        #expect(list.groups.flatMap { $0.exercises.map(\.name) } == ["Belt Squat"])
    }

    // MARK: - Editing (FR-1.1.4)

    @Test("An edit replaces the fields the form exposes and carries every other one across")
    func editPreservesTheFieldsItDoesNotShow() async throws {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue + [DetailFixtures.everyFieldDistinct])
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.everyFieldDistinct.id), repository: repository)
        await state.load()
        state.name = "Anderson Squat, low pins"
        state.equipment = .barbell
        state.laterality = .bilateral
        state.barType = .standard
        state.parentExerciseID = nil
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.name == "Anderson Squat, low pins")
        #expect(saved.equipment == .barbell)
        #expect(saved.parentExerciseID == nil)
        // Not on the form, and not lost by it: the notes are the detail screen's editor's
        // (`FR-1.1.6`), the archive flag is T-1.13's (`FR-1.1.5`), and the rest is the row's own
        // identity and audit trail.
        #expect(saved.id == DetailFixtures.everyFieldDistinct.id)
        #expect(saved.notes == "Pins at the sticking point.")
        #expect(saved.isArchived == true)
        #expect(saved.isCustom == true)
        #expect(saved.implementCount == 2)
        #expect(saved.createdAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test("Renaming a built-in exercise keeps it built-in")
    func renameDoesNotMakeAnExerciseCustom() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id), repository: repository)
        await state.load()
        state.name = "Squat"
        await state.save()
        #expect(await repository.savedRecords.map(\.isCustom) == [false])
    }

    @Test("A successful save retires the banner the attempt before it left behind")
    func successRetiresTheWriteFailure() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        await state.save()
        #expect(state.writeFailure != nil)

        // The retry is another tap and not another edit, so nothing else clears it.
        await repository.recoverWrites()
        await state.save()
        #expect(state.writeFailure == nil)
    }

    @Test("A second save upserts the row the first one wrote rather than re-minting it")
    func aSecondSaveKeepsTheRowItAlreadyWrote() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        await state.save()
        state.name = "Belt Squat, high"
        await state.save()

        // The screen dismisses on the first success, so this is a race rather than a flow — but a
        // second write that minted a fresh `createdAt` would age the row backwards, and `createdAt`
        // is not a column a later write can put right.
        let written = await repository.savedRecords
        #expect(written.count == 2)
        #expect(Set(written.map(\.id)).count == 1)
        #expect(written.map(\.createdAt) == [written[0].createdAt, written[0].createdAt])
        #expect(written.map(\.name) == ["Belt Squat", "Belt Squat, high"])
    }

    @Test("Renaming a built-in exercise does not break the sets logged against it (FR-1.1.4)")
    func renameKeepsLoggedHistory() async throws {
        // `RepositoryFakes` again, and for the same reason: this asserts that the *store* resolves a
        // logged set to the same exercise after a rename. It is structural — every set hangs off
        // `Exercise.id` and the write path upserts on that id — and this is what pins it.
        let stack = InMemoryRepositoryStack()
        let squat = DetailFixtures.exercise(
            id: DetailFixtures.identifier("1"), name: "Back Squat", movement: .squat)
        try await stack.exercises.save(squat)
        try await FormFixtures.logASet(against: squat.id, in: stack)

        let form = ExerciseFormState(mode: .edit(exerciseID: squat.id), repository: stack.exercises)
        await form.load()
        form.name = "Low-bar Back Squat"
        await form.save()
        #expect(form.didSave)

        // The set is still there, still against this exercise, and the exercise is the renamed one.
        let logged = try await stack.workouts.sets(forExerciseID: squat.id, includingDeleted: false)
        #expect(logged.count == 1)
        #expect(logged.first?.reps == 5)
        let renamed = try await stack.exercises.exercise(id: squat.id, includingDeleted: false)
        #expect(renamed?.name == "Low-bar Back Squat")
        #expect(renamed?.isCustom == false)
    }

}
