import DerivedValues
import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.1`: which exercises are tiled, what each tile says, and what happens when the selection
/// names something that is no longer there.
@MainActor
@Suite("Dashboard estimated-max tiles")
struct EstimatedMaxTilesStateTests {
    @Test("With nothing stored, the tiles are the three competition lifts, in the requirement's order")
    func theDefaultIsTheThreeCompetitionLifts() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        let deadlift = try await fixture.exercise(named: "Deadlift", movement: .deadlift)
        try await fixture.exercise(named: "Leg Press", movement: .squat, equipment: .machine)

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.selection == [squat, bench, deadlift])
        #expect(state.isConfigured == false)
    }

    @Test("A stored selection is drawn in the order it was stored")
    func astoredSelectionKeepsItsOrder() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let press = try await fixture.exercise(named: "Overhead Press", movement: .overheadPress)
        try await fixture.tile([press, squat])

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.tiles.map(\.exerciseID) == [press, squat])
        #expect(state.tiles.map(\.name) == ["Overhead Press", "Back Squat"])
        #expect(state.isConfigured)
    }

    /// `G-2.5` forbids the constraint that would stop a tiled exercise being deleted, so the
    /// dangling identifier has to be survivable rather than impossible.
    @Test("An identifier the catalogue cannot resolve is dropped, not drawn empty")
    func adanglingIdentifierIsDropped() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.tile([squat, UUID()])

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.tiles.map(\.exerciseID) == [squat])
        #expect(state.selection.count == 2)
    }

    @Test("A tile carries the estimate and what it moved from")
    func atileCarriesTheEstimateAndItsDelta() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.session(
            on: weeksAgo(4), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 110_000, reps: 5)])])
        try await fixture.tile([squat])

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.tiles.first?.estimate.record?.weight == Weight(grams: 128_333))
        #expect(state.tiles.first?.estimate.delta == Weight(grams: 11_666))
    }

    /// `FR-1.13.3`: the tile that has no number says why, and the reason is the calculator's own
    /// rather than one this screen re-derived.
    @Test("A tile with no estimate carries the refusal that produced it")
    func atileWithNoEstimateCarriesItsRefusal() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 12)])])
        try await fixture.tile([squat])

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.tiles.first?.estimate.absence == .refused(.repsOutOfRange))
    }

    /// **Driven through the picker, which is the only thing that writes this column.** The tiles
    /// state reads the selection and never stores one, so a test that wrote it directly would be
    /// proving a path the app does not have.
    @Test("A tile removed in the picker is gone from the dashboard on the next read")
    func atileRemovedInThePickerIsGone() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        let picker = TiledExerciseSelectionState(
            catalogue: fixture.repositories.exercises, settings: fixture.repositories.settings)
        await picker.load()

        await picker.toggle(squat)

        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == [bench])
        let state = tiles(over: fixture)
        await state.load()
        #expect(state.selection == [bench])
        #expect(state.tiles.map(\.exerciseID) == [bench])
    }

    /// The one case the column's optionality exists for: "no tiles" is a choice, and it has to
    /// survive a relaunch instead of handing the three defaults back.
    @Test("An empty selection is a choice rather than never having chosen")
    func anemptySelectionIsAChoice() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let picker = TiledExerciseSelectionState(
            catalogue: fixture.repositories.exercises, settings: fixture.repositories.settings)
        await picker.load()

        await picker.toggle(squat)

        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == [])

        // The relaunch: a fresh state over the same store reads a choice, not an absence — the
        // empty state rather than the three defaults handed back.
        let relaunched = tiles(over: fixture)
        await relaunched.load()
        #expect(relaunched.tiles.isEmpty)
        #expect(relaunched.selection.isEmpty)
        #expect(relaunched.isConfigured)
        #expect(EstimatedMaxTilesScreenState.current(relaunched) == .noneTiled)
    }

    @Test("The unit the loads are drawn in is the stored one")
    func theUnitIsTheStoredOne() async throws {
        let fixture = DashboardFixture()
        let stored = try await fixture.repositories.settings.settings()
        try await fixture.repositories.settings.save(
            UserSettings(
                id: stored.id,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                deletedAt: nil,
                userID: stored.userID,
                displayUnit: .pounds,
                e1RMFormula: stored.e1RMFormula,
                theme: stored.theme,
                defaultRoundingIncrement: stored.defaultRoundingIncrement,
                defaultRoundingStrategy: stored.defaultRoundingStrategy,
                // Carried rather than defaulted away: rebuilding a row by hand is the stale-write
                // shape `UserSettings.tiling(_:)` exists to keep out of the app, and a fixture is
                // not exempt from it.
                dashboardExerciseIDs: stored.dashboardExerciseIDs))

        let state = tiles(over: fixture)
        await state.load()

        #expect(state.unit == .pounds)
    }

    // MARK: - The section's four states

    @Test("A failed read outranks the tiles it leaves behind")
    func afailedReadOutranksStaleTiles() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.tile([squat])
        let state = tiles(over: fixture)
        await state.load()
        #expect(EstimatedMaxTilesScreenState.current(state) == .ready(state.tiles))

        // The same state after a read that failed still holds the tiles; the diagnostic wins.
        let failed = tiles(over: DashboardFixture(), failing: true)
        await failed.load()
        #expect(EstimatedMaxTilesScreenState.current(failed) == .failed)
    }

    @Test("Nothing tiled is the empty state, not a blank band")
    func nothingTiledIsTheEmptyState() async throws {
        let fixture = DashboardFixture()
        let state = tiles(over: fixture)
        await state.load()

        #expect(EstimatedMaxTilesScreenState.current(state) == .noneTiled)
    }

    @Test("Before the first read the section is loading")
    func beforeTheFirstReadTheSectionIsLoading() {
        #expect(EstimatedMaxTilesScreenState.current(tiles(over: DashboardFixture())) == .loading)
    }

    /// The function reads the arithmetic, though only ``DesignSystem/DeltaDirection/increase`` is
    /// reachable from the pipeline above — see ``EstimatedMaxTileView/direction(of:)``, and
    /// ``DerivedValues/EstimatedMax/delta`` for why.
    @Test("The delta's direction follows the arithmetic, zero and negative included")
    func thedeltaDirectionFollowsTheArithmetic() {
        #expect(EstimatedMaxTileView.direction(of: Weight(grams: 500)) == .increase)
        #expect(EstimatedMaxTileView.direction(of: Weight(grams: -500)) == .decrease)
        #expect(EstimatedMaxTileView.direction(of: Weight(grams: 0)) == .unchanged)
    }

    // MARK: - Fixtures

    private func tiles(
        over fixture: DashboardFixture, failing: Bool = false
    ) -> EstimatedMaxTilesState {
        EstimatedMaxTilesState(
            records: fixture.records,
            catalogue: failing ? FailingExerciseRepository() : fixture.repositories.exercises,
            settings: fixture.repositories.settings)
    }
}
