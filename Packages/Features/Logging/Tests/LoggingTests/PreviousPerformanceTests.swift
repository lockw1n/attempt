import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.2.10`: what each exercise looked like the last time it was trained, and which session
/// "last" means.
///
/// The ordering is `TR-0.2.8`'s `(session date, entry order, set order)` chronology, reused rather
/// than re-invented — so the cases below are mostly about which session wins, not about rendering.
@Suite("Previous performance")
struct PreviousPerformanceTests {
    // MARK: - Which session is "last time" (FR-1.2.10)

    @Test("The strip shows the most recent past session, not the first one")
    func mostRecentPastSessionWins() async throws {
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(3), exercise: workout.squat.id, kilos: 100, in: workout.repositories)
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.squat.id, kilos: 105, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let card = try #require(workout.store.exercises.first)
        let performance = try #require(workout.store.previous.byEntryID[card.id])
        #expect(performance.date == .weeksAgo(1))
        #expect(performance.workingSets.map(\.weight) == [Weight(grams: 105_000)])
    }

    @Test("A backdated workout compares against what came before it, not against what came after")
    func backdatedWorkoutLooksBackFromItsOwnDay() async throws {
        // The whole reason the walk is the repository's own newest-first order rather than "the
        // latest session that is not this one": a workout entered for a day two weeks ago is being
        // logged *into that day*, and last week's training is not what preceded it.
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await Workout.seed(into: repositories)
        try await History.workout(
            on: .weeksAgo(3), exercise: catalogue[0].id, kilos: 100, in: repositories)
        try await History.workout(
            on: .weeksAgo(1), exercise: catalogue[0].id, kilos: 105, in: repositories)
        let store = ActiveSessionStore(
            repository: repositories.workouts,
            catalogue: repositories.exercises,
            settings: repositories.settings)
        await store.start(on: .weeksAgo(2))
        await store.addExercise(id: catalogue[0].id)

        await store.loadPreviousPerformances()

        let card = try #require(store.exercises.first)
        #expect(store.previous.byEntryID[card.id]?.date == .weeksAgo(3))
    }

    @Test("An exercise performed twice in one past session shows the later of the two")
    func theLastEntryOfASessionWins() async throws {
        let workout = try await Workout.started()
        let past = try await History.session(on: .weeksAgo(1), in: workout.repositories)
        try await History.entry(
            for: workout.squat.id, in: past, order: 0, kilos: 100, in: workout.repositories)
        try await History.entry(
            for: workout.squat.id, in: past, order: 1, kilos: 60, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let card = try #require(workout.store.exercises.first)
        let performance = try #require(workout.store.previous.byEntryID[card.id])
        #expect(performance.workingSets.map(\.weight) == [Weight(grams: 60_000)])
    }

    @Test("The same exercise twice in this workout gives both cards the same previous session")
    func twoCardsForOneExerciseAgree() async throws {
        // Keyed on the entry rather than the exercise, which is what makes this answerable at all:
        // two cards, one history.
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.squat.id, kilos: 105, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let cards = workout.store.exercises.map(\.id)
        #expect(cards.count == 2)
        #expect(workout.store.previous.byEntryID.count == 2)
        #expect(
            cards.compactMap { workout.store.previous.byEntryID[$0]?.date } == [
                .weeksAgo(1), .weeksAgo(1),
            ])
    }

    @Test("What is logged into this workout is not what it compares itself against")
    func theWorkoutInProgressIsExcluded() async throws {
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.squat.id, kilos: 105, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)
        let card = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: card.id,
            values: SetEntryValues(weight: Weight(grams: 200_000), reps: 1, rpe: nil, isWarmup: false)
        )

        await workout.store.loadPreviousPerformances()

        #expect(
            workout.store.previous.byEntryID[card.id]?.workingSets.map(\.weight)
                == [Weight(grams: 105_000)])
    }

    // MARK: - What the card makes of it (FR-1.2.10, FR-1.13.3)

    @Test("An exercise never trained before has no previous session, and says so")
    func firstTimeEverIsInsufficientData() async throws {
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.bench.id, kilos: 80, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let card = try #require(workout.store.exercises.first)
        #expect(workout.store.previous.byEntryID[card.id] == nil)
        #expect(workout.store.previous.state(forEntryID: card.id) == .noneYet)
    }

    @Test("Before anything has looked, a card knows it does not know")
    func nothingLookedYetIsUnknown() {
        // The distinction the strip is built on: an exercise never trained and one nothing has read
        // are both a miss in the dictionary, and drawing the first for the second is a claim.
        #expect(PreviousPerformances().state(forEntryID: UUID()) == .unknown)
    }

    @Test("A previous session with nothing but warmups in it is no previous performance")
    func warmupsOnlyIsNotAPerformance() async throws {
        // A strip naming a date with nothing under it is the blank area FR-1.2.10 is served by the
        // insufficient-data state instead of.
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1),
            exercise: workout.squat.id,
            kilos: 60,
            sets: [true],
            in: workout.repositories
        )
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let card = try #require(workout.store.exercises.first)
        #expect(workout.store.previous.byEntryID[card.id]?.sets.count == 1)
        #expect(workout.store.previous.state(forEntryID: card.id) == .noneYet)
    }

    @Test("The strip carries the warmups it does not draw")
    func warmupsAreCarriedButNotCompared() async throws {
        let workout = try await Workout.started()
        let past = try await History.session(on: .weeksAgo(1), in: workout.repositories)
        try await History.entry(
            for: workout.squat.id,
            in: past,
            order: 0,
            kilos: 100,
            sets: [true, false],
            in: workout.repositories
        )
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.loadPreviousPerformances()

        let card = try #require(workout.store.exercises.first)
        let performance = try #require(workout.store.previous.byEntryID[card.id])
        // Both halves: what was logged is kept, and what is compared is the work.
        #expect(performance.sets.count == 2)
        #expect(performance.workingSets.count == 1)
        #expect(workout.store.previous.state(forEntryID: card.id) == .performed(performance))
    }

    // MARK: - When it is read, and when it fails

    @Test("An exercise added mid-workout arrives with its previous session already read")
    func addingAnExerciseReadsItsStrip() async throws {
        // The one write that can leave a card with no strip behind it. The screen's `.task` has
        // long since run by the time the chooser pops.
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.bench.id, kilos: 80, in: workout.repositories)

        await workout.store.addExercise(id: workout.bench.id)

        let card = try #require(workout.store.exercises.first)
        #expect(workout.store.previous.byEntryID[card.id]?.date == .weeksAgo(1))
    }

    @Test("A history that cannot be read leaves every card unknown, and reports once")
    func failedReadIsReportedOnce() async throws {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await Workout.seed(into: repositories)
        let store = ActiveSessionStore(
            repository: repositories.workouts,
            catalogue: repositories.exercises,
            settings: repositories.settings)
        await store.start(on: .now)
        await store.addExercise(id: catalogue[0].id)
        let card = try #require(store.exercises.first)

        let failing = ActiveSessionStore(
            repository: UnreadableHistory(base: repositories.workouts, error: failure),
            catalogue: repositories.exercises,
            settings: repositories.settings)
        let session = try #require(store.session)
        await failing.adopt(sessionID: session.id)
        await failing.loadExercises()
        await failing.loadPreviousPerformances()

        #expect(failing.previous.readFailure == String(describing: failure))
        // Not "never trained": the cards must not claim a history they could not read.
        #expect(failing.previous.state(forEntryID: card.id) == .unknown)
        #expect(failing.exercises.count == 1)
    }

    @Test("Leaving one workout for another drops the strips with it")
    func adoptingAnotherWorkoutForgetsTheStrips() async throws {
        let workout = try await Workout.started()
        try await History.workout(
            on: .weeksAgo(1), exercise: workout.squat.id, kilos: 105, in: workout.repositories)
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.loadPreviousPerformances()
        try #require(!workout.store.previous.byEntryID.isEmpty)

        await workout.store.discard()

        #expect(workout.store.previous == PreviousPerformances())
        #expect(!workout.store.previous.hasLoaded)
    }

    @Test("A workout with nothing in it has been read and has nothing to show")
    func emptyWorkoutIsReadRatherThanUnread() async throws {
        let workout = try await Workout.started()

        await workout.store.loadPreviousPerformances()

        #expect(workout.store.previous.hasLoaded)
        #expect(workout.store.previous.byEntryID.isEmpty)
        #expect(workout.store.previous.readFailure == nil)
    }
}

/// Sessions logged before the one in progress — what `FR-1.2.10` reads back.
enum History {
    /// One past workout with one exercise in it.
    ///
    /// - Parameters:
    ///   - day: The training day.
    ///   - exercise: The catalogue row performed.
    ///   - kilos: The load, in whole kilograms.
    ///   - sets: One flag per set logged — `true` for a warmup. One working set by default.
    ///   - repositories: Where it is written.
    static func workout(
        on day: Date,
        exercise: UUID,
        kilos: Int,
        sets: [Bool] = [false],
        in repositories: InMemoryRepositoryStack
    ) async throws {
        let session = try await session(on: day, in: repositories)
        try await entry(
            for: exercise, in: session, order: 0, kilos: kilos, sets: sets, in: repositories)
    }

    /// One finished past session, with nothing in it yet.
    ///
    /// Finished, which is what makes it a *past* session: nothing would resume it.
    ///
    /// - Parameters:
    ///   - day: The training day.
    ///   - repositories: Where it is written.
    /// - Returns: The session.
    @discardableResult
    static func session(
        on day: Date,
        in repositories: InMemoryRepositoryStack
    ) async throws -> WorkoutSession {
        let session = WorkoutSession(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            date: day,
            startedAt: day,
            endedAt: day.addingTimeInterval(3600),
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        return session
    }

    /// One exercise performed in a past session, with a single set logged against it.
    ///
    /// - Parameters:
    ///   - exercise: The catalogue row performed.
    ///   - session: The workout it was performed in.
    ///   - order: Its place in that workout.
    ///   - kilos: The load, in whole kilograms.
    ///   - sets: One flag per set logged — `true` for a warmup. An entry of nothing but warmups is
    ///     a ramp and no performance, which is one of the cases above.
    ///   - repositories: Where it is written.
    static func entry(
        for exercise: UUID,
        in session: WorkoutSession,
        order: Int,
        kilos: Int,
        sets: [Bool] = [false],
        in repositories: InMemoryRepositoryStack
    ) async throws {
        let day = session.date
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise,
            order: order,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        for (position, isWarmup) in sets.enumerated() {
            try await repositories.workouts.save(
                SetEntry(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    entryID: entry.id,
                    order: position,
                    weight: Weight(grams: kilos * 1_000),
                    reps: 5,
                    rpe: nil,
                    rir: nil,
                    isWarmup: isWarmup,
                    isCompleted: true,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: day
                ))
        }
    }
}

/// A repository that answers everything but the list of sessions, which it refuses.
///
/// The one failure this suite needs and a faithful fake will not produce: the workout in progress
/// still reads, so the cards are on screen when the history behind them is not.
actor UnreadableHistory: WorkoutRepository {
    private let base: any WorkoutRepository
    private let error: RepositoryError

    init(base: any WorkoutRepository, error: RepositoryError) {
        self.base = base
        self.error = error
    }

    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw error
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await base.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws { try await base.save(session) }

    func deleteSession(id: UUID) async throws { try await base.deleteSession(id: id) }

    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await base.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws { try await base.save(entry) }

    func deleteExerciseEntry(id: UUID) async throws { try await base.deleteExerciseEntry(id: id) }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await base.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func save(_ set: SetEntry) async throws { try await base.save(set) }

    func deleteSet(id: UUID) async throws { try await base.deleteSet(id: id) }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await base.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

extension Date {
    /// A fixed training day, so a comparison in these tests is between two constants.
    fileprivate static func weeksAgo(_ weeks: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 - Double(weeks) * 604_800)
    }
}
