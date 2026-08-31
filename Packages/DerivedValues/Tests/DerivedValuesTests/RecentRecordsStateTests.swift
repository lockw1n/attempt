import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// The `@Observable` half of `FR-1.6.5`'s feed: what a screen sees, and when.
@Suite("Recent records state")
@MainActor
struct RecentRecordsStateTests {
    /// Waits for `condition`, or gives up — `ExerciseRecordsStateTests`' helper, for its reason.
    private func settle(
        until condition: @MainActor () -> Bool,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Waits until `recomputer` has a subscriber, so a publish cannot reach an empty list.
    private func awaitSubscriber(
        on recomputer: PersonalRecordRecomputer,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if await recomputer.subscriberCount >= 1 { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// A log, the recomputer over it, and the exercises in it — a value rather than a tuple,
    /// because three members is one past the lint ceiling and `.2` says nothing at a call site.
    private struct Trained {
        let log: TrainingLog
        let recomputer: PersonalRecordRecomputer
        let exercises: [UUID]
    }

    /// Two exercises trained on different days, both recomputed.
    private func trainedLog() async throws -> Trained {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        try await log.session(of: squat, on: weeksAgo(4), sets: [working(140_000, 3)])
        try await log.session(of: bench, on: weeksAgo(1), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        try await recomputer.recompute(forExerciseID: bench)
        return Trained(log: log, recomputer: recomputer, exercises: [squat, bench])
    }

    @Test("A load reports the feed and the exercise behind each entry")
    func aLoadReportsTheFeed() async throws {
        let trained = try await trainedLog()
        let state = RecentRecordsState(
            recomputer: trained.recomputer, catalogue: trained.log.repositories.exercises, limit: 10)

        await state.load()

        #expect(state.hasLoaded)
        #expect(state.failure == nil)
        #expect(state.records.map(\.exerciseID) == [trained.exercises[1], trained.exercises[0]])
        #expect(state.exerciseNames[trained.exercises[0]] == "Back Squat")
        #expect(state.exerciseNames[trained.exercises[1]] == "Bench Press")
    }

    /// A feed with nothing in it and one nothing has looked at are both an empty list, and a screen
    /// says opposite things about them (`FR-1.13.1`).
    @Test("A store with no records loads empty rather than unloaded")
    func nothingLoggedIsLoadedAndEmpty() async throws {
        let log = TrainingLog()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        let state = RecentRecordsState(
            recomputer: recomputer, catalogue: log.repositories.exercises, limit: 10)

        #expect(!state.hasLoaded)
        await state.load()

        #expect(state.hasLoaded)
        #expect(state.records.isEmpty)
        #expect(state.exerciseNames.isEmpty)
        #expect(state.failure == nil)
    }

    @Test("The limit is what reaches the screen")
    func theLimitIsHonoured() async throws {
        let trained = try await trainedLog()
        let state = RecentRecordsState(
            recomputer: trained.recomputer, catalogue: trained.log.repositories.exercises, limit: 1)

        await state.load()

        #expect(state.records.map(\.exerciseID) == [trained.exercises[1]])
        // The name join follows the drawn rows, not the whole catalogue.
        #expect(state.exerciseNames.count == 1)
    }

    @Test("A cache that cannot be read reports the failure rather than an empty feed")
    func anUnreadableCacheReports() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let recomputer = PersonalRecordRecomputer(
            workouts: InMemoryRepositoryStack().workouts,
            exercises: InMemoryRepositoryStack().exercises,
            cache: RefusingCache(failure: failure),
            now: { fixtureNow })
        let state = RecentRecordsState(
            recomputer: recomputer, catalogue: InMemoryRepositoryStack().exercises, limit: 10)

        await state.load()

        #expect(state.hasLoaded)
        #expect(state.records.isEmpty)
        #expect(state.failure == String(describing: failure))
    }

    /// The name join is best-effort: a catalogue that refuses costs the row its name and nothing
    /// else, because the record is still readable and reporting the feed unreadable would name the
    /// wrong thing as broken.
    @Test("A catalogue that cannot be read leaves the feed on screen without names")
    func anUnreadableCatalogueIsNotAFailure() async throws {
        let trained = try await trainedLog()
        let state = RecentRecordsState(
            recomputer: trained.recomputer,
            catalogue: RefusingExercises(failure: .recordNotFound(id: UUID())),
            limit: 10)

        await state.load()

        #expect(state.records.map(\.exerciseID) == [trained.exercises[1], trained.exercises[0]])
        #expect(state.exerciseNames.isEmpty)
        #expect(state.failure == nil)
    }

    @Test("A set logged against any exercise reaches a subscribed feed")
    func anyExerciseMovesTheFeed() async throws {
        let trained = try await trainedLog()
        let state = RecentRecordsState(
            recomputer: trained.recomputer, catalogue: trained.log.repositories.exercises, limit: 10)
        await state.load()
        #expect(state.records.first?.weight == Weight(grams: 100_000))

        let subscription = Task { await state.observeChanges() }
        defer { subscription.cancel() }
        await awaitSubscriber(on: trained.recomputer)
        // A heavier 5 on the older exercise: it takes the top of the feed only if the reload
        // happened, since its own session predates the other's.
        let entryID = try await trained.log.session(
            of: trained.exercises[0], on: weeksAgo(0), sets: [working(150_000, 5)])
        await trained.recomputer.setDidChange(inEntryID: entryID)

        await settle { state.records.first?.weight == Weight(grams: 150_000) }
        #expect(state.records.first?.exerciseID == trained.exercises[0])
        #expect(state.records.first?.achievedAt == weeksAgo(0))
    }

    /// **A cache read already in flight does not notice that a newer one has started**, so
    /// cancelling the task is not enough on its own: the abandoned read resumes and assigns. The
    /// token is what refuses it — `ExerciseRecordsState`'s gate, and the reason this type carries a
    /// copy of it.
    @Test("A superseded read does not publish over a newer one")
    func aSupersededReadDoesNotPublish() async throws {
        let log = TrainingLog()
        let bench = try await log.exercise(named: "Bench Press")
        try await log.session(of: bench, on: weeksAgo(1), sets: [working(100_000, 5)])
        let gated = GatedCache(wrapped: log.repositories.personalRecords)
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: gated,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: bench)
        let state = RecentRecordsState(
            recomputer: recomputer, catalogue: log.repositories.exercises, limit: 10)

        // The first read takes the cache holding 100 kg, and is held before it can assign.
        let stale = Task { await state.load() }
        for _ in 0..<200 {
            if await gated.startedFeedReads >= 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        // A heavier record lands, and a newer read takes the answer.
        try await log.repositories.personalRecords.replacePersonalRecords(
            forExerciseID: bench,
            with: [
                PersonalRecordCacheValues(
                    repCount: 5,
                    weight: Weight(grams: 150_000),
                    sourceSetID: UUID(),
                    achievedAt: weeksAgo(1),
                    computationVersion: PersonalRecordCalculator.computationVersion)
            ])
        await state.load()
        #expect(state.records.first?.weight == Weight(grams: 150_000))

        await gated.open()
        await stale.value

        // The abandoned read resumed holding 100 kg. It must not have landed.
        #expect(state.records.first?.weight == Weight(grams: 150_000))
    }

    /// A record outlives the retirement of the exercise it was set on, and an entry with no name is
    /// worse than one naming a retired movement — so the name join reads deleted rows too.
    ///
    /// Asserted against a catalogue that answers *only* when deleted rows are asked for, because no
    /// `ExerciseRepository` read soft-deletes one: the write ignores `deletedAt` (rule 7) and the
    /// protocol has no delete, so the flag cannot be set through the real API at all in this phase.
    @Test("The name join reads exercises the catalogue no longer lists")
    func aRetiredExerciseStillNamesItsRecord() async throws {
        let trained = try await trainedLog()
        let retired = trained.exercises[1]
        let state = RecentRecordsState(
            recomputer: trained.recomputer,
            catalogue: RetiredCatalogue(exerciseID: retired, name: "Bench Press"),
            limit: 10)

        await state.load()

        #expect(state.records.first?.exerciseID == retired)
        #expect(state.exerciseNames[retired] == "Bench Press")
    }

    /// A formula change moves every estimate and no rep max, so waking this feed for one would walk
    /// the cache for an answer that cannot have moved.
    @Test("A formula change does not reload the feed")
    func aFormulaChangeIsIgnored() async throws {
        let trained = try await trainedLog()
        let state = RecentRecordsState(
            recomputer: trained.recomputer, catalogue: trained.log.repositories.exercises, limit: 10)
        await state.load()

        let subscription = Task { await state.observeChanges() }
        defer { subscription.cancel() }
        await awaitSubscriber(on: trained.recomputer)
        // The cache is emptied behind the state's back: a reload would show it, so a feed that still
        // holds two entries is one that did not reload.
        for exerciseID in state.records.map(\.exerciseID) {
            try await trained.log.repositories.personalRecords.replacePersonalRecords(
                forExerciseID: exerciseID, with: [])
        }
        await trained.recomputer.formulaDidChange(to: .brzycki)

        await settle(until: { false }, within: 20)
        #expect(state.records.count == 2)
    }
}

/// A catalogue that refuses every read, so the name join fails while the feed itself does not.
struct RefusingExercises: ExerciseRepository {
    let failure: RepositoryError

    func exercises(includingDeleted: Bool) async throws -> [Exercise] { throw failure }
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { throw failure }
    func save(_ exercise: Exercise) async throws { throw failure }
    func trainingMax(
        forExerciseID exerciseID: UUID, on date: Date
    ) async throws -> TrainingMaxEntry? { throw failure }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] { throw failure }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws { throw failure }
}

/// A cache whose first cross-exercise read is held open *after* it has read, so a superseded read
/// can be made to resume last while holding the older answer. `GatedWorkouts`' shape, one store over.
///
/// **Only the feed's read is gated.** A recompute reads per exercise and writes, and holding either
/// would stall the fixture rather than the read under test.
actor GatedCache: PersonalRecordCacheRepository {
    private let wrapped: any PersonalRecordCacheRepository
    private var reads = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(wrapped: any PersonalRecordCacheRepository) {
        self.wrapped = wrapped
    }

    /// How many cross-exercise reads have begun.
    var startedFeedReads: Int { reads }

    /// Lets the held read return.
    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        reads += 1
        let held = reads == 1
        let answer = try await wrapped.personalRecords(includingDeleted: includingDeleted)
        if held, !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return answer
    }

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] {
        try await wrapped.personalRecords(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }

    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws {
        try await wrapped.replacePersonalRecords(forExerciseID: exerciseID, with: values)
    }
}

/// A catalogue holding one exercise that only a read asking for deleted rows can see.
struct RetiredCatalogue: ExerciseRepository {
    let exerciseID: UUID
    let name: String

    private var retired: Exercise {
        Exercise(
            id: exerciseID,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: .distantPast,
            name: name,
            ukrainianName: nil,
            movement: .bench,
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

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        includingDeleted ? [retired] : []
    }
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        includingDeleted && id == exerciseID ? retired : nil
    }
    func save(_ exercise: Exercise) async throws {}
    func trainingMax(
        forExerciseID exerciseID: UUID, on date: Date
    ) async throws -> TrainingMaxEntry? { nil }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] { [] }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}
