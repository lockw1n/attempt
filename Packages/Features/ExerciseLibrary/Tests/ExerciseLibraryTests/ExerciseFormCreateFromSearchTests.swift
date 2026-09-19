import Foundation
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-18.1.3`/`FR-18.1.4` as claims about the form: what a prefilled name opens on, and what a
/// successful save hands back.
///
/// Its own file rather than a section of `ExerciseFormStateTests`, whose suite is at SwiftLint's
/// type-body ceiling. The fixtures are `ExerciseListStateTests`'.
@MainActor
@Suite("Creating from a search that matched nothing")
struct ExerciseFormCreateFromSearchTests {
    // MARK: - The prefill (FR-18.1.3)

    @Test("The typed name opens the form, in English")
    func prefillsTheEnglishName() async {
        let state = await form(initialName: "Rear delt fly")

        #expect(state.name == "Rear delt fly")
        #expect(state.ukrainianName.isEmpty)
        #expect(state.canSave)
    }

    /// Both fields, because ``ExerciseFormState/name`` is the one the save requires: a Ukrainian
    /// prefill that filled only the Ukrainian field would open a form whose Save is refused.
    @Test("A Ukrainian prefill fills both names, so the save is available")
    func prefillsBothNamesInUkrainian() async {
        let state = await form(initialName: "Задня дельта в тренажері", language: .ukrainian)

        #expect(state.name == "Задня дельта в тренажері")
        #expect(state.ukrainianName == "Задня дельта в тренажері")
        #expect(state.canSave)
    }

    @Test("No prefill leaves the form empty, and its save refused")
    func noPrefillLeavesTheFormEmpty() async {
        let state = await form(initialName: "")

        #expect(state.name.isEmpty)
        #expect(state.ukrainianName.isEmpty)
        #expect(state.canSave == false)
    }

    /// The prefill is `create`'s alone: an edit has a record, and `load()` populates from it.
    @Test("An edit form ignores a prefill and keeps the record's name")
    func editIgnoresThePrefill() async {
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id),
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue),
            initialName: "Rear delt fly"
        )
        await state.load()

        #expect(state.name == "Back Squat")
    }

    // MARK: - The selection (FR-18.1.4)

    @Test("Saving hands the stored row to the picker, once")
    func saveSelectsTheStoredRow() async throws {
        let selected = Selection()
        let state = await form(initialName: "Rear delt fly", onSave: selected.record(_:))

        await state.save()

        #expect(state.didSave)
        #expect(selected.exercises.count == 1)
        let chosen = try #require(selected.exercises.first)
        #expect(chosen.name == "Rear delt fly")
        #expect(chosen.isCustom)
        #expect(state.dismissesItselfOnSave == false)
    }

    @Test("A save that failed selects nothing")
    func failedSaveSelectsNothing() async {
        let selected = Selection()
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(
                exercises: DetailFixtures.catalogue,
                writeError: .recordNotFound(id: DetailFixtures.backSquat.id)),
            initialName: "Rear delt fly",
            onSave: selected.record(_:)
        )
        await state.load()

        await state.save()

        #expect(state.didSave == false)
        #expect(selected.exercises.isEmpty)
    }

    /// The browsing screen's form: nothing to select, and the form owns its own exit.
    @Test("Without a picker, a save selects nothing and the form leaves on its own")
    func browsingSaveSelectsNothing() async {
        let state = await form(initialName: "Rear delt fly")

        await state.save()

        #expect(state.didSave)
        #expect(state.dismissesItselfOnSave)
    }

    // MARK: - Fixtures

    /// What the picker did with the saved row.
    ///
    /// A class, because the closure is handed to the form before the assertions read it back.
    @MainActor private final class Selection {
        private(set) var exercises: [Exercise] = []

        func record(_ exercise: Exercise) async {
            exercises.append(exercise)
        }
    }

    /// A create form over the fixture catalogue, already read.
    ///
    /// - Parameters:
    ///   - initialName: What the search had in it.
    ///   - language: The active name language, handed over as the view hands it over — before the
    ///     read, which is what decides which field the prefill reaches.
    ///   - onSave: The picker's selection, or nothing.
    /// - Returns: The form, ready.
    private func form(
        initialName: String,
        language: ExerciseNameLanguage = .english,
        onSave: ((Exercise) async -> Void)? = nil
    ) async -> ExerciseFormState {
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(exercises: DetailFixtures.catalogue),
            initialName: initialName,
            onSave: onSave
        )
        state.nameLanguage = language
        await state.load()
        return state
    }
}
