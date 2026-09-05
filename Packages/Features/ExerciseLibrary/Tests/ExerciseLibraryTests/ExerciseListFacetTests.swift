import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// `FR-16.5.4`: the facets fold behind one row, the row says what is in force, and the list opens on
/// **Recently used** once the log has history — remembered for the rest of the launch.
@MainActor
@Suite("Exercise list facets")
struct ExerciseListFacetTests {
    @Test("A list with history opens on Recently used")
    func alistWithHistoryOpensOnRecentlyUsed() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 3)

        let state = gym.listState()
        await state.load()

        #expect(state.showsRecentOnly == true)
        #expect(state.activeFacets == [.recentlyUsed])
    }

    /// The other half of the same rule, and the one that has to hold on a fresh install: there is no
    /// recency to narrow to, so narrowing to it would empty the screen behind a disabled chip.
    @Test("A list with no history opens on everything")
    func alistWithNoHistoryOpensOnEverything() async throws {
        let gym = try await Gym.seeded()

        let state = gym.listState()
        await state.load()

        #expect(state.showsRecentOnly == false)
        #expect(state.activeFacets.isEmpty)
    }

    @Test("The facets the lifter chose are what the list reopens on, not the default")
    func thefacetsChosenAreWhatItReopensOn() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 3)
        let memory = ExerciseListFilterMemory()

        let first = gym.listState(memory: memory)
        await first.load()
        first.showsRecentOnly = false
        first.movementFilter = .bench

        let second = gym.listState(memory: memory)
        await second.load()

        #expect(second.showsRecentOnly == false)
        #expect(second.movementFilter == .bench)
    }

    /// The distinction the memory's optional exists for: "cleared every facet" and "never chose" are
    /// the same four values and different intentions, and only the second gets the default.
    @Test("Clearing every facet is a choice, not a return to never having chosen")
    func clearingEveryFacetIsAChoice() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 3)
        let memory = ExerciseListFilterMemory()

        let first = gym.listState(memory: memory)
        await first.load()
        first.clearFilters()

        let second = gym.listState(memory: memory)
        await second.load()

        #expect(second.showsRecentOnly == false)
    }

    /// The window moves on while the app runs, so a remembered narrowing can outlive the history
    /// behind it — and a filter in force under a disabled chip is one nothing on screen clears.
    @Test("A remembered recency filter is dropped where the history no longer supports it")
    func arememberedRecencyFilterIsDroppedWithoutHistory() async throws {
        let trained = try await Gym.seeded()
        try await trained.train(trained.squat, daysAgo: 3)
        let memory = ExerciseListFilterMemory()

        let first = trained.listState(memory: memory)
        await first.load()
        first.showsRecentOnly = true

        let fresh = try await Gym.seeded()
        let second = fresh.listState(memory: memory)
        await second.load()

        #expect(second.isRecencyFilterAvailable == false)
        #expect(second.showsRecentOnly == false)
        #expect(second.names.count == 3)
    }

    @Test("The folded row lists every narrowing in force, in the filter rows' own order")
    func thefoldedRowListsEveryNarrowing() async throws {
        let gym = try await Gym.seeded()
        let state = gym.listState()
        await state.load()

        state.movementFilter = .bench
        state.equipmentFilter = .barbell
        state.originFilter = .custom
        state.showsArchived = true

        #expect(
            state.activeFacets == [
                .movement(.bench), .equipment(.barbell), .origin(.custom), .archived,
            ])
    }

    @Test("Tapping a chip clears its own facet and leaves the others alone")
    func tappingachipClearsItsOwnFacet() async throws {
        let gym = try await Gym.seeded()
        let state = gym.listState()
        await state.load()
        state.movementFilter = .bench
        state.equipmentFilter = .barbell

        state.clear(.movement(.bench))

        #expect(state.movementFilter == nil)
        #expect(state.equipmentFilter == .barbell)
        #expect(state.activeFacets == [.equipment(.barbell)])
    }

    /// `showsArchived` widens where the four narrow, so it is on the row and not among the filters —
    /// clearing them must not hide rows the lifter just asked to see.
    @Test("Clearing the filters leaves the archived control alone")
    func clearingthefiltersLeavesArchivedAlone() async throws {
        let gym = try await Gym.seeded()
        let state = gym.listState()
        await state.load()
        state.showsArchived = true
        state.movementFilter = .bench

        state.clearFilters()

        #expect(state.showsArchived == true)
        #expect(state.activeFacets == [.archived])
    }

    /// A screen returned to after a create or an edit re-reads (`FR-1.1.3`), and a refresh that
    /// re-applied the opening rule would drop the lifter's filter every time they came back.
    @Test("A refresh does not re-apply the opening default")
    func arefreshDoesNotReapplyTheDefault() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 3)

        let state = gym.listState()
        await state.load()
        state.showsRecentOnly = false
        await state.refresh()

        #expect(state.showsRecentOnly == false)
    }
}
