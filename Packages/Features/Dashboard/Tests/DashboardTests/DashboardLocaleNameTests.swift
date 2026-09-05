import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.14.2` on the Dashboard tab. Each of these three states bakes an exercise's name into a
/// value a row draws — a tile's headline, a picker's label, the card's list — so none of them can be
/// resolved by the view, and each has to be told which name it is building.
///
/// **The picker's Ukrainian names sort against their English ones**, for the reason
/// `ExerciseLocaleDisplayTests` gives: an order is the assertion a wrong name column actually fails.
@MainActor
@Suite("Dashboard exercise names, resolved for the screen's locale")
struct DashboardLocaleNameTests {
    @Test("A tile carries the Ukrainian name, and the English one where none is set")
    func tilesCarryTheResolvedName() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(
            named: "Back Squat", ukrainian: "Присідання зі штангою", movement: .squat)
        let row = try await fixture.exercise(named: "Barbell Row", movement: .row)
        try await fixture.tile([squat, row])

        let state = EstimatedMaxTilesState(
            records: fixture.records,
            catalogue: fixture.repositories.exercises,
            settings: fixture.repositories.settings,
            trainingMaxes: fixture.repositories.trainingMaxes)
        state.nameLanguage = .ukrainian
        await state.load()

        #expect(state.tiles.map(\.name) == ["Присідання зі штангою", "Barbell Row"])
    }

    @Test("The picker's rows carry the resolved name, and are ordered by it")
    func pickerRowsCarryAndFollowTheResolvedName() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(
            named: "Back Squat", ukrainian: "Присідання зі штангою", movement: .squat)
        try await fixture.exercise(
            named: "Front Squat", ukrainian: "Глибокі присідання", movement: .squat)
        try await fixture.exercise(named: "Barbell Row", movement: .row)

        let state = TiledExerciseSelectionState(
            catalogue: fixture.repositories.exercises, settings: fixture.repositories.settings)
        state.nameLanguage = .ukrainian
        await state.load()

        #expect(
            state.choices.map(\.name) == ["Barbell Row", "Глибокі присідання", "Присідання зі штангою"])
    }

    @Test("The last-workout card lists the resolved names")
    func thecardListsTheResolvedNames() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(
            named: "Back Squat", ukrainian: "Присідання зі штангою", movement: .squat)
        let row = try await fixture.exercise(named: "Barbell Row", movement: .row)
        try await fixture.session(
            on: weeksAgo(1),
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5)]),
                (row, [LoggedSet(grams: 60_000, reps: 8)]),
            ])

        let state = LastWorkoutState(
            workouts: fixture.repositories.workouts, catalogue: fixture.repositories.exercises)
        state.nameLanguage = .ukrainian
        await state.load()

        #expect(state.summary?.exerciseNames == ["Присідання зі штангою", "Barbell Row"])
    }

    /// The one place on this tab that reads the English column on purpose: which exercise gets a
    /// tile before anyone has configured one is a choice that must not move when a lifter changes
    /// their phone's language.
    @Test("The unconfigured default is chosen by the English name, whatever the screen shows")
    func thedefaultSelectionIsLocaleIndependent() async throws {
        let fixture = DashboardFixture()
        // Alphabetically first in English, last in Ukrainian — so the two rules disagree here.
        let aSquat = try await fixture.exercise(
            named: "A Squat", ukrainian: "Я присідання", movement: .squat)
        try await fixture.exercise(named: "B Squat", ukrainian: "А присідання", movement: .squat)

        let state = EstimatedMaxTilesState(
            records: fixture.records,
            catalogue: fixture.repositories.exercises,
            settings: fixture.repositories.settings,
            trainingMaxes: fixture.repositories.trainingMaxes)
        state.nameLanguage = .ukrainian
        await state.load()

        #expect(state.selection == [aSquat])
        #expect(state.tiles.map(\.name) == ["Я присідання"])
    }
}
