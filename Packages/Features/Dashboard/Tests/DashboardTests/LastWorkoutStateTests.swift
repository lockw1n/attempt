import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Dashboard

/// `FR-1.9.2`: which workout the card reports, what it says about it, and which of the two actions
/// applies.
@MainActor
@Suite("Dashboard last workout")
struct LastWorkoutStateTests {
    @Test("The most recent finished workout is the one reported")
    func themostRecentFinishedWorkoutIsReported() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.session(
            on: weeksAgo(4), exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        let recent = try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 110_000, reps: 5)])])

        let state = card(over: fixture)
        await state.load()

        #expect(state.summary?.sessionID == recent)
        #expect(state.summary?.date == weeksAgo(1))
        #expect(state.summary?.isInProgress == false)
        #expect(LastWorkoutScreenState.current(state) == .finished(try #require(state.summary)))
    }

    /// The same rule `ActiveSessionStore.resume()` applies, and for its reason: an older backdated
    /// session left open is still the workout in progress, so offering "repeat" beside it would put
    /// two workouts in progress at once.
    @Test("An open workout outranks a newer finished one")
    func anopenWorkoutOutranksANewerFinishedOne() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let open = try await fixture.session(
            on: weeksAgo(4),
            isFinished: false,
            exercises: [(squat, [LoggedSet(grams: 100_000, reps: 5)])])
        try await fixture.session(
            on: weeksAgo(1), exercises: [(squat, [LoggedSet(grams: 110_000, reps: 5)])])

        let state = card(over: fixture)
        await state.load()

        #expect(state.summary?.sessionID == open)
        #expect(state.summary?.isInProgress == true)
        #expect(LastWorkoutScreenState.current(state) == .inProgress(try #require(state.summary)))
    }

    /// `G-1.8`'s two flags are what make this a count of work rather than of rows.
    @Test("Warmups and unfinished sets are not working sets")
    func warmupsAndUnfinishedSetsAreNotWorkingSets() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        try await fixture.session(
            on: weeksAgo(1),
            exercises: [
                (
                    squat,
                    [
                        LoggedSet(grams: 60_000, reps: 5, isWarmup: true),
                        LoggedSet(grams: 100_000, reps: 5),
                        LoggedSet(grams: 100_000, reps: 5),
                        LoggedSet(grams: 100_000, reps: 3, isCompleted: false),
                    ]
                )
            ])

        let state = card(over: fixture)
        await state.load()

        #expect(state.summary?.workingSetCount == 2)
    }

    @Test("An exercise trained twice is named once, in the order it was performed")
    func anexerciseTrainedTwiceIsNamedOnce() async throws {
        let fixture = DashboardFixture()
        let squat = try await fixture.exercise(named: "Back Squat", movement: .squat)
        let bench = try await fixture.exercise(named: "Bench Press", movement: .bench)
        try await fixture.session(
            on: weeksAgo(1),
            exercises: [
                (squat, [LoggedSet(grams: 100_000, reps: 5)]),
                (bench, [LoggedSet(grams: 80_000, reps: 5)]),
                (squat, [LoggedSet(grams: 80_000, reps: 8)]),
            ])

        let state = card(over: fixture)
        await state.load()

        #expect(state.summary?.exerciseNames == ["Back Squat", "Bench Press"])
    }

    @Test("Nothing logged is the empty state")
    func nothingLoggedIsTheEmptyState() async {
        let state = card(over: DashboardFixture())
        #expect(LastWorkoutScreenState.current(state) == .loading)

        await state.load()
        #expect(state.summary == nil)
        #expect(LastWorkoutScreenState.current(state) == .nothingLogged)
    }

    @Test("A failed read is the error state")
    func afailedReadIsTheErrorState() async {
        let fixture = DashboardFixture()
        let state = LastWorkoutState(
            workouts: FailingWorkoutRepository(), catalogue: fixture.repositories.exercises)
        await state.load()

        #expect(LastWorkoutScreenState.current(state) == .failed)
    }

    @Test("A repeat that started nothing is reported; one that started is not")
    func arepeatThatStartedNothingIsReported() async {
        let state = card(over: DashboardFixture())

        state.repeatDidFinish(started: false)
        #expect(state.repeatDidFail)

        state.repeatDidFinish(started: true)
        #expect(!state.repeatDidFail)
    }

    // MARK: - Fixtures

    private func card(over fixture: DashboardFixture) -> LastWorkoutState {
        LastWorkoutState(
            workouts: fixture.repositories.workouts, catalogue: fixture.repositories.exercises)
    }
}
