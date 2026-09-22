import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.5`'s weeks and `FR-1.13.2`'s first launch — the one read that answers both — and
/// `FR-18.9.3`'s change, which is measured between the last two completed weeks and never against
/// the one in progress.
///
/// **Every total here is worked out by hand and written as a literal**, rather than compared against
/// a second computation: a test asserting `state.weeks?.thisWeek.tonnage == Tonnage.of(sets)` passes
/// for any arithmetic both sides share, including none.
///
/// **The weeks are Monday-first unless a test says otherwise**, because `firstWeekday` is the one
/// thing a locale can change about a calendar week, and a test pinned to the machine's would move
/// with it. ``fixtureNow`` is Tuesday 14 November 2023, 22:13 UTC: Monday-first, this week is
/// 13–19 November, last week 6–12, the week before 30 October–5 November.
@MainActor
@Suite("Week summary")
struct WeekSummaryStateTests {
    /// A calendar pinned to GMT and to Monday, so a week's boundaries do not move with the machine
    /// running this.
    static func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// A state over `fixture`, told that "now" is `now` and the week starts on `firstWeekday`.
    static func state(
        _ fixture: DashboardFixture, now: Date = fixtureNow, firstWeekday: Int = 2
    ) -> WeekSummaryState {
        WeekSummaryState(
            workouts: fixture.repositories.workouts,
            calendar: calendar(firstWeekday: firstWeekday),
            now: { now })
    }

    /// Monday 13 November 2023, 08:53 UTC — the first day of ``fixtureNow``'s Monday-first week,
    /// with nothing trained in it yet.
    static let monday = Date(timeIntervalSince1970: 1_699_866_000)

    /// Three weeks with nothing in them.
    static let nothing = WeekSummaries(thisWeek: .empty, lastWeek: .empty, weekBefore: .empty)

    @Test("An install with nothing in it is FR-1.13.2's first launch")
    func firstLaunch() async throws {
        let fixture = DashboardFixture()
        try await fixture.exercise(named: "Back Squat")
        let state = Self.state(fixture)

        await state.load()

        // A seeded catalogue is not history: the question is whether a session was ever logged.
        #expect(state.hasEverTrained == false)
        #expect(state.hasLoaded)
        #expect(state.failure == nil)
        #expect(state.weeks == Self.nothing)
        #expect(DashboardScreenState.current(state) == .firstLaunch)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
    }

    @Test("A hand-computed week: 5×100 + 3×120 is 860 kg over one workout")
    func handComputed() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // 500 + 360. Two different loads at two different rep counts, so a transposed multiply does
        // not land on the same total.
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5), LoggedSet(grams: 120_000, reps: 3)])
            ])
        let state = Self.state(fixture)

        await state.load()

        let expected = WeekSummaries(
            thisWeek: WeekSummary(workoutCount: 1, tonnage: Weight(grams: 860_000)),
            lastWeek: .empty,
            weekBefore: .empty)
        #expect(state.weeks == expected)
        #expect(state.hasEverTrained)
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(WeekSummaryScreenState.current(state) == .ready(expected))
    }

    @Test("Last week's training is its own line, not this week's volume")
    func lastWeekIsItsOwnLine() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        // The two halves of the one read disagreeing is the whole point of folding them together:
        // there IS history, and this week holds none of it. Since FR-18.9.2 that history is drawn,
        // so the card is not quiet.
        #expect(state.hasEverTrained)
        #expect(state.weeks?.thisWeek == .empty)
        #expect(state.weeks?.lastWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(WeekSummaryScreenState.current(state) != .quiet)
    }

    @Test("A backdated session is weighed into the week it was trained, not the week it was entered")
    func backdatingDecidesTheWeek() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        // `FR-1.2.1`'s backdate: trained last week, typed in today. This is the only fixture shape
        // that can tell `session.date` from `session.createdAt` — every other session here writes
        // one value into both, so a read of the wrong column passes them all.
        try await fixture.session(
            on: weeksAgo(1),
            enteredOn: fixtureNow,
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        // Trained this week, and the only thing that may be counted here. Present so the assertion
        // is a real total rather than a zero every broken reading also produces.
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 120_000, reps: 3)])])
        let state = Self.state(fixture)

        await state.load()

        // 360 this week, not 860: reading `createdAt` would pull last week's 500 into it.
        #expect(state.weeks?.thisWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 360_000)))
        #expect(state.weeks?.lastWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
    }

    @Test("Two sessions this week are two workouts, summed")
    func twoSessions() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: fixtureNow.addingTimeInterval(-86_400),
            exercises: [(squat, [LoggedSet(grams: 80_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        // 500 + 400.
        #expect(state.weeks?.thisWeek == WeekSummary(workoutCount: 2, tonnage: Weight(grams: 900_000)))
    }

    @Test("A workout still in progress counts as this week's")
    func openSessionCounts() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow,
            isFinished: false,
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let state = Self.state(fixture)

        await state.load()

        #expect(state.weeks?.thisWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))
    }

    @Test("A session with only warmups and failures is not a workout")
    func nothingPerformed() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (
                    squat,
                    [
                        LoggedSet(grams: 60_000, reps: 5, isWarmup: true),
                        LoggedSet(grams: 100_000, reps: 8, isCompleted: false),
                    ]
                )
            ])
        let state = Self.state(fixture)

        await state.load()

        // A session opened and not trained in raises neither number — the count is drawn from the
        // same population as the volume.
        #expect(state.weeks == Self.nothing)
        #expect(state.hasEverTrained)
        #expect(WeekSummaryScreenState.current(state) == .quiet)
    }

    @Test("A week of bodyweight work is a workout with no volume, not a zero")
    func unweighable() async throws {
        let fixture = DashboardFixture()
        let pullUp = try await fixture.exercise(named: "Pull-Up")
        try await fixture.session(
            on: fixtureNow,
            exercises: [
                (
                    pullUp,
                    [LoggedSet(grams: 0, reps: 10), LoggedSet(grams: -20_000, reps: 8)]
                )
            ])
        let state = Self.state(fixture)

        await state.load()

        // FR-1.13.3: the workout happened and its volume is not zero, it is unweighable. The two
        // read differently and the line says so.
        let weeks = try #require(state.weeks)
        #expect(weeks.thisWeek == WeekSummary(workoutCount: 1, tonnage: .zero))
        #expect(WeekSummaryScreenState.current(state) == .ready(weeks))
        #expect(WeekLines(weeks).thisWeek.reading == .unweighed(workouts: 1))
    }

    // MARK: - Loading and failure

    @Test("A read that fails says so, and is not read as a first launch")
    func failedRead() async {
        let state = WeekSummaryState(
            workouts: FailingWorkoutRepository(), calendar: Self.calendar(), now: { fixtureNow })

        await state.load()

        #expect(state.failure != nil)
        #expect(state.hasLoaded)
        #expect(state.weeks == nil)
        // The failure says nothing about whether anything was ever logged, so the sections draw and
        // each reports its own — a screen that read this as an empty install would replace three
        // readable cards with a welcome message.
        #expect(DashboardScreenState.current(state) == .sections)
        #expect(WeekSummaryScreenState.current(state) == .failed)
    }

    @Test("Before the read answers, the sections draw and the summary is loading")
    func beforeLoading() {
        let state = Self.state(DashboardFixture())

        #expect(state.hasLoaded == false)
        #expect(WeekSummaryScreenState.current(state) == .loading)
        // Not `.firstLaunch`: nothing has been read, so nothing is known about the install yet, and
        // a welcome message shown while the store is still answering would flash on every launch.
        #expect(DashboardScreenState.current(state) == .sections)
    }

    @Test("A failure outranks the weeks already on screen")
    func failureOutranksStaleWeeks() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat")
        try await fixture.session(
            on: fixtureNow, exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let switchable = SwitchableWorkouts(wrapping: fixture.repositories.workouts)
        let state = WeekSummaryState(
            workouts: switchable, calendar: Self.calendar(), now: { fixtureNow })
        await state.load()
        #expect(state.weeks?.thisWeek == WeekSummary(workoutCount: 1, tonnage: Weight(grams: 500_000)))

        await switchable.refuse()
        await state.load()

        #expect(state.weeks != nil, "the previous answer is still held")
        #expect(WeekSummaryScreenState.current(state) == .failed)
    }
}
