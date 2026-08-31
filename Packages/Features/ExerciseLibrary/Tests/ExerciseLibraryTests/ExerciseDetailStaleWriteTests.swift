import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What the detail screen's two writes must not clear.
///
/// **The exercise row has a second writer**: `FR-1.7.5`'s manual estimate is stored by the estimate
/// section, through its own store, and this screen is never shown that column. Both commands here
/// rebuild the whole record, so each is one stale copy away from silently reverting an override
/// from a command about something else — which is what these pin.
///
/// A suite of its own rather than a `// MARK:` in ``ExerciseDetailStateTests``: that file had
/// reached SwiftLint's length ceiling. Same fixtures, same fake.
@MainActor
@Suite("Exercise detail stale writes")
struct ExerciseDetailStaleWriteTests {
    /// **This row has a second writer, and this screen is never shown the column it writes.**
    /// `FR-1.7.5`'s manual estimate is stored by the estimate section through its own store, so a
    /// notes save that rebuilt the record from the picture this screen loaded would clear an
    /// override entered since — silently, and from a command about something else entirely.
    @Test("A notes save keeps an override stored since the screen read the row")
    func savingNotesKeepsAnOverrideWrittenSinceTheRead() async throws {
        let original = DetailFixtures.exercise(
            id: DetailFixtures.identifier("7"), name: "Deadlift", movement: .deadlift)
        let repository = ScriptedExerciseRepository(exercises: [original])
        let state = DetailFixtures.state(exerciseID: original.id, repository: repository)
        await state.load()

        // The estimate section's write, landing while this screen holds its own copy of the row.
        try await repository.save(DetailFixtures.overriding(original, at: Weight(grams: 180_000)))
        state.notesDraft = "Straps from the third set."
        await state.saveNotes()

        let saved = try #require(await repository.savedRecords.last)
        #expect(saved.notes == "Straps from the third set.")
        #expect(saved.manualE1RM == Weight(grams: 180_000))
    }

    /// The same hazard on the other command — it rebuilds the record the same way.
    @Test("An archive keeps an override stored since the screen read the row")
    func archivingKeepsAnOverrideWrittenSinceTheRead() async throws {
        let original = DetailFixtures.exercise(
            id: DetailFixtures.identifier("8"), name: "Overhead Press", movement: .overheadPress)
        let repository = ScriptedExerciseRepository(exercises: [original])
        let state = DetailFixtures.state(exerciseID: original.id, repository: repository)
        await state.load()

        try await repository.save(DetailFixtures.overriding(original, at: Weight(grams: 62_500)))
        await state.setArchived(true)

        let saved = try #require(await repository.savedRecords.last)
        #expect(saved.isArchived)
        #expect(saved.manualE1RM == Weight(grams: 62_500))
    }
}

extension DetailFixtures {
    /// `exercise` carrying `weight` as `FR-1.7.5`'s override and nothing else touched — the row as
    /// the estimate section leaves it, for the tests about what a second writer must not clear.
    static func overriding(_ exercise: Exercise, at weight: Weight) -> Exercise {
        Exercise(
            id: exercise.id,
            createdAt: exercise.createdAt,
            updatedAt: exercise.updatedAt,
            deletedAt: exercise.deletedAt,
            name: exercise.name,
            ukrainianName: nil,
            movement: exercise.movement,
            parentExerciseID: exercise.parentExerciseID,
            equipment: exercise.equipment,
            laterality: exercise.laterality,
            barType: exercise.barType,
            implementCount: exercise.implementCount,
            isCustom: exercise.isCustom,
            isArchived: exercise.isArchived,
            notes: exercise.notes,
            manualE1RM: weight)
    }
}
