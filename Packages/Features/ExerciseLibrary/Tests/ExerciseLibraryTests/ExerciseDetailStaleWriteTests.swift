import Foundation
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What the detail screen's two writes must not revert.
///
/// **The screen draws a subset of the row, and both commands rebuild the whole of it.** So each is
/// one stale copy away from silently writing back a column's old value from a command about
/// something else — which is what the re-read in `writeNotes(_:)` and `writeArchived(_:)` is for,
/// and what these pin. The witness is ``RepositoryInterface/Exercise/name``: `FR-1.1.4` lets it be
/// edited, the create/edit form writes it, and this screen never offers it.
///
/// A suite of its own rather than a `// MARK:` in ``ExerciseDetailStateTests``: that file had
/// reached SwiftLint's length ceiling. Same fixtures, same fake.
@MainActor
@Suite("Exercise detail stale writes")
struct ExerciseDetailStaleWriteTests {
    /// A notes save that rebuilt the record from the picture this screen loaded would put the old
    /// name back — from a command about the notes.
    @Test("A notes save keeps a rename stored since the screen read the row")
    func savingNotesKeepsARenameWrittenSinceTheRead() async throws {
        let original = DetailFixtures.exercise(
            id: DetailFixtures.identifier("7"), name: "Deadlift", movement: .deadlift)
        let repository = ScriptedExerciseRepository(exercises: [original])
        let state = DetailFixtures.state(exerciseID: original.id, repository: repository)
        await state.load()

        // The form's write, landing while this screen holds its own copy of the row.
        try await repository.save(DetailFixtures.renamed(original, to: "Sumo Deadlift"))
        state.notesDraft = "Straps from the third set."
        await state.saveNotes()

        let saved = try #require(await repository.savedRecords.last)
        #expect(saved.notes == "Straps from the third set.")
        #expect(saved.name == "Sumo Deadlift")
    }

    /// The same hazard on the other command — it rebuilds the record the same way.
    @Test("An archive keeps a rename stored since the screen read the row")
    func archivingKeepsARenameWrittenSinceTheRead() async throws {
        let original = DetailFixtures.exercise(
            id: DetailFixtures.identifier("8"), name: "Overhead Press", movement: .overheadPress)
        let repository = ScriptedExerciseRepository(exercises: [original])
        let state = DetailFixtures.state(exerciseID: original.id, repository: repository)
        await state.load()

        try await repository.save(DetailFixtures.renamed(original, to: "Behind-the-Neck Press"))
        await state.setArchived(true)

        let saved = try #require(await repository.savedRecords.last)
        #expect(saved.isArchived)
        #expect(saved.name == "Behind-the-Neck Press")
    }
}

extension DetailFixtures {
    /// `exercise` under `name` and nothing else touched — the row as the edit form leaves it, for
    /// the tests about what a second writer must not revert.
    static func renamed(_ exercise: Exercise, to name: String) -> Exercise {
        Exercise(
            id: exercise.id,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt,
            name: name,
            ukrainianName: exercise.ukrainianName,
            movement: exercise.movement,
            parentExerciseID: exercise.parentExerciseID,
            equipment: exercise.equipment,
            laterality: exercise.laterality,
            barType: exercise.barType,
            implementCount: exercise.implementCount,
            isCustom: exercise.isCustom,
            isArchived: exercise.isArchived,
            notes: exercise.notes)
    }
}
