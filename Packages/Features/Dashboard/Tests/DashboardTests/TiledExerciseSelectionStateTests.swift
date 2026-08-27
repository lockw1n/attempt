import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.1`'s "configurable which exercises appear": the picker, and what a tick writes.
@MainActor
@Suite("Dashboard tile picker")
struct TiledExerciseSelectionStateTests {
    @Test("The picker opens holding what the dashboard is already showing")
    func thepickerOpensHoldingTheDefaults() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.exercise(named: "Leg Press", movement: .squat, equipment: .machine)

        let state = picker(over: fixture)
        await state.load()

        #expect(state.selection == [squat])
        #expect(state.choices.map(\.isTiled) == [true, false])
    }

    @Test("The rows are every unarchived exercise, ordered by name")
    func therowsAreEveryUnarchivedExercise() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "Bench Press", movement: .bench)
        try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.exercise(named: "Old Lift", movement: .row, isArchived: true)

        let state = picker(over: fixture)
        await state.load()

        #expect(state.choices.map(\.name) == ["Back Squat", "Bench Press"])
    }

    /// Hiding an archived exercise that is already tiled would leave a tile the user can see and
    /// cannot remove.
    @Test("An archived exercise that is tiled stays listed")
    func anarchivedTiledExerciseStaysListed() async throws {
        let fixture = DashboardFixture()
        let retired = try await fixture.exercise(
            named: "Old Lift", movement: .row, isArchived: true)
        try await fixture.tile([retired])

        let state = picker(over: fixture)
        await state.load()

        #expect(state.choices.map(\.name) == ["Old Lift"])
        #expect(state.choices.first?.isTiled == true)
    }

    @Test("Ticking an exercise appends it and stores the result")
    func tickinganExerciseAppendsIt() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let press = try await fixture.exercise(named: "Overhead Press", movement: .overheadPress)
        try await fixture.tile([squat])

        let state = picker(over: fixture)
        await state.load()
        await state.toggle(press)

        #expect(state.selection == [squat, press])
        let stored = try await fixture.repositories.settings.settings()
        #expect(stored.dashboardExerciseIDs == [squat, press])
    }

    @Test("Unticking removes it and leaves the rest in order")
    func untickingRemovesIt() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        try await fixture.tile([squat, bench])

        let state = picker(over: fixture)
        await state.load()
        await state.toggle(squat)

        #expect(state.selection == [bench])
        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == [bench])
    }

    /// The first tick is what turns the three defaults into a stored choice — before it, nothing is
    /// written, so a catalogue that gains a competition lift later is still tiled.
    @Test("Nothing is stored until the first tick")
    func nothingIsStoredUntilTheFirstTick() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)

        let state = picker(over: fixture)
        await state.load()
        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == nil)

        await state.toggle(squat)
        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == [])
    }

    /// A failed write is reported beside the rows it did not change — and those rows are what the
    /// next read replaces, so the diagnostic goes with them rather than outliving them.
    @Test("A failed toggle changes nothing, and is retired by the next read")
    func afailedToggleIsRetiredByTheNextRead() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let state = TiledExerciseSelectionState(
            catalogue: fixture.repositories.exercises,
            settings: ReadOnlySettingsRepository(stored: fixture.repositories.settings))
        await state.load()

        await state.toggle(squat)

        #expect(state.writeFailure != nil)
        #expect(state.selection == [squat])
        #expect(try await fixture.repositories.settings.settings().dashboardExerciseIDs == nil)

        await state.load()
        #expect(state.writeFailure == nil)
    }

    // MARK: - The screen's four states

    @Test("A failed read is the error state")
    func afailedReadIsTheErrorState() async {
        let state = TiledExerciseSelectionState(
            catalogue: FailingExerciseRepository(),
            settings: DashboardFixture().repositories.settings)
        await state.load()

        #expect(TiledExerciseSelectionScreenState.current(state) == .failed)
    }

    @Test("An empty catalogue is the empty state, and no read yet is loading")
    func anemptyCatalogueIsTheEmptyState() async {
        let state = picker(over: DashboardFixture())
        #expect(TiledExerciseSelectionScreenState.current(state) == .loading)

        await state.load()
        #expect(TiledExerciseSelectionScreenState.current(state) == .empty)
    }

    // MARK: - Fixtures

    private func picker(over fixture: DashboardFixture) -> TiledExerciseSelectionState {
        TiledExerciseSelectionState(
            catalogue: fixture.repositories.exercises, settings: fixture.repositories.settings)
    }
}
