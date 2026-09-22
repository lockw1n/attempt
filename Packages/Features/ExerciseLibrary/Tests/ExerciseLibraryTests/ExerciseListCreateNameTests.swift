import Testing

@testable import ExerciseLibrary

/// `FR-18.1.3`'s first half as a claim about the state: whether the no-match state has a name to
/// offer creating, and what that name is.
///
/// The fixtures are `ExerciseListStateTests`'; its own file rather than a section of that suite,
/// which is at SwiftLint's type-body ceiling.
@MainActor
@Suite("The name Create offers (FR-18.1.3)")
struct ExerciseListCreateNameTests {
    @Test("What was typed is what would be created")
    func offersTheTypedName() async {
        let state = await listing(searchFor: "rear delt fly")

        #expect(state.nameToCreate == "rear delt fly")
    }

    /// A no-match the filters caused has no name in it, and Clear filters is the whole answer.
    @Test("Filters alone offer nothing to create")
    func filtersAloneOfferNothing() async {
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(exercises: DetailFixtures.catalogue))
        await state.load()
        state.movementFilter = .deadlift
        state.equipmentFilter = .machine

        #expect(state.groups.isEmpty)
        #expect(state.nameToCreate == nil)
    }

    @Test("A field holding only whitespace is not a name")
    func whitespaceIsNotAName() async {
        #expect(await listing(searchFor: "   ").nameToCreate == nil)
        #expect(await listing(searchFor: "").nameToCreate == nil)
    }

    @Test("The name is trimmed and its inner whitespace collapsed")
    func normalisesWhatWasTyped() async {
        let state = await listing(searchFor: "  задня   дельта \n в тренажері ")

        #expect(state.nameToCreate == "задня дельта в тренажері")
    }

    /// A list state over the fixture catalogue, read, searching for `query`.
    ///
    /// - Parameter query: What was typed into the search field.
    /// - Returns: The state.
    private func listing(searchFor query: String) async -> ExerciseListState {
        let state = ExerciseListState.overCatalogue(
            ScriptedExerciseRepository(exercises: DetailFixtures.catalogue))
        await state.load()
        state.searchText = query
        return state
    }
}
