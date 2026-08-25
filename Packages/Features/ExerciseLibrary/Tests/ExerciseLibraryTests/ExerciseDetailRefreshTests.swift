import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What the detail screen shows when it is returned to (`FR-1.1.4`): the store may have moved under
/// it while an edit form was on top, and `load()` — which refuses to read twice — is what would
/// leave the old reading on screen.
///
/// Its own suite rather than more of `ExerciseDetailStateTests`, whose subject is one read and one
/// write; the fixtures and `ScriptedExerciseRepository` are shared.
@MainActor
@Suite("Exercise detail refresh")
struct ExerciseDetailRefreshTests {
    @Test("A refresh shows an edit made since the screen was read")
    func refreshPicksUpAnEdit() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = DetailFixtures.state(exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        #expect(state.detail?.exercise.name == "Back Squat")

        // What T-1.12's edit screen does, one screen above this one.
        try await repository.save(
            DetailFixtures.exercise(
                id: DetailFixtures.backSquat.id, name: "Low-bar Back Squat", movement: .squat))
        await state.refresh()
        #expect(state.detail?.exercise.name == "Low-bar Back Squat")
    }

    @Test("A refresh does not overwrite notes the user has typed and not saved")
    func refreshKeepsAnUnsavedDraft() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = DetailFixtures.state(exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        state.notesDraft = "Typed, not yet saved."

        await state.refresh()
        #expect(state.notesDraft == "Typed, not yet saved.")
        #expect(state.hasUnsavedNotes)
    }

    @Test("A refresh with nothing unsaved shows the notes as they are now stored")
    func refreshFollowsTheStoredNotes() async throws {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = DetailFixtures.state(exerciseID: DetailFixtures.backSquat.id, repository: repository)
        await state.load()
        #expect(state.notesDraft == "Belt from 140 kg.")

        try await repository.save(
            DetailFixtures.exercise(
                id: DetailFixtures.backSquat.id,
                name: "Back Squat",
                movement: .squat,
                notes: "Belt from 150 kg."
            )
        )
        await state.refresh()
        #expect(state.notesDraft == "Belt from 150 kg.")
        #expect(state.hasUnsavedNotes == false)
    }

    @Test("A refresh does not re-read an identifier that already resolved to nothing")
    func refreshLeavesMissingAlone() async {
        let repository = ScriptedExerciseRepository(exercises: DetailFixtures.catalogue)
        let state = DetailFixtures.state(exerciseID: DetailFixtures.identifier("F"), repository: repository)
        await state.load()
        await state.refresh()
        #expect(state.phase == .missing)
        #expect(await repository.reads == 1)
    }
}
