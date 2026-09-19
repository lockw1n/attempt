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

    /// The ordering, not just the call: a reader that sees ``ExerciseFormState/didSave`` must be
    /// able to rely on the selection having landed, which is the whole reason the two lines are in
    /// the order they are in.
    @Test("The save is not finished until the selection has landed")
    func theFlagFollowsTheSelection() async {
        let probe = FlagProbe()
        let state = await form(initialName: "Rear delt fly", onSave: probe.record(_:))
        probe.form = state

        await state.save()

        #expect(state.didSave)
        #expect(
            probe.flagDuringSelection == false,
            """
            didSave was already true while the selection was still running, or the selection never \
            ran at all (FR-18.1.4).
            """)
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

    /// What ``ExerciseFormState/didSave`` read as while the selection was still running.
    ///
    /// **Starts at `true`, which is the failing value**, so a selection that never ran at all fails
    /// the same assertion as one that ran too late — the probe cannot pass by doing nothing.
    @MainActor private final class FlagProbe {
        /// The form under test, set after it is built because the closure is built first.
        weak var form: ExerciseFormState?

        /// The flag as the selection saw it.
        private(set) var flagDuringSelection = true

        /// Reads the flag at the moment the picker would be writing the exercise away.
        ///
        /// - Parameter exercise: The stored row, unused — the claim is about the ordering.
        func record(_ exercise: Exercise) async {
            flagDuringSelection = form?.didSave ?? true
        }
    }

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
