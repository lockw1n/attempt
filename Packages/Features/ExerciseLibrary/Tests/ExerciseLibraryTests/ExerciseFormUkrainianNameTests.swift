import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-1.14.2` as claims about what the form does with the second name: where it opens, what it
/// stores, and that a built-in exercise may carry one. Its own file rather than a section of
/// `ExerciseFormStateTests`, whose suite is at SwiftLint's type-body ceiling.
@MainActor
@Suite("The exercise form's Ukrainian name (FR-1.14.2)")
struct ExerciseFormUkrainianNameTests {
    @Test("A create form opens with no Ukrainian name")
    func createOpensWithNoUkrainianName() async {
        let state = await FormFixtures.creating()

        #expect(state.ukrainianName.isEmpty)
        #expect(state.trimmedUkrainianName == nil)
    }

    @Test("An edit form opens on the record's Ukrainian name, or on nothing")
    func editOpensOnTheStoredUkrainianName() async {
        let translated = DetailFixtures.exercise(
            id: DetailFixtures.identifier("9"),
            name: "Back Squat",
            ukrainianName: "Присідання",
            movement: .squat)

        #expect(await FormFixtures.editing(translated).ukrainianName == "Присідання")
        #expect(await FormFixtures.editing(DetailFixtures.backSquat).ukrainianName.isEmpty)
    }

    @Test("A created exercise carries the Ukrainian name, trimmed")
    func createStoresTheUkrainianName() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        state.ukrainianName = "  Присідання в тренажері  "
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.ukrainianName == "Присідання в тренажері")
        #expect(saved.name == "Belt Squat")
    }

    // Blank collapses to absent rather than to `""`, which is what keeps "never translated" and
    // "translated to nothing" one stored value instead of two that render alike.
    @Test("A blank Ukrainian name is stored as none at all")
    func blankUkrainianNameIsStoredAsNone() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(mode: .create, repository: repository)
        await state.load()
        state.name = "Belt Squat"
        state.ukrainianName = "   "
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.ukrainianName == nil)
        #expect(saved.name == "Belt Squat", "the record was written")
    }

    // The one field below the name that a *built-in* exercise may still change. The seed merge
    // fills this column rather than re-supplying it, so unlike the five `catalogueOwnsFields`
    // withholds, an edit here is not undone by the next import.
    @Test("A built-in exercise's Ukrainian name is editable and reaches the store")
    func aBuiltInTakesAUkrainianName() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id), repository: repository)
        await state.load()
        #expect(state.catalogueOwnsFields, "the fixture is not a built-in")
        state.ukrainianName = "Присідання"
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.ukrainianName == "Присідання")
        #expect(saved.isCustom == false)
        #expect(saved.movement == DetailFixtures.backSquat.movement, "the owned fields are still the catalogue's")
    }

    // Clearing has to reach the store as `nil`, or a Ukrainian name could be added and never
    // removed — the direction a `??` in the mapping layer would swallow.
    @Test("Clearing a stored Ukrainian name stores none")
    func clearingTheUkrainianNameReachesTheStore() async throws {
        let translated = DetailFixtures.exercise(
            id: DetailFixtures.identifier("9"),
            name: "Back Squat",
            ukrainianName: "Присідання",
            movement: .squat,
            isCustom: true)
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue + [translated])
        let state = ExerciseFormState(mode: .edit(exerciseID: translated.id), repository: repository)
        await state.load()
        #expect(state.ukrainianName == "Присідання")
        state.ukrainianName = ""
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.ukrainianName == nil)
        #expect(saved.name == "Back Squat")
    }
}
