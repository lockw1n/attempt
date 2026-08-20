import ExerciseLibrary
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

/// `FR-1.1.2`'s recency filter: what "recently used" means, and what the control does when it
/// cannot be answered.
@Suite("Exercise recency filter")
struct ExerciseRecencyTests {
    @Test("An exercise trained inside the window is recent, and the filter narrows to it")
    func recentExerciseIsOffered() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 3)

        let state = gym.listState()
        await state.load()

        #expect(state.isRecencyFilterAvailable == true)
        #expect(state.recentExerciseIDs == [gym.squat.id])
        #expect(state.names.count == 3)

        state.showsRecentOnly = true
        #expect(state.names == ["Back Squat"])
    }

    @Test("A session outside the window is not recent, and the chip goes back to being unavailable")
    func oldSessionIsNotRecent() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 45)

        let state = gym.listState()
        await state.load()

        #expect(state.recentExerciseIDs == [])
        #expect(state.isRecencyFilterAvailable == false)
    }

    @Test("The window's far edge is inside it, and a day past it is not")
    func windowEdges() async throws {
        let inside = try await Gym.seeded()
        try await inside.train(inside.squat, daysAgo: ExerciseListState.recencyWindowInDays - 1)
        let outside = try await Gym.seeded()
        try await outside.train(outside.squat, daysAgo: ExerciseListState.recencyWindowInDays + 1)

        let recent = inside.listState()
        await recent.load()
        let stale = outside.listState()
        await stale.load()

        #expect(recent.recentExerciseIDs == [inside.squat.id])
        #expect(stale.recentExerciseIDs == [])
    }

    @Test("Only the exercises actually trained are recent, not everything in a recent session")
    func onlyTrainedExercisesAreRecent() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 1)
        try await gym.train(gym.bench, daysAgo: 2)

        let state = gym.listState()
        await state.load()
        state.showsRecentOnly = true

        #expect(state.recentExerciseIDs == [gym.squat.id, gym.bench.id])
        #expect(state.names == ["Back Squat", "Bench Press"])
    }

    @Test("Recency is one of FR-1.1.2's filters, so clearing the filters turns it off")
    func clearFiltersClearsRecency() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 1)
        let state = gym.listState()
        await state.load()
        state.showsRecentOnly = true
        #expect(state.names == ["Back Squat"])

        state.clearFilters()

        #expect(state.showsRecentOnly == false)
        #expect(state.names.count == 3)
    }

    @Test("A workout read that fails disables the filter rather than taking the catalogue down")
    func failedRecencyReadKeepsTheList() async throws {
        let gym = try await Gym.seeded()
        let state = ExerciseListState(
            repository: gym.repositories.exercises,
            workouts: FailingWorkoutRepository()
        )

        await state.load()

        #expect(state.names.count == 3)
        #expect(state.recentExerciseIDs == nil)
        #expect(state.isRecencyFilterAvailable == false)
    }

    @Test("A filter in force is turned off by a read that fails, not left narrowing silently")
    func failedReadRetiresTheFilter() async throws {
        let gym = try await Gym.seeded()
        try await gym.train(gym.squat, daysAgo: 1)
        let state = gym.listState()
        await state.load()
        state.showsRecentOnly = true

        let broken = ExerciseListState(
            repository: gym.repositories.exercises,
            workouts: FailingWorkoutRepository()
        )
        broken.showsRecentOnly = true
        await broken.load()

        #expect(state.showsRecentOnly == true)
        #expect(broken.showsRecentOnly == false)
        #expect(broken.names.count == 3)
    }
}

/// A catalogue of three exercises and a place to have trained some of them.
private struct Gym {
    let repositories: InMemoryRepositoryStack
    let squat: Exercise
    let bench: Exercise
    let deadlift: Exercise

    /// Three exercises in the catalogue and nothing logged.
    static func seeded() async throws -> Gym {
        let repositories = InMemoryRepositoryStack()
        let catalogue = [
            Fixtures.exercise(name: "Back Squat", movement: .squat),
            Fixtures.exercise(name: "Bench Press", movement: .bench),
            Fixtures.exercise(name: "Deadlift", movement: .deadlift),
        ]
        for exercise in catalogue {
            try await repositories.exercises.save(exercise)
        }
        return Gym(
            repositories: repositories,
            squat: catalogue[0],
            bench: catalogue[1],
            deadlift: catalogue[2]
        )
    }

    /// Logs a session `daysAgo` days back with one exercise in it.
    ///
    /// The session is dated rather than the entry: `FR-1.1.2`'s window is over training days, and
    /// the entry carries no date of its own.
    func train(_ exercise: Exercise, daysAgo: Int) async throws {
        let day =
            Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let session = WorkoutSession(
            id: UUID(),
            createdAt: day,
            updatedAt: day,
            deletedAt: nil,
            date: day,
            startedAt: day,
            endedAt: day,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        try await repositories.workouts.save(
            ExerciseEntry(
                id: UUID(),
                createdAt: day,
                updatedAt: day,
                deletedAt: nil,
                sessionID: session.id,
                exerciseID: exercise.id,
                order: 0,
                notes: ""
            )
        )
    }

    /// A list state over this gym's two repositories.
    func listState() -> ExerciseListState {
        ExerciseListState(repository: repositories.exercises, workouts: repositories.workouts)
    }
}

/// A ``WorkoutRepository`` whose every read fails — the in-memory fake cannot be made to throw, and
/// a failed recency read is a state this screen has to survive.
///
/// The writes are unreachable from the list screen and throw the same error rather than pretending
/// to land, which is what keeps a future caller from mistaking this for a working store.
private struct FailingWorkoutRepository: WorkoutRepository {
    /// What every call raises.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] { throw failure }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }
    func save(_ session: WorkoutSession) async throws { throw failure }
    func deleteSession(id: UUID) async throws { throw failure }
    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { throw failure }
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
