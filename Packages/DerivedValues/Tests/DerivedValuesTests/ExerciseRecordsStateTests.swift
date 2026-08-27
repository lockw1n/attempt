import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// The `@Observable` half (`TR-1.5`, `TR-1.2`): what a screen sees, and when.
@Suite("Exercise records state")
@MainActor
struct ExerciseRecordsStateTests {
    /// Waits for `condition`, or gives up — so a failure is an assertion rather than a hung suite.
    ///
    /// **Polling rather than a second stream.** The state is what is under test, and subscribing to
    /// the same announcements it does would assert that the announcement arrived, not that the state
    /// acted on it. The interval is short and the ceiling generous: on a green run this returns on
    /// the first or second pass.
    private func settle(
        until condition: @MainActor () -> Bool,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Waits until `recomputer` has `count` subscribers.
    ///
    /// `observeChanges()` subscribes inside a detached task, so a publish issued straight after
    /// starting one can reach an empty subscriber list. Every test below that publishes to a state
    /// goes through here first.
    private func awaitSubscriber(
        on recomputer: PersonalRecordRecomputer,
        count: Int = 1,
        within attempts: Int = 200
    ) async {
        for _ in 0..<attempts {
            if await recomputer.subscriberCount >= count { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("A loaded state reports the exercise's rep maxes")
    func aLoadReportsTheRecords() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.failure == nil)
        #expect(state.repMaxes.map(\.reps) == [1, 2, 3, 4, 5])
    }

    /// **An exercise with no records and one nothing has looked at are both an empty list**, and a
    /// screen says opposite things about them — `FR-1.13.1`'s empty state versus its loading one.
    @Test("An exercise with no records loads empty rather than unloaded")
    func nothingLoggedIsLoadedAndEmpty() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        #expect(!state.hasLoaded)
        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.repMaxes.isEmpty)
    }

    /// `T-1.40`'s first *done when*: a completed set that sets a new 5RM reaches the cache and a
    /// subscribed state, with no rendering involved.
    @Test("A set that beats the 5RM reaches the cache and a subscribed state")
    func aNewRecordReachesASubscriber() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)
        await state.loadRecords()
        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 100_000))

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)

        // The set is logged the way the app logs one — through the repository — and then announced,
        // which is exactly what `LoggedSetWriter` and `ActiveSessionStore` do around their writes.
        try await log.repositories.workouts.save(
            log.setEntry(entryID: entryID, order: 1, on: weeksAgo(2), working(120_000, 5)))
        await recomputer.setDidChange(inEntryID: entryID)

        await settle { state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000) }

        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000))
        let cached = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(cached.first { $0.repCount == 5 }?.weight == Weight(grams: 120_000))
    }

    /// `FR-1.6.4`'s scope on the read side: every logged set announces, and a screen that reloaded
    /// on all of them would walk this exercise's history because a different one was trained.
    @Test("A change to another exercise leaves this state alone")
    func anotherExerciseDoesNotReload() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        try await log.session(of: squat, on: weeksAgo(2), sets: [working(100_000, 5)])
        let benchEntry = try await log.session(
            of: bench, on: weeksAgo(2), sets: [working(70_000, 5)])
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: counting, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: squat, recomputer: recomputer)
        await state.loadRecords()

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)
        await counting.reset()
        await recomputer.setDidChange(inEntryID: benchEntry)

        // Long enough that a reload would have happened; the assertion is that none did.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counting.walkedExercises == [bench])
    }

    /// A rep max reads no setting at all, so nothing a formula picker does can move one — reloading
    /// the list on a formula change would be a walk for an answer that cannot have changed.
    @Test("A formula change reloads the estimate and not the records")
    func aFormulaChangeReloadsOnlyTheEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            formula: .epley,
            now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)
        await state.load()
        let recordsBefore = state.repMaxes
        let estimateBefore = try #require(state.estimatedMax)

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)
        await recomputer.formulaDidChange(to: .brzycki)

        await settle { state.estimatedMax != estimateBefore }

        #expect(state.estimatedMax != estimateBefore)
        #expect(state.repMaxes == recordsBefore)
    }

    /// **A read may not announce, and this is the loop that proves why.** A cache holding nothing
    /// is recomputed on every read — an exercise with no records writes nothing that would stop the
    /// next pass — so a read that published would be told to read again by the subscriber it had
    /// just woken. Measured before the fix: ~10,000 walks of the exercise's history in 300 ms, with
    /// no exit.
    @Test("An exercise with no records does not recompute itself in a loop")
    func anEmptyExerciseSettles() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: counting, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        let watching = Task { await state.observeChanges() }
        defer { watching.cancel() }
        await awaitSubscriber(on: recomputer)
        await state.load()

        try? await Task.sleep(for: .milliseconds(100))
        let settled = await counting.exerciseWalks
        try? await Task.sleep(for: .milliseconds(100))

        // Both halves of `load()` walk once, and nothing announces, so the count stops at two.
        #expect(settled <= 2)
        #expect(await counting.exerciseWalks == settled)
    }

    /// **A repository read already in flight does not notice that a newer one has started**, so
    /// cancelling the task is not enough on its own: the abandoned read resumes and assigns. The
    /// token is what refuses it — the same rule the history search's walk carries.
    @Test("A superseded read does not publish over a newer one")
    func aSupersededReadDoesNotPublish() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let gated = GatedWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: gated, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        // The first read walks, sees 100 kg, and is held before it can assign.
        let stale = Task { await state.loadRecords() }
        for _ in 0..<200 {
            if await gated.startedWalks >= 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        // A heavier set lands, and a newer read takes the answer.
        try await log.repositories.workouts.save(
            log.setEntry(entryID: entryID, order: 1, on: weeksAgo(2), working(120_000, 5)))
        await state.loadRecords()
        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000))

        await gated.open()
        await stale.value

        // The abandoned read resumed holding 100 kg. It must not have landed.
        #expect(state.repMaxes.first { $0.reps == 5 }?.record.weight == Weight(grams: 120_000))
    }

    /// **A superseded recompute must not write the cache either.** The token above protects what is
    /// on screen; nothing protected the row, and the row is what `FR-1.6.2`'s list and `FR-1.6.3`'s
    /// badge read. Measured before the generation counter landed: the screen held 120 kg while the
    /// cache held 100 kg, until the next mutation of that exercise happened to recompute it.
    @Test("A superseded recompute does not write the cache over a newer one")
    func aSupersededRecomputeDoesNotWriteTheCache() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let gated = GatedWorkouts(wrapped: log.repositories.workouts)
        let recomputer = PersonalRecordRecomputer(
            workouts: gated, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        // The first read walks, sees 100 kg, and is held before it can write.
        let stale = Task { await state.loadRecords() }
        for _ in 0..<200 {
            if await gated.startedWalks >= 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        // A heavier set lands, and a newer read computes and stores 120 kg.
        try await log.repositories.workouts.save(
            log.setEntry(entryID: entryID, order: 1, on: weeksAgo(2), working(120_000, 5)))
        await state.loadRecords()

        await gated.open()
        await stale.value

        let cached = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(cached.first { $0.repCount == 5 }?.weight == Weight(grams: 120_000))
        #expect(cached.first { $0.repCount == 5 }?.weight != Weight(grams: 100_000))
    }

    /// **`FR-1.6.2`'s link, and it is a join rather than a stored column.** The cache holds the set;
    /// the session behind it is resolved on read, so a record that moved to another workout cannot
    /// leave a link pointing at the old one.
    @Test("Each record resolves to the session its source set was performed in")
    func recordsResolveToTheirSessions() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let old = try await log.session(
            of: exerciseID, on: weeksAgo(4), sets: [working(140_000, 1)])
        let recent = try await log.session(
            of: exerciseID, on: weeksAgo(1), sets: [working(120_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.load()

        // The heaviest single is four weeks back; the 5RM is last week's. Two records, two sessions.
        let single = try #require(state.repMaxes.first { $0.reps == 1 })
        let five = try #require(state.repMaxes.first { $0.reps == 5 })
        let oldSession = try #require(
            try await log.repositories.workouts.entry(id: old, includingDeleted: false)?.sessionID)
        let recentSession = try #require(
            try await log.repositories.workouts.entry(id: recent, includingDeleted: false)?
                .sessionID)
        #expect(state.sourceSessions[single.record.sourceSetID] == oldSession)
        #expect(state.sourceSessions[five.record.sourceSetID] == recentSession)
        #expect(oldSession != recentSession)
    }

    /// **A reload replaces the links with the list they belong to.** Kept across a replacement they
    /// would key on sets that are no longer records — a link on the wrong row rather than a missing
    /// one.
    @Test("Reloading the records drops links the new list does not own")
    func reloadingRecordsDropsStaleLinks() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        let entryID = try await log.session(
            of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: log.repositories.personalRecords, now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.load()
        let first = try #require(state.repMaxes.first { $0.reps == 5 }).record.sourceSetID
        #expect(state.sourceSessions[first] != nil)

        // A heavier set in a different workout takes the 5RM. The old set is no longer a record.
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(120_000, 5)])
        _ = try await recomputer.recompute(forExerciseID: exerciseID)

        // The list alone, before anything re-resolves. This is the assertion that can fail: after
        // `loadSources()` the map is replaced wholesale, so a test looking only at the end state
        // passes whether or not the replacement ever dropped the previous list's links — which is
        // exactly the window a screen draws in between the two reads.
        await state.loadRecords()
        #expect(state.sourceSessions.isEmpty)

        await state.loadSources()
        let second = try #require(state.repMaxes.first { $0.reps == 5 }).record.sourceSetID
        #expect(second != first)
        #expect(state.sourceSessions[first] == nil)
        #expect(state.sourceSessions[second] != nil)
        #expect(entryID != second)
    }

    /// **The estimate's success must not speak for the list.** ``ExerciseRecordsState/load()`` runs
    /// the estimate second, so one shared diagnostic let it clear a failed record read — leaving an
    /// empty list, a `true` `hasLoaded` and no failure, which is exactly what a screen renders as
    /// "this exercise holds no records" (`FR-1.13.1`).
    @Test("A successful estimate does not clear a failed record read")
    func aSucceedingEstimateKeepsTheRecordsFailure() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(2), sets: [working(100_000, 5)])
        let failure = RepositoryError.recordNotFound(id: UUID())
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts, cache: RefusingCache(failure: failure), now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: exerciseID, recomputer: recomputer)

        await state.load()

        // The estimate reads no cache, so it succeeds where the records read did not.
        #expect(state.estimatedMax != nil)
        #expect(state.repMaxes.isEmpty)
        #expect(state.failure == String(describing: failure))
    }

    @Test("A read that fails is reported as a diagnostic and does not claim records")
    func aFailedReadIsReported() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let recomputer = PersonalRecordRecomputer(
            workouts: RefusingWorkouts(failure: failure),
            cache: InMemoryRepositoryStack().personalRecords,
            now: { fixtureNow })
        let state = ExerciseRecordsState(exerciseID: UUID(), recomputer: recomputer)

        await state.loadRecords()

        #expect(state.hasLoaded)
        #expect(state.repMaxes.isEmpty)
        #expect(state.failure == String(describing: failure))
    }
}

/// A cache that refuses everything, so the records half fails while the estimate half does not.
struct RefusingCache: PersonalRecordCacheRepository {
    let failure: RepositoryError

    func personalRecords(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [PersonalRecordCache] { throw failure }
    func personalRecords(includingDeleted: Bool) async throws -> [PersonalRecordCache] {
        throw failure
    }
    func replacePersonalRecords(
        forExerciseID exerciseID: UUID, with values: [PersonalRecordCacheValues]
    ) async throws { throw failure }
}

/// A repository whose first exercise walk is held open *after* it has read, so a superseded read can
/// be made to resume last while holding the older answer.
actor GatedWorkouts: WorkoutRepository {
    private let wrapped: any WorkoutRepository
    private var walks = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// How many exercise walks have begun.
    var startedWalks: Int { walks }

    /// Lets the held walk return.
    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        walks += 1
        let held = walks == 1
        let answer = try await wrapped.sets(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
        if held, !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return answer
    }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
}

/// A repository that refuses every read, for the diagnostic path.
struct RefusingWorkouts: WorkoutRepository {
    let failure: RepositoryError

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw failure }
    func save(_ entry: ExerciseEntry) async throws { throw failure }
    func deleteExerciseEntry(id: UUID) async throws { throw failure }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
    func save(_ set: SetEntry) async throws { throw failure }
    func deleteSet(id: UUID) async throws { throw failure }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
}
