import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// Which of an exercise's fields the form may write, and which belong to the seed catalogue
/// (`FR-1.1.4`, `TR-0.5.1`).
///
/// Its own suite because its subject is neither the read nor the write but the *line between them*:
/// the seed import is a merge that runs at every launch and re-supplies six columns on any row that
/// is not `isCustom`, so a form that offered those five would offer an edit the next cold start
/// undoes. `ExerciseFormState.catalogueOwnsFields` states the rule; these are the claims that the
/// store never sees a write crossing it.
///
/// The fixtures and `ScriptedExerciseRepository` are `ExerciseListStateTests`'.
@MainActor
@Suite("Exercise form catalogue ownership")
struct ExerciseFormCatalogueTests {
    @Test("Only a built-in exercise's fields belong to the catalogue")
    func catalogueOwnsOnlyABuiltInsFields() async {
        let creating = await FormFixtures.creating()
        #expect(creating.catalogueOwnsFields == false)

        let custom = await FormFixtures.editing(DetailFixtures.everyFieldDistinct)
        #expect(custom.catalogueOwnsFields == false)

        let builtIn = await FormFixtures.editing(DetailFixtures.backSquat)
        #expect(builtIn.catalogueOwnsFields)
    }

    @Test("A built-in's seed-owned columns never reach the store from this form (FR-1.1.4)")
    func aBuiltInsSeedOwnedColumnsAreNotWritten() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.backSquat.id), repository: repository)
        await state.load()
        // The screen renders these as facts, so nothing can set them by hand — which is exactly why
        // the assertion sets them by hand. A seed re-import re-supplies all five at the next launch,
        // so a write that carried them would be accepted, shown, and then undone with nothing said.
        state.name = "Low-bar Back Squat"
        state.movement = .deadlift
        state.equipment = .machine
        state.barType = .swiss
        state.laterality = .unilateral
        state.parentExerciseID = DetailFixtures.benchPress.id
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        #expect(saved.name == "Low-bar Back Squat")
        #expect(saved.movement == .squat)
        #expect(saved.equipment == .barbell)
        #expect(saved.barType == .standard)
        #expect(saved.laterality == .bilateral)
        #expect(saved.parentExerciseID == nil)
    }

    @Test("A custom exercise's own fields still reach the store")
    func aCustomExercisesFieldsAreStillWritten() async throws {
        let repository = ScriptedExerciseRepository(
            exercises: DetailFixtures.catalogue + [DetailFixtures.everyFieldDistinct])
        let state = ExerciseFormState(
            mode: .edit(exerciseID: DetailFixtures.everyFieldDistinct.id), repository: repository)
        await state.load()
        state.movement = .deadlift
        state.equipment = .dumbbell
        await state.save()

        let saved = try #require(await repository.savedRecords.first)
        // The seed import skips a custom row outright, so nothing here is the catalogue's to undo.
        #expect(saved.movement == .deadlift)
        #expect(saved.equipment == .dumbbell)
    }
}
