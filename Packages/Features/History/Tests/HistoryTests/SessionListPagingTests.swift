import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import History

/// `NFR-1.5`: the list summarises a page at a time, so nothing about it is quadratic in a history's
/// size before T-1.83 gets to measure it.
@MainActor
@Suite("Session list paging")
struct SessionListPagingTests {
    @Test("The first read summarises one page, not the whole history")
    func firstReadIsOnePage() async throws {
        let log = try await Self.history(sessions: SessionListState.pageSize + 5)

        let state = log.listState()
        await state.load()

        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.hasMore)
        #expect(SessionListScreenState.current(state.phase) == .ready)
    }

    @Test("A history of 20+ sessions loads whole, newest first, one page at a time")
    func extendingReachesTheEnd() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)

        let state = log.listState()
        await state.load()
        await state.loadMore()

        #expect(state.summaries.count == total)
        #expect(state.hasMore == false)
        let dates = state.summaries.map(\.date)
        #expect(dates == dates.sorted(by: >))
        // Every row is distinct: a page built from the wrong offset repeats one.
        #expect(Set(state.summaries.map(\.id)).count == total)
    }

    @Test("loadMore() at the end of the list does nothing rather than re-reading")
    func extendingPastTheEndIsANoOp() async throws {
        let log = try await Self.history(sessions: 3)

        let state = log.listState()
        await state.load()
        let rows = state.summaries
        await state.loadMore()

        #expect(state.summaries == rows)
        #expect(state.extendFailure == nil)
    }

    @Test("A page that fails leaves the rows already on screen, and says so beside them")
    func extendFailureKeepsWhatLoaded() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)
        // Fails only once the first page is built, which is the case the separate property exists
        // for: a screen full of sessions must not be replaced by "History unavailable".
        let flaky = FlakyWorkoutRepository(
            wrapping: log.repositories.workouts, failingAfter: SessionListState.pageSize)
        let state = SessionListState(
            workouts: flaky,
            exercises: log.repositories.exercises,
            settings: log.repositories.settings
        )

        await state.load()
        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.extendFailure == nil)

        await state.loadMore()
        #expect(SessionListScreenState.current(state.phase) == .ready)
        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.extendFailure != nil)
        #expect(state.hasMore)
    }

    @Test("A page covers the 20-session history FR-1.5.1's list is proved against")
    func pageSizeCoversTheFixture() {
        // Every case here sizes its history as `pageSize + 5`, which scales with the constant — so a
        // page shrunk to four would leave the list proved against nine sessions and still green.
        #expect(SessionListState.pageSize >= 20)
    }

    @Test("An extension a re-read overtook does not publish over it")
    func supersededExtensionDoesNotPublish() async throws {
        let log = try await Self.history(sessions: SessionListState.pageSize + 5)
        // The first entry read past the first page — so the gate stops `loadMore()` and neither
        // `load()`.
        let gate = Self.gate(over: log, holdingRead: SessionListState.pageSize + 1)
        let state = Self.state(over: log, workouts: gate)

        await state.load()
        #expect(state.summaries.count == SessionListState.pageSize)

        let extending = Task { await state.loadMore() }
        await gate.arrival()

        // A workout was finished in the Train tab, and this tab was returned to — which fires the
        // screen's own `task` while the extension is still suspended mid-page.
        let finished = try await log.session(daysAgo: -1)
        await state.load()

        await gate.release()
        await extending.value

        // The newer read's list, whole. The extension's rows were offsets into a list that no
        // longer exists, so publishing them would have dropped `finished` and repeated the row at
        // the seam.
        #expect(state.summaries.count == SessionListState.pageSize)
        #expect(state.summaries.first?.id == finished.id)
        #expect(Set(state.summaries.map(\.id)).count == SessionListState.pageSize)
    }

    @Test("A second extension arriving mid-page does no work rather than building the page twice")
    func oneExtensionAtATime() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)
        let gate = Self.gate(over: log, holdingRead: SessionListState.pageSize + 1)
        let state = Self.state(over: log, workouts: gate)

        await state.load()
        let afterFirstPage = await gate.entryReads

        let extending = Task { await state.loadMore() }
        await gate.arrival()
        // The last row's `onAppear` fires again while the page it asked for is still being built.
        let second = Task { await state.loadMore() }
        await Task.yield()
        await gate.release()
        await extending.value
        await second.value

        #expect(state.summaries.count == total)
        #expect(Set(state.summaries.map(\.id)).count == total)
        // Five sessions were left to summarise, so five entry reads happened — not ten. Asserted as
        // work not done, because the rows come out right either way.
        let reads = await gate.entryReads
        #expect(reads == afterFirstPage + 5)
    }

    @Test("An extension left behind by a re-read does not wedge the next one")
    func supersededExtensionDoesNotWedgePaging() async throws {
        let total = SessionListState.pageSize + 5
        let log = try await Self.history(sessions: total)
        let gate = Self.gate(over: log, holdingRead: SessionListState.pageSize + 1)
        let state = Self.state(over: log, workouts: gate)

        await state.load()
        let abandoned = Task { await state.loadMore() }
        await gate.arrival()

        // The tab was returned to mid-page. The extension above is now reading offsets into a list
        // that is being replaced, and will refuse to publish — but it only clears its own flag when
        // it resumes, which may be long after the user has scrolled to the bottom of the new list.
        await state.load()

        // That scroll. It has to extend the list rather than be refused on behalf of a read that
        // has already been superseded.
        await state.loadMore()
        #expect(state.summaries.count == total)

        await gate.release()
        await abandoned.value

        #expect(state.summaries.count == total)
        #expect(Set(state.summaries.map(\.id)).count == total)
    }

    @Test("A second load() while the first is in flight is refused, not run twice")
    func oneLoadAtATime() async throws {
        let log = try await Self.history(sessions: SessionListState.pageSize + 5)
        // The very first entry read, which is inside the first page of the first `load()`.
        let gate = Self.gate(over: log, holdingRead: 1)
        let state = Self.state(over: log, workouts: gate)

        let reading = Task { await state.load() }
        await gate.arrival()
        // The screen appeared twice — a tab switched away from and back — mid-read.
        let second = Task { await state.load() }
        await Task.yield()
        await gate.release()
        await reading.value
        await second.value

        #expect(state.summaries.count == SessionListState.pageSize)
        let reads = await gate.entryReads
        #expect(reads == SessionListState.pageSize)
    }

    /// A gate over `log`'s workouts, holding one entry read.
    ///
    /// - Parameters:
    ///   - log: The store.
    ///   - read: Which entry read to suspend, counting from one.
    /// - Returns: The gate.
    private static func gate(
        over log: TrainingLog, holdingRead read: Int
    ) -> GatedWorkoutRepository {
        GatedWorkoutRepository(wrapping: log.repositories.workouts, holdingRead: read)
    }

    /// The state under test, reading sessions through `workouts` and everything else through `log`.
    ///
    /// - Parameters:
    ///   - log: The store.
    ///   - workouts: The workout repository to interpose.
    /// - Returns: A fresh state.
    private static func state(
        over log: TrainingLog, workouts: any WorkoutRepository
    ) -> SessionListState {
        SessionListState(
            workouts: workouts,
            exercises: log.repositories.exercises,
            settings: log.repositories.settings
        )
    }

    /// `count` sessions, one exercise and one working set in each, one day apart.
    ///
    /// - Parameter count: How many to write.
    /// - Returns: The store.
    private static func history(sessions count: Int) async throws -> TrainingLog {
        var log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for day in 0..<count {
            let session = try await log.session(daysAgo: day)
            let entry = try await log.entry(squat, in: session)
            try await log.set(in: entry, kilograms: 100, reps: 5)
        }
        return log
    }
}
