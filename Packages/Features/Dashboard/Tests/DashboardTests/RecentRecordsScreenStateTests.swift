import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.13.1`: which of the feed's five states a load is in, asserted without rendering anything.
@Suite("Recent records screen state")
@MainActor
struct RecentRecordsScreenStateTests {
    /// A feed's state over an empty store, which is enough for every case here — what is under test
    /// is the mapping, and the reads that produce it are `RecentRecordsStateTests`'.
    private func state(limit: Int = 5) -> RecentRecordsState {
        let repositories = InMemoryRepositoryStack()
        return RecentRecordsState(
            recomputer: PersonalRecordRecomputer(
                workouts: repositories.workouts,
                exercises: repositories.exercises,
                cache: repositories.personalRecords),
            catalogue: repositories.exercises,
            settings: repositories.settings,
            limit: limit,
            defaultDashboardExerciseIDs: DashboardDefaults.exerciseIDs(in:))
    }

    @Test("Before the first read it is loading, not empty")
    func anUnloadedFeedIsLoading() {
        #expect(RecentRecordsScreenState.current(state()) == .loading)
    }

    /// The scope is what separates the two empty states, and under `FR-16.3.1`'s default it is
    /// narrower than every exercise — so a store with nothing in it lands on the offer rather than
    /// on "log a working set".
    @Test("A store holding no records under the default scope offers the wider one")
    func anEmptyStoreUnderTheDefaultScopeOffers() async {
        let feed = state()
        await feed.load()

        #expect(feed.hasLoaded)
        #expect(RecentRecordsScreenState.current(feed) == .nothingInScope)
    }

    /// And at the widest scope there is nothing left to widen to, so the sentence is the one about
    /// what a set has to be.
    @Test("A store holding no records at the widest scope is the insufficient-data case")
    func anEmptyStoreHasNothingYet() async throws {
        let feed = state()
        try await widenScope(feed)
        await feed.load()

        #expect(RecentRecordsScreenState.current(feed) == .nothingYet)
    }

    /// `FR-16.3.4`'s offer taken: the setting moves, and the feed re-reads under it.
    @Test("Taking the offer widens the stored scope and reloads")
    func takingTheOfferWidensTheScope() async throws {
        let log = TrainingLogFixture()
        // Improved rather than logged once, so the standing record beat something: a baseline is
        // hidden by `FR-16.3.4`'s own default and widening the scope would not reveal it.
        try await log.trainAndImprove()
        // A lifter who removed every tile: `FR-1.9.1`'s selection is empty rather than never made,
        // so `FR-16.3.1`'s default scope resolves to nothing and the record is outside it.
        var stored = try await log.repositories.settings.settings()
        stored.dashboardExerciseIDs = []
        try await log.repositories.settings.save(stored)
        let feed = log.feed()
        await feed.load()
        #expect(RecentRecordsScreenState.current(feed) == .nothingInScope)

        await feed.widenScope()

        #expect(RecentRecordsScreenState.current(feed) == .ready)
        #expect(feed.scope == .everyExercise)
        #expect(
            try await log.repositories.settings.settings().recentRecordsScope == .everyExercise)
    }

    /// Widens the scope on the store behind `feed`, for the tests that are not about the offer.
    private func widenScope(_ feed: RecentRecordsState) async throws {
        await feed.widenScope()
    }

    @Test("Records to show is the ready case")
    func recordsAreReady() async throws {
        let log = TrainingLogFixture()
        let exerciseID = try await log.trainOnce()
        let feed = log.feed()
        try await log.showEveryRecord()

        await feed.load()

        #expect(feed.records.map(\.exerciseID) == [exerciseID])
        #expect(RecentRecordsScreenState.current(feed) == .ready)
    }

    /// The failure outranks a list already on screen: drawing the previous answer under no
    /// diagnostic presents a stale feed as a current one.
    @Test("A failed read outranks the records it left behind")
    func aFailureOutranksAStaleList() async throws {
        let log = TrainingLogFixture()
        try await log.trainOnce()
        let feed = log.feed()
        try await log.showEveryRecord()
        await feed.load()
        #expect(RecentRecordsScreenState.current(feed) == .ready)

        await log.refuseReads()
        await feed.load()

        #expect(!feed.records.isEmpty, "the previous answer is still held")
        #expect(RecentRecordsScreenState.current(feed) == .failed)
    }
}

/// One trained exercise over the fakes, with a cache that can be made to refuse.
@MainActor
private final class TrainingLogFixture {
    let repositories = InMemoryRepositoryStack()
    private let cache: SwitchableCache
    lazy var recomputer = PersonalRecordRecomputer(
        workouts: repositories.workouts,
        exercises: repositories.exercises,
        cache: cache)

    init() { cache = SwitchableCache(wrapping: repositories.personalRecords) }

    /// The feed over this fixture's store, at the card's length.
    func feed(limit: Int = 5) -> RecentRecordsState {
        RecentRecordsState(
            recomputer: recomputer,
            catalogue: repositories.exercises,
            settings: repositories.settings,
            limit: limit,
            defaultDashboardExerciseIDs: DashboardDefaults.exerciseIDs(in:))
    }

    /// Turns `FR-16.3`'s filters off, for the tests that are about the state mapping rather than
    /// about the configuration.
    func showEveryRecord() async throws {
        var stored = try await repositories.settings.settings()
        stored.recentRecordsScope = .everyExercise
        stored.recentRecordsShowsBaselines = true
        try await repositories.settings.save(stored)
    }

    /// Logs one working set against one exercise and recomputes it.
    @discardableResult
    func trainOnce() async throws -> UUID {
        let exerciseID = UUID()
        try await repositories.exercises.save(exercise(id: exerciseID))
        let entryID = try await loggedEntry(for: exerciseID)
        try await repositories.workouts.save(workingSet(inEntryID: entryID))
        try await recomputer.recompute(forExerciseID: exerciseID)
        return exerciseID
    }

    /// The same, and then a heavier session — so the standing record beat something and is not a
    /// baseline, which is what `FR-16.3.4` hides by default.
    @discardableResult
    func trainAndImprove() async throws -> UUID {
        let exerciseID = try await trainOnce()
        let later = day.addingTimeInterval(604_800)
        let entryID = try await loggedEntry(for: exerciseID, on: later)
        try await repositories.workouts.save(
            workingSet(inEntryID: entryID, grams: 150_000, on: later))
        try await recomputer.recompute(forExerciseID: exerciseID)
        return exerciseID
    }

    /// The day everything here is stamped with — fixed, so nothing drifts by run.
    private var day: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    /// One catalogue row.
    private func exercise(id: UUID) -> Exercise {
        Exercise(
            id: id,
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            name: "Back Squat",
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "",
            manualE1RM: nil)
    }

    /// A session and one entry under it, saved — returns the entry a set can be logged against.
    private func loggedEntry(for exerciseID: UUID, on stamp: Date? = nil) async throws -> UUID {
        let day = stamp ?? self.day
        let sessionID = UUID()
        try await repositories.workouts.save(
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
        try await repositories.workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: day,
                updatedAt: day,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: ""))
        return entryID
    }

    /// One completed working set, which is the only kind `FR-1.6.1` counts.
    private func workingSet(
        inEntryID entryID: UUID, grams: Int = 140_000, on stamp: Date? = nil
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: stamp ?? day,
            updatedAt: stamp ?? day,
            deletedAt: nil,
            entryID: entryID,
            order: 0,
            weight: Weight(grams: grams),
            reps: 3,
            rpe: nil,
            rir: nil,
            isWarmup: false,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: stamp ?? day)
    }

    /// Makes every later cache read throw, so a second load fails over a feed already on screen.
    func refuseReads() async {
        await cache.refuse()
    }
}

/// A cache that answers from the fakes until it is told to refuse.
///
/// **An actor rather than a class with an escape hatch** (`G-6.4`). The switch is written from the
/// test's `@MainActor` fixture and read from inside `PersonalRecordRecomputer`, which is an actor on
/// the cooperative pool — two isolation domains over one mutable flag, which is a real race rather
/// than an over-strict diagnostic. `PersonalRecordCacheRepository` is `Sendable` and every member is
/// `async throws`, so an actor conforms with nothing unchecked.
///
/// The wrapped store is a `let` for the same reason: it was only ever assigned once, at
/// construction, so making it settable bought a second shared mutable field and no test used it.
private actor SwitchableCache: PersonalRecordCacheRepository {
    /// Where a read that is not refusing is answered from.
    private let wrapped: any PersonalRecordCacheRepository

    /// Whether every later read throws.
    private var isRefusing = false

    /// What a refusal throws. The case does not matter — the state under test reports *that* a read
    /// failed, never which error it was.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    init(wrapping wrapped: any PersonalRecordCacheRepository) {
        self.wrapped = wrapped
    }

    /// Makes every later read throw.
    func refuse() {
        isRefusing = true
    }

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] {
        guard !isRefusing else { throw failure }
        return try await wrapped.personalRecords(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        guard !isRefusing else { throw failure }
        return try await wrapped.personalRecords(includingDeleted: includingDeleted)
    }

    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.replacePersonalRecords(forExerciseID: exerciseID, with: values)
    }
}
