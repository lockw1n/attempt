import Foundation
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

// `FR-18.1.2` as the list draws it. The list filters and splits by movement *before* it orders, so
// a parent the search, a filter or a movement section leaves out is simply not in the input, and
// its variation sorts among the roots by its own name. Every expectation is a literal name list.

@MainActor
@Suite("The library lists a parent before its variations (FR-18.1.2, FR-1.1.1)")
struct ExerciseListParentOrderTests {
    private static let backSquatID = UUID()

    private static let catalogue: [Exercise] = [
        Fixtures.exercise(name: "Pause Squat", movement: .squat, parentExerciseID: backSquatID),
        Fixtures.exercise(name: "Hack Squat", movement: .squat),
        Fixtures.exercise(id: backSquatID, name: "Back Squat", movement: .squat),
        Fixtures.exercise(name: "Box Squat", movement: .squat, parentExerciseID: backSquatID),
        // A custom variation filed under another movement than its parent's (`FR-1.1.1`).
        Fixtures.exercise(
            name: "Belt Squat", movement: .other, parentExerciseID: backSquatID, isCustom: true),
        Fixtures.exercise(name: "Leg Press", movement: .other),
    ]

    private func loaded() async -> ExerciseListState {
        let state = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: Self.catalogue))
        await state.load()
        return state
    }

    @Test("Within a movement, a parent leads its variations and the next root follows them")
    func parentLeadsItsSection() async {
        let state = await loaded()
        let squats = state.groups.first { $0.movement == .squat }?.exercises.map(\.name)
        #expect(squats == ["Back Squat", "Box Squat", "Pause Squat", "Hack Squat"])
    }

    @Test("A variation filed under another movement sits in that section by its own name")
    func crossMovementChildIsARootInItsSection() async {
        let state = await loaded()
        let legs = state.groups.first { $0.movement == .other }?.exercises.map(\.name)
        #expect(legs == ["Belt Squat", "Leg Press"])
    }

    @Test("A search or an archived parent that leaves the parent out puts its variations among the roots")
    func variationsWithoutTheirParent() async {
        let state = await loaded()
        state.searchText = "squat"
        state.movementFilter = .squat
        #expect(state.names == ["Back Squat", "Box Squat", "Pause Squat", "Hack Squat"])

        let archivedParent = Self.catalogue.map { exercise in
            exercise.id == Self.backSquatID
                ? Fixtures.exercise(
                    id: Self.backSquatID, name: "Back Squat", movement: .squat, isArchived: true)
                : exercise
        }
        let hidden = ExerciseListState.overCatalogue(ScriptedExerciseRepository(exercises: archivedParent))
        await hidden.load()
        let squats = hidden.groups.first { $0.movement == .squat }?.exercises.map(\.name)
        #expect(squats == ["Box Squat", "Hack Squat", "Pause Squat"])
    }
}
