import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Routines

/// A catalogue exercise a routine can prescribe.
func routineExerciseFixture(name: String) -> Exercise {
    Exercise(
        id: UUID(),
        createdAt: .now,
        updatedAt: .now,
        deletedAt: nil,
        name: name,
        ukrainianName: nil,
        movement: .squat,
        parentExerciseID: nil,
        equipment: .barbell,
        laterality: .bilateral,
        barType: .standard,
        implementCount: 1,
        isCustom: true,
        isArchived: false,
        notes: "",
        manualE1RM: nil)
}

/// A stack whose catalogue already holds `exercises`, since a routine slot the repository will
/// accept has to name a row that exists.
func seededStack(_ exercises: [Exercise]) async throws -> InMemoryRepositoryStack {
    let stack = InMemoryRepositoryStack()
    for exercise in exercises {
        try await stack.exercises.save(exercise)
    }
    return stack
}

/// An editor over `stack`, in the locale and unit every test here uses.
///
/// **`en_US_POSIX` and kilograms deliberately**: the draft parses in a locale, so a test that took
/// the machine's own would pass or fail on where it ran.
@MainActor
func editor(over stack: InMemoryRepositoryStack) -> RoutineEditorState {
    let state = RoutineEditorState(
        repository: stack.routines, catalogue: stack.exercises, settings: stack.settings)
    state.locale = Locale(identifier: "en_US_POSIX")
    return state
}
