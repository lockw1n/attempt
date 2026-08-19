import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.1.6`/`FR-1.1.7` as claims about *what a screen resolves and what it writes*: which
/// relationships an identifier produces, and what a notes edit does to the store. None of them
/// renders a view, which is the property `TR-1.2`'s pattern exists to buy.
///
/// The fixtures and `ScriptedExerciseRepository` are `ExerciseListStateTests`', which is also where
/// the argument for a scripted fake over the in-memory one lives.
@MainActor
@Suite("Exercise detail state")
struct ExerciseDetailStateTests {
    // MARK: - Resolving the identifier

    @Test("A load publishes the exercise the route named")
    func loadPublishesTheExercise() async {
        let state = await DetailFixtures.loaded(DetailFixtures.backSquat.id)
        #expect(state.detail?.exercise.name == "Back Squat")
    }

    @Test("An identifier that names nothing is missing, not a failed read")
    func unknownIdentifierIsMissing() async {
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.identifier("F"),
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        await state.load()
        #expect(state.phase == .missing)
    }

    @Test("A missing exercise is not read again — retrying resolves to the same absence")
    func missingIsTerminal() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.identifier("F"), repository: repository)
        await state.load()
        await state.load()
        #expect(await repository.reads == 1)
    }

    @Test("A failed read is recoverable, and the retry resolves the exercise")
    func failedReadRetries() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            readError: .recordNotFound(id: UUID())
        )
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed phase, got \(state.phase)")
            return
        }
        #expect(diagnostic.contains("recordNotFound"))
        #expect(state.detail == nil)

        await repository.recover()
        await state.load()
        #expect(state.detail?.exercise.name == "Back Squat")
    }

    @Test("Soft-deleted rows are asked for by the repository calls, not filtered afterwards")
    func deletedRowsAreNotRequested() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        #expect(await repository.readsIncludingDeleted == [false, false])
    }

    @Test("Nothing is claimed about an exercise before a read has finished")
    func nothingIsClaimedBeforeLoading() {
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id,
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        #expect(state.phase == .idle)
        #expect(state.detail == nil)
        #expect(state.hasUnsavedNotes == false)
        #expect(state.notesDraft.isEmpty)
    }

    // MARK: - Variations (FR-1.1.7)

    @Test("A parent exercise shows its variations, in reader order")
    func parentShowsItsVariations() async {
        let state = await DetailFixtures.loaded(DetailFixtures.backSquat.id)
        #expect(state.detail?.variations.map(\.name) == ["Front Squat", "Pause Squat"])
        #expect(state.detail?.parent == nil)
    }

    @Test("A variation names the exercise it varies")
    func variationNamesItsParent() async {
        let state = await DetailFixtures.loaded(DetailFixtures.frontSquat.id)
        #expect(state.detail?.parent?.name == "Back Squat")
        #expect(state.detail?.variations.isEmpty == true)
    }

    @Test("An archived variation is not listed (FR-1.1.5)")
    func archivedVariationsAreExcluded() async {
        let retired = DetailFixtures.exercise(
            name: "Anderson Squat",
            movement: .squat,
            parentExerciseID: DetailFixtures.backSquat.id,
            isArchived: true
        )
        let state = await DetailFixtures.loaded(
            DetailFixtures.backSquat.id, extra: [retired])
        #expect(state.detail?.variations.map(\.name) == ["Front Squat", "Pause Squat"])
    }

    @Test("An archived parent is still named — hiding it would assert this is a root exercise")
    func archivedParentIsStillShown() async {
        let archivedParent = DetailFixtures.exercise(
            id: DetailFixtures.identifier("9"),
            name: "Retired Machine Press",
            movement: .bench,
            isArchived: true
        )
        let child = DetailFixtures.exercise(
            id: DetailFixtures.identifier("A"),
            name: "Retired Machine Press, Wide",
            movement: .bench,
            parentExerciseID: archivedParent.id
        )
        let state = await DetailFixtures.loaded(child.id, extra: [archivedParent, child])
        #expect(state.detail?.parent?.name == "Retired Machine Press")
    }

    @Test("An exercise with neither a parent nor variations has no relationships section")
    func rootWithoutVariationsHasNoRelationships() async {
        let state = await DetailFixtures.loaded(DetailFixtures.benchPress.id)
        #expect(state.detail?.hasRelationships == false)
    }

    @Test("A parent with one variation does have a relationships section")
    func aRelationshipIsEnoughForTheSection() async {
        let state = await DetailFixtures.loaded(DetailFixtures.frontSquat.id)
        #expect(state.detail?.hasRelationships == true)
    }

    // MARK: - Notes (FR-1.1.6)

    @Test("The draft starts as what is stored")
    func draftStartsFromTheRecord() async {
        let state = await DetailFixtures.loaded(DetailFixtures.backSquat.id)
        #expect(state.notesDraft == "Belt from 140 kg.")
        #expect(state.hasUnsavedNotes == false)
    }

    @Test("Typing makes the draft unsaved; saving it reaches the store and the screen")
    func savingNotesWritesAndRepublishes() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()

        state.notesDraft = "Knees out, chest up."
        #expect(state.hasUnsavedNotes == true)

        await state.saveNotes()
        #expect(await repository.savedNotes == ["Knees out, chest up."])
        #expect(state.detail?.exercise.notes == "Knees out, chest up.")
        #expect(state.notesDraft == "Knees out, chest up.")
        #expect(state.hasUnsavedNotes == false)
        #expect(state.writeFailure == nil)
    }

    @Test("A save of the text already stored writes nothing — G-2.4's key must not be restamped")
    func unchangedNotesAreNotWritten() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        await state.saveNotes()
        #expect(await repository.savedNotes.isEmpty)
    }

    @Test("Saving changes only the notes")
    func savingLeavesEveryOtherFieldAlone() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.frontSquat.id, repository: repository)
        await state.load()
        state.notesDraft = "Front rack mobility first."
        await state.saveNotes()

        let saved = state.detail?.exercise
        #expect(saved?.name == "Front Squat")
        #expect(saved?.parentExerciseID == DetailFixtures.backSquat.id)
        #expect(saved?.isCustom == true)
        #expect(saved?.movement == .squat)
        // The parent link survived the write, which is the one that a rebuilt record can silently
        // drop — and dropping it would orphan the variation from FR-1.1.7's tree.
        #expect(state.detail?.parent?.name == "Back Squat")
    }

    @Test("A failed write costs the screen neither its exercise nor the text the user typed")
    func failedWriteKeepsTheScreen() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        state.notesDraft = "Typed and then lost?"
        await state.saveNotes()

        #expect(state.writeFailure?.contains("recordNotFound") == true)
        #expect(state.detail?.exercise.name == "Back Squat")
        #expect(state.notesDraft == "Typed and then lost?")
        #expect(state.hasUnsavedNotes == true)

        await repository.recoverWrites()
        await state.saveNotes()
        #expect(state.writeFailure == nil)
        #expect(state.detail?.exercise.notes == "Typed and then lost?")
    }

    @Test("Discarding puts the stored notes back and clears the failure with them")
    func discardingRestoresTheStoredNotes() async {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue,
            writeError: .recordNotFound(id: UUID())
        )
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        state.notesDraft = "Second thoughts."
        await state.saveNotes()
        #expect(state.writeFailure != nil)

        state.discardNoteEdits()
        #expect(state.notesDraft == "Belt from 140 kg.")
        #expect(state.hasUnsavedNotes == false)
        #expect(state.writeFailure == nil)
    }

    @Test("Nothing is unsaved on a screen that never resolved an exercise")
    func nothingIsUnsavedWithoutAnExercise() async {
        let state = ExerciseDetailState(
            exerciseID: DetailFixtures.identifier("F"),
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        )
        await state.load()
        state.notesDraft = "Typed onto a screen with no exercise."
        #expect(state.hasUnsavedNotes == false)

        await state.saveNotes()
        #expect(state.phase == .missing)
    }
}

/// The exercise under test, where the assertions above read one.
extension ExerciseDetailState {
    fileprivate var detail: ExerciseDetail? {
        guard case .loaded(let detail) = phase else { return nil }
        return detail
    }
}

/// The catalogue these tests resolve against: a parent with two variations, one unrelated exercise.
enum DetailFixtures {
    /// A root exercise with two variations and notes already on it.
    static let backSquat = exercise(
        id: identifier("1"), name: "Back Squat", movement: .squat, notes: "Belt from 140 kg.")

    /// One of its variations, and the user's own.
    static let frontSquat = exercise(
        id: identifier("2"),
        name: "Front Squat",
        movement: .squat,
        parentExerciseID: identifier("1"),
        isCustom: true
    )

    /// Its other variation. Named so that it sorts *after* `Front Squat` while being handed to the
    /// repository before it — the ordering assertion is about the state, not about the fake.
    static let pauseSquat = exercise(
        id: identifier("3"),
        name: "Pause Squat",
        movement: .squat,
        parentExerciseID: identifier("1")
    )

    /// An exercise with no relationships at all.
    static let benchPress = exercise(id: identifier("4"), name: "Bench Press", movement: .bench)

    /// **Deliberately in no order any assertion expects**, for the reason
    /// `ExerciseListStateTests.Fixtures.catalogue` gives.
    static let catalogue: [Exercise] = [pauseSquat, benchPress, frontSquat, backSquat]

    /// A state over ``catalogue``, already read.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise the route named.
    ///   - extra: Rows beyond the catalogue, for the tests that need an archived one.
    /// - Returns: The state, loaded.
    static func loaded(_ exerciseID: UUID, extra: [Exercise] = []) async -> ExerciseDetailState {
        let state = ExerciseDetailState(
            exerciseID: exerciseID,
            repository: ScriptedExerciseRepository(exercises: catalogue + extra)
        )
        await state.load()
        return state
    }

    /// An identifier ending in `suffix`, so the byte-order tiebreak is decidable from the fixture.
    static func identifier(_ suffix: String) -> UUID {
        UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-00000000000\(suffix)") ?? UUID()
    }

    /// One exercise. `ExerciseListStateTests.Fixtures.exercise` under another name, so the two
    /// suites' fixtures cannot drift.
    static func exercise(
        id: UUID = UUID(),
        name: String,
        movement: Movement,
        equipment: Equipment = .barbell,
        parentExerciseID: UUID? = nil,
        isCustom: Bool = false,
        isArchived: Bool = false,
        notes: String = ""
    ) -> Exercise {
        Fixtures.exercise(
            id: id,
            name: name,
            movement: movement,
            equipment: equipment,
            parentExerciseID: parentExerciseID,
            isCustom: isCustom,
            isArchived: isArchived,
            notes: notes
        )
    }
}
