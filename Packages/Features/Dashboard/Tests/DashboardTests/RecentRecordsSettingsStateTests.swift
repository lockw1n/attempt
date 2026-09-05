import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-16.3`'s configuration screen: what it reads, what it writes, and what it tells the feed.
@Suite("Recent PRs configuration")
@MainActor
struct RecentRecordsSettingsStateTests {
    /// A store with one improving lift in it, and the screen's state over it.
    private struct Configured {
        let repositories: InMemoryRepositoryStack
        let recomputer: PersonalRecordRecomputer
        let state: RecentRecordsSettingsState
        let squat: UUID
        let kickback: UUID
    }

    private func configured() async throws -> Configured {
        let repositories = InMemoryRepositoryStack()
        let recomputer = PersonalRecordRecomputer(
            workouts: repositories.workouts,
            cache: repositories.personalRecords)
        let squat = try await repositories.save(
            exerciseNamed: "Back Squat", movement: .squat, isCustom: false)
        let kickback = try await repositories.save(
            exerciseNamed: "Triceps Kickback", movement: .other, isCustom: true)
        // Three 5 × 3 runs, improving: enough for `FR-16.3.2`'s threshold, and not a baseline.
        for (offset, grams) in [(0, 120_000), (1, 130_000), (2, 140_000)] {
            try await repositories.log(
                exerciseID: squat, grams: grams, reps: 5, sets: 3, dayOffset: offset)
        }
        try await recomputer.recompute(forExerciseID: squat)
        try await recomputer.recompute(forExerciseID: kickback)
        let state = RecentRecordsSettingsState(
            settings: repositories.settings, catalogue: repositories.exercises, records: recomputer)
        return Configured(
            repositories: repositories,
            recomputer: recomputer,
            state: state,
            squat: squat,
            kickback: kickback)
    }

    @Test("A load reports the stored row, the exercises and the schemes in scope")
    func aLoadReportsTheConfiguration() async throws {
        let fixture = try await configured()

        await fixture.state.load()

        #expect(fixture.state.hasLoaded)
        #expect(fixture.state.failure == nil)
        #expect(fixture.state.settings?.recentRecordsScope == .dashboardLifts)
        #expect(fixture.state.exerciseChoices.map(\.name) == ["Back Squat", "Triceps Kickback"])
        // The squat is the only competition lift installed, so the default scope resolves to it and
        // the schemes offered are its own.
        #expect(fixture.state.schemeChoices.map(\.scheme) == [RecordScheme(reps: 5, sets: 3)])
        #expect(fixture.state.schemeChoices.allSatisfy { !$0.isChosen })
    }

    /// `NFR-1.8`'s posture: each control is stored on change, with no Save button to forget.
    @Test("Every control writes straight through")
    func everyControlWritesThrough() async throws {
        let fixture = try await configured()
        await fixture.state.load()

        await fixture.state.apply { $0.recentRecordsScope = .chosen }
        await fixture.state.toggleExercise(fixture.kickback)
        await fixture.state.apply { $0.recentRecordsShowsBaselines = true }

        let stored = try await fixture.repositories.settings.settings()
        #expect(stored.recentRecordsScope == .chosen)
        #expect(stored.recentRecordsExerciseIDs == [fixture.kickback])
        #expect(stored.recentRecordsShowsBaselines == true)
        #expect(fixture.state.writeFailure == nil)
    }

    /// The chosen list is a narrowing, so turning it on must not empty the feed: it starts holding
    /// everything on offer and the lifter takes cells out of it.
    @Test("Turning the chosen list on seeds it with every scheme on offer")
    func choosingSchemesSeedsFromWhatIsOffered() async throws {
        let fixture = try await configured()
        await fixture.state.load()

        await fixture.state.setSchemesDerived(false)

        #expect(
            fixture.state.settings?.recentRecordsSchemes
                == .chosen([RecordScheme(reps: 5, sets: 3)]))
        #expect(fixture.state.schemeChoices.allSatisfy { $0.isChosen })
    }

    @Test("A scheme is taken out of the chosen list and put back")
    func aSchemeTogglesInTheChosenList() async throws {
        let fixture = try await configured()
        await fixture.state.load()
        await fixture.state.setSchemesDerived(false)
        let scheme = RecordScheme(reps: 5, sets: 3)

        await fixture.state.toggleScheme(scheme)
        #expect(fixture.state.settings?.recentRecordsSchemes == .chosen([]))
        // Still offered, though nothing ticks it: a picker whose selection has left its own options
        // cannot be put back.
        #expect(fixture.state.schemeChoices.map(\.scheme) == [scheme])

        await fixture.state.toggleScheme(scheme)
        #expect(fixture.state.settings?.recentRecordsSchemes == .chosen([scheme]))
    }

    /// `TR-1.5`: the feed is on another screen and is not revisited on the way back, so the write
    /// has to announce itself.
    @Test("A change announces itself, so a subscribed feed re-reads")
    func aChangeAnnouncesItself() async throws {
        let fixture = try await configured()
        await fixture.state.load()
        var stored = try await fixture.repositories.settings.settings()
        stored.dashboardExerciseIDs = []
        try await fixture.repositories.settings.save(stored)
        let feed = RecentRecordsState(
            recomputer: fixture.recomputer,
            catalogue: fixture.repositories.exercises,
            settings: fixture.repositories.settings,
            limit: 5,
            defaultDashboardExerciseIDs: DashboardDefaults.exerciseIDs(in:))
        await feed.load()
        #expect(feed.records.isEmpty)

        let subscription = Task { await feed.observeChanges() }
        defer { subscription.cancel() }
        // The subscriber count is `DerivedValues`' own, so this waits on the effect instead: the
        // announcement is retried until the feed has re-read or the attempts run out.
        for _ in 0..<200 where feed.records.isEmpty {
            await fixture.state.apply { $0.recentRecordsScope = .everyExercise }
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(feed.records.map(\.exerciseID) == [fixture.squat])
    }

    /// A read that failed is reported rather than drawn as an unconfigured screen — the row decides
    /// what the feed contains, so a blank one presented as a configuration would be a lie.
    @Test("A settings row that cannot be read is the failed state")
    func anUnreadableRowFails() async throws {
        let repositories = InMemoryRepositoryStack()
        let state = RecentRecordsSettingsState(
            settings: RefusingSettings(),
            catalogue: repositories.exercises,
            records: PersonalRecordRecomputer(
                workouts: repositories.workouts,
                cache: repositories.personalRecords))

        await state.load()

        #expect(state.hasLoaded)
        #expect(state.settings == nil)
        #expect(state.failure != nil)
        #expect(RecentRecordsSettingsScreenState.current(state) == .failed)
    }

    /// A write that failed is reported beside the controls it did not move, rather than replacing
    /// them: the row is still loaded and still editable.
    @Test("A change that cannot be stored leaves the controls up and reports it")
    func anUnstorableChangeReports() async throws {
        let fixture = try await configured()
        await fixture.state.load()
        let state = RecentRecordsSettingsState(
            settings: RefusingSettings(),
            catalogue: fixture.repositories.exercises,
            records: fixture.recomputer)
        await state.load()

        await state.apply { $0.recentRecordsShowsBaselines = true }

        #expect(state.writeFailure != nil)
    }
}

/// A settings repository that refuses every read and write.
private struct RefusingSettings: SettingsRepository {
    /// What every call throws. The case does not matter — the state reports *that* it failed.
    private let failure = RepositoryError.recordNotFound(id: UUID())

    func settings() async throws -> UserSettings { throw failure }

    func save(_ settings: UserSettings) async throws { throw failure }

    func restorePreferences(from backup: UserSettings) async throws { throw failure }
}

extension InMemoryRepositoryStack {
    /// One catalogue row, enough for the configuration screen's list.
    fileprivate func save(
        exerciseNamed name: String, movement: Movement, isCustom: Bool
    ) async throws -> UUID {
        let id = UUID()
        try await exercises.save(
            Exercise(
                id: id,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: name,
                ukrainianName: nil,
                movement: movement,
                parentExerciseID: nil,
                equipment: .barbell,
                laterality: .bilateral,
                barType: .standard,
                implementCount: 1,
                isCustom: isCustom,
                isArchived: false,
                notes: "",
                manualE1RM: nil))
        return id
    }

    /// A session of `sets` consecutive completed working sets, on its own training day.
    fileprivate func log(
        exerciseID: UUID, grams: Int, reps: Int, sets: Int, dayOffset: Int
    ) async throws {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
            .addingTimeInterval(Double(dayOffset) * 86_400)
        let sessionID = UUID()
        try await workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: day,
                updatedAt: day,
                deletedAt: nil,
                date: day,
                startedAt: nil,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil))
        let entryID = UUID()
        try await workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: day,
                updatedAt: day,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: ""))
        for order in 0..<sets {
            try await workouts.save(
                SetEntry(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    entryID: entryID,
                    order: order,
                    weight: Weight(grams: grams),
                    reps: reps,
                    rpe: nil,
                    rir: nil,
                    isWarmup: false,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: day))
        }
    }
}
