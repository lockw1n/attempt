import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-17.3.3`'s pushed lift picker: what it lists, what a tick writes, and what it tells the feed.
///
/// The list itself was `RecentRecordsSettingsStateTests`' until `FR-17.3.3` made it a screen; what
/// is new here is that the write has to announce itself, because the screen behind this one is not
/// the feed.
@Suite("Recent PRs — the lifts in the feed")
@MainActor
struct RecentRecordsExercisesStateTests {
    /// A store with two exercises in it, and the picker's state over it.
    private struct Chosen {
        let repositories: InMemoryRepositoryStack
        let recomputer: PersonalRecordRecomputer
        let state: RecentRecordsExercisesState
        let squat: UUID
        let kickback: UUID
    }

    private func chosen() async throws -> Chosen {
        let repositories = InMemoryRepositoryStack()
        let recomputer = PersonalRecordRecomputer(
            workouts: repositories.workouts,
            cache: repositories.personalRecords)
        let squat = try await repositories.save(
            exerciseNamed: "Back Squat", movement: .squat, isCustom: false)
        let kickback = try await repositories.save(
            exerciseNamed: "Triceps Kickback", movement: .other, isCustom: true)
        try await repositories.log(
            exerciseID: squat, grams: 140_000, reps: 5, sets: 3, dayOffset: 0)
        try await recomputer.recompute(forExerciseID: squat)
        let state = RecentRecordsExercisesState(
            settings: repositories.settings, catalogue: repositories.exercises, records: recomputer)
        return Chosen(
            repositories: repositories,
            recomputer: recomputer,
            state: state,
            squat: squat,
            kickback: kickback)
    }

    @Test("A load lists the catalogue, ordered by name, with the stored ticks")
    func aLoadListsTheCatalogue() async throws {
        let fixture = try await chosen()
        var stored = try await fixture.repositories.settings.settings()
        stored.recentRecordsExerciseIDs = [fixture.kickback]
        try await fixture.repositories.settings.save(stored)

        await fixture.state.load()

        #expect(fixture.state.hasLoaded)
        #expect(fixture.state.failure == nil)
        #expect(fixture.state.choices.map(\.name) == ["Back Squat", "Triceps Kickback"])
        #expect(fixture.state.choices.filter(\.isTiled).map(\.exerciseID) == [fixture.kickback])
    }

    /// `NFR-1.8`: a tick is stored as it is made, with no Save button to forget.
    @Test("A tick is written straight through, and unticking takes it back out")
    func aTickWritesThrough() async throws {
        let fixture = try await chosen()
        await fixture.state.load()

        await fixture.state.toggle(fixture.kickback)
        #expect(
            try await fixture.repositories.settings.settings().recentRecordsExerciseIDs
                == [fixture.kickback])
        #expect(fixture.state.writeFailure == nil)

        await fixture.state.toggle(fixture.kickback)
        #expect(try await fixture.repositories.settings.settings().recentRecordsExerciseIDs == [])
    }

    /// `FR-16.5.3`: the search narrows the sections, and the population it narrows is unchanged —
    /// which is what lets the no-matches state offer to clear the query rather than saying the
    /// catalogue is empty.
    @Test("The search narrows the sections without emptying the choices")
    func theSearchNarrowsTheSections() async throws {
        let fixture = try await chosen()
        await fixture.state.load()

        fixture.state.searchText = "kick"

        #expect(fixture.state.sections.flatMap { $0.choices }.map(\.name) == ["Triceps Kickback"])
        #expect(fixture.state.choices.count == 2)
        #expect(RecentRecordsExercisesScreenState.current(fixture.state) != .empty)
    }

    /// `TR-1.5`: the feed is on another tab and is not revisited on the way back, so the write has
    /// to announce itself — the settings screen this one is pushed from does not do it for us.
    @Test("A tick announces itself, so a subscribed feed re-reads")
    func aTickAnnouncesItself() async throws {
        let fixture = try await chosen()
        var stored = try await fixture.repositories.settings.settings()
        stored.recentRecordsScope = .chosen
        stored.recentRecordsShowsBaselines = true
        try await fixture.repositories.settings.save(stored)
        await fixture.state.load()
        let feed = RecentRecordsState(
            recomputer: fixture.recomputer,
            catalogue: fixture.repositories.exercises,
            settings: fixture.repositories.settings,
            limit: 5,
            defaultDashboardExerciseIDs: DashboardDefaults.exerciseIDs(in:mostTrained:))
        await feed.load()
        #expect(feed.records.isEmpty)

        let subscription = Task { await feed.observeChanges() }
        defer { subscription.cancel() }
        // The subscriber count is `DerivedValues`' own, so this waits on the effect instead: the
        // tick is re-applied until the feed has re-read or the attempts run out. An even number of
        // taps, so what the row ends up holding is what the assertion expects.
        for _ in 0..<200 where feed.records.isEmpty {
            await fixture.state.toggle(fixture.squat)
            await fixture.state.toggle(fixture.kickback)
        }

        #expect(feed.records.map(\.exerciseID) == [fixture.squat])
    }

    /// A catalogue that cannot be read is the failed state rather than an empty list: an empty list
    /// says the store holds nothing to choose from, which is a different fact.
    @Test("A catalogue that cannot be read is the failed state")
    func anUnreadableCatalogueFails() async throws {
        let repositories = InMemoryRepositoryStack()
        let state = RecentRecordsExercisesState(
            settings: repositories.settings,
            catalogue: RefusingExerciseCatalogue(),
            records: PersonalRecordRecomputer(
                workouts: repositories.workouts,
                cache: repositories.personalRecords))

        await state.load()

        #expect(state.hasLoaded)
        #expect(state.choices.isEmpty)
        #expect(state.failure != nil)
        #expect(RecentRecordsExercisesScreenState.current(state) == .failed)
    }

    /// A tick that could not be stored is reported beside the rows it did not change.
    @Test("A tick that cannot be stored leaves the rows up and reports it")
    func anUnstorableTickReports() async throws {
        let fixture = try await chosen()
        let state = RecentRecordsExercisesState(
            settings: RefusingSettingsRow(),
            catalogue: fixture.repositories.exercises,
            records: fixture.recomputer)
        await state.load()

        await state.toggle(fixture.kickback)

        #expect(state.writeFailure != nil)
    }

    /// An empty catalogue is its own state — a restore of an emptied store can reach it, and a
    /// seeded install cannot.
    @Test("An empty catalogue is the empty state, not the loading one")
    func anEmptyCatalogueIsEmpty() async throws {
        let repositories = InMemoryRepositoryStack()
        let state = RecentRecordsExercisesState(
            settings: repositories.settings,
            catalogue: repositories.exercises,
            records: PersonalRecordRecomputer(
                workouts: repositories.workouts,
                cache: repositories.personalRecords))

        await state.load()

        #expect(RecentRecordsExercisesScreenState.current(state) == .empty)
    }
}

/// A catalogue that refuses every read.
private struct RefusingExerciseCatalogue: ExerciseRepository {
    /// What every call throws. The case does not matter — the state reports *that* it failed.
    private let failure = RepositoryError.recordNotFound(id: UUID())

    func exercises(includingDeleted: Bool) async throws -> [Exercise] { throw failure }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { throw failure }

    func save(_ exercise: Exercise) async throws { throw failure }
}

/// A settings repository that refuses every read and write.
private struct RefusingSettingsRow: SettingsRepository {
    /// What every call throws.
    private let failure = RepositoryError.recordNotFound(id: UUID())

    func settings() async throws -> UserSettings { throw failure }

    func save(_ settings: UserSettings) async throws { throw failure }

    func restorePreferences(from backup: UserSettings) async throws { throw failure }
}
