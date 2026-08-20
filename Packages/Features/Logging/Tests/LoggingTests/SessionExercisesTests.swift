import Foundation
import Logging
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

/// The workout's exercises: adding one, reordering them, and what the cards make of the result
/// (`FR-1.2.2`, `FR-1.2.13`, `NFR-1.8`, `G-2.4`).
@Suite("Session exercises")
struct SessionExercisesTests {
    // MARK: - Adding (FR-1.2.2, FR-1.2.13, NFR-1.8)

    @Test("An added exercise is written through and comes back joined to its catalogue row")
    func addWritesThrough() async throws {
        let workout = try await Workout.started()

        await workout.store.addExercise(id: workout.squat.id)

        let held = try #require(workout.store.exercises.first)
        #expect(workout.store.exercises.count == 1)
        #expect(held.exercise?.name == "Back Squat")
        #expect(held.sets.isEmpty)
        #expect(workout.store.exercisesWriteFailure == nil)
        // NFR-1.8's claim: the entry is in the store, not only in the list on screen.
        let session = try #require(workout.store.session)
        let stored = try await workout.repositories.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        #expect(stored.map(\.id) == [held.entry.id])
    }

    @Test("Exercises are appended, never inserted, and numbered from the highest stored order")
    func addAppends() async throws {
        let workout = try await Workout.started()

        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        await workout.store.addExercise(id: workout.deadlift.id)

        #expect(workout.store.exercises.map(\.exercise?.name) == ["Back Squat", "Bench Press", "Deadlift"])
        #expect(workout.store.exercises.map(\.entry.order) == [0, 1, 2])
    }

    @Test("An exercise added without the list having been read still lands at the end")
    func addWithoutHavingLoaded() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        // The chooser is reachable from a restored stack that never drew the workout, so the store
        // can be asked to add with nothing loaded. Measuring the held list there would put every
        // exercise at position zero.
        let cold = ActiveSessionStore(
            repository: workout.repositories.workouts,
            catalogue: workout.repositories.exercises
        )
        await cold.resume()

        await cold.addExercise(id: workout.deadlift.id)

        #expect(cold.exercises.map(\.entry.order) == [0, 1, 2])
        #expect(cold.exercises.last?.exercise?.name == "Deadlift")
    }

    @Test("An order a soft-deleted entry vacated is not handed out again")
    func addNumbersPastADeletedEntry() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        let squat = try #require(workout.store.exercises.first)
        // The list is now two rows at orders 0 and 1. Removing the first leaves one row at order 1,
        // so a position counted from the *count* would collide with it.
        try await workout.repositories.workouts.deleteExerciseEntry(id: squat.entry.id)
        await workout.store.loadExercises()

        await workout.store.addExercise(id: workout.deadlift.id)

        #expect(workout.store.exercises.map(\.entry.order) == [1, 2])
        #expect(workout.store.exercises.map(\.exercise?.name) == ["Bench Press", "Deadlift"])
    }

    @Test("Nothing is added while no workout is in progress")
    func addRefusedWithoutAWorkout() async throws {
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await Workout.seed(into: repositories)
        let store = ActiveSessionStore(
            repository: repositories.workouts, catalogue: repositories.exercises)

        await store.addExercise(id: catalogue[0].id)

        #expect(store.exercises.isEmpty)
        #expect(store.exercisesWriteFailure == nil)
    }

    @Test("An exercise the catalogue does not have is reported as a failed write")
    func addReportsAFailedWrite() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)

        // The repositories refuse a dangling reference, which is the failure this command actually
        // has: the chooser only offers rows it read, so a missing one is a row that went away.
        await workout.store.addExercise(id: UUID())

        let failure = try #require(workout.store.exercisesWriteFailure)
        #expect(failure.contains("danglingReference"))
        // A failed write costs the list nothing — that is the whole reason it is a second
        // diagnostic rather than the read's.
        #expect(workout.store.exercises.map(\.exercise?.name) == ["Back Squat"])
        #expect(workout.store.exercisesReadFailure == nil)
        #expect(workout.store.hasLoadedExercises)
    }

    @Test("A write that lands retires the failure the last one left")
    func aGoodWriteRetiresTheFailure() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: UUID())
        #expect(workout.store.exercisesWriteFailure != nil)

        await workout.store.addExercise(id: workout.squat.id)

        #expect(workout.store.exercisesWriteFailure == nil)
    }

    @Test("A failed read is reported as a read, and costs the list its cards")
    func loadReportsAFailedRead() async throws {
        let session = WorkoutSession.fixture()
        // The scripted repository refuses every entry call, which the faithful fake will not do.
        let store = ActiveSessionStore(
            repository: ScriptedWorkoutRepository(row: session),
            catalogue: InMemoryRepositoryStack().exercises)
        await store.adopt(sessionID: session.id)

        await store.loadExercises()

        #expect(store.exercisesReadFailure != nil)
        #expect(store.exercisesWriteFailure == nil)
        #expect(store.exercises.isEmpty)
        // Read, not still reading: the state that has the retry in it is the one with nothing.
        #expect(store.hasLoadedExercises)
        #expect(store.session == session)
    }

    // MARK: - Reordering (FR-1.2.2, G-2.4)

    @Test("Moving an exercise renumbers the workout and survives a fresh read")
    func moveRenumbers() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        await workout.store.addExercise(id: workout.deadlift.id)

        let deadliftCard = try #require(workout.store.exercises.last)
        await workout.store.moveExercise(id: deadliftCard.id, by: -2)

        #expect(workout.store.exercises.map(\.exercise?.name) == ["Deadlift", "Back Squat", "Bench Press"])
        #expect(workout.store.exercises.map(\.entry.order) == [0, 1, 2])
        // A relaunch reads the order back out of the store rather than out of this list.
        let reopened = ActiveSessionStore(
            repository: workout.repositories.workouts,
            catalogue: workout.repositories.exercises
        )
        await reopened.resume()
        await reopened.loadExercises()
        #expect(reopened.exercises.map(\.exercise?.name) == ["Deadlift", "Back Squat", "Bench Press"])
    }

    @Test("Only the rows whose position actually changed are written")
    func moveWritesOnlyWhatMoved() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        await workout.store.addExercise(id: workout.deadlift.id)
        let before = try await workout.entryTimestamps()

        let squatCard = try #require(workout.store.exercises.first)
        await workout.store.moveExercise(id: squatCard.id, by: 1)

        let after = try await workout.entryTimestamps()
        // Swapping the first two leaves the third where it was — and `updatedAt` is G-2.4's conflict
        // key, so restamping it would let a local no-op outrank a real remote edit.
        let deadlift = try #require(workout.store.exercises.last?.entry.exerciseID)
        #expect(after[deadlift] == before[deadlift])
        #expect(after[workout.squat.id] != before[workout.squat.id])
        #expect(after[workout.bench.id] != before[workout.bench.id])
    }

    @Test("A move of nowhere, off either end, or of an exercise not in the workout, does nothing")
    func moveRefusesNonMoves() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        let cards = workout.store.exercises
        let before = try await workout.entryTimestamps()

        await workout.store.moveExercise(id: cards[0].id, by: 0)
        await workout.store.moveExercise(id: cards[0].id, by: -1)
        await workout.store.moveExercise(id: cards[1].id, by: 1)
        // Not this workout's — the id names an entry, and one from anywhere else is not a position.
        await workout.store.moveExercise(id: UUID(), by: 1)

        #expect(try await workout.entryTimestamps() == before)
        #expect(workout.store.exercises.map(\.entry.order) == [0, 1])
    }

    @Test("Two taps on the same control are two moves, not one")
    func overlappingMovesBothLand() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        await workout.store.addExercise(id: workout.deadlift.id)
        let squatCard = try #require(workout.store.exercises.first)

        // What two taps on **move down** actually are: neither waits for the other, which is what
        // the store's write chain is for. Computed against the list each saw when it was tapped,
        // the second would carry the position the first had just vacated and undo it.
        async let first: Void = workout.store.moveExercise(id: squatCard.id, by: 1)
        async let second: Void = workout.store.moveExercise(id: squatCard.id, by: 1)
        _ = await (first, second)

        #expect(
            workout.store.exercises.map(\.exercise?.name) == ["Bench Press", "Deadlift", "Back Squat"])
        #expect(workout.store.exercises.map(\.entry.order) == [0, 1, 2])
    }

    // MARK: - The list's lifetime

    @Test("Discarding the workout takes its exercises with it")
    func discardForgetsTheExercises() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)

        await workout.store.discard()

        #expect(workout.store.exercises.isEmpty)
        #expect(!workout.store.hasLoadedExercises)
    }

    @Test("Reading the exercises with no workout in progress reports nothing rather than failing")
    func loadWithoutAWorkout() async throws {
        let repositories = InMemoryRepositoryStack()
        _ = try await Workout.seed(into: repositories)
        let store = ActiveSessionStore(
            repository: repositories.workouts, catalogue: repositories.exercises)

        await store.loadExercises()

        #expect(store.exercises.isEmpty)
        #expect(!store.hasLoadedExercises)
        #expect(store.exercisesReadFailure == nil)
    }

    // MARK: - What the cards make of it (FR-1.2.13)

    @Test("An exercise with no working set is unstarted, not complete")
    func emptyExerciseIsNotComplete() {
        #expect(!SessionExercise.fixture(sets: []).isComplete)
        // Warmups are not the work, so an exercise that has only warmed up is still unstarted —
        // and an `allSatisfy` over an empty collection would say the opposite.
        #expect(!SessionExercise.fixture(sets: [.fixture(isWarmup: true, isCompleted: true)]).isComplete)
    }

    @Test("An exercise is complete when every working set is")
    func completedExercise() {
        let done = SessionExercise.fixture(sets: [
            .fixture(isWarmup: true, isCompleted: false),
            .fixture(isWarmup: false, isCompleted: true),
            .fixture(isWarmup: false, isCompleted: true),
        ])
        let partly = SessionExercise.fixture(sets: [
            .fixture(isWarmup: false, isCompleted: true),
            .fixture(isWarmup: false, isCompleted: false),
        ])

        #expect(done.isComplete)
        #expect(!partly.isComplete)
    }

    @Test("Progress counts finished exercises, and an empty workout is zero rather than whole")
    func progress() {
        let complete = SessionExercise.fixture(sets: [.fixture(isWarmup: false, isCompleted: true)])
        let open = SessionExercise.fixture(sets: [])

        #expect(SessionProgress([]).fraction == 0)
        #expect(SessionProgress([]).total == 0)
        #expect(SessionProgress([complete, open, open]).completed == 1)
        #expect(SessionProgress([complete, open, open]).total == 3)
        #expect(SessionProgress([complete, open]).fraction == 0.5)
    }
}

/// A workout in progress over a seeded catalogue — what every test above starts from.
private struct Workout {
    let repositories: InMemoryRepositoryStack
    let store: ActiveSessionStore
    let squat: Exercise
    let bench: Exercise
    let deadlift: Exercise

    /// Seeds three exercises, starts a workout and returns the store holding it.
    static func started() async throws -> Workout {
        let repositories = InMemoryRepositoryStack()
        let catalogue = try await seed(into: repositories)
        let store = ActiveSessionStore(
            repository: repositories.workouts, catalogue: repositories.exercises)
        await store.start(on: .now)
        await store.loadExercises()
        return Workout(
            repositories: repositories,
            store: store,
            squat: catalogue[0],
            bench: catalogue[1],
            deadlift: catalogue[2]
        )
    }

    /// Puts three exercises in the catalogue, in the order the tests name them.
    static func seed(into repositories: InMemoryRepositoryStack) async throws -> [Exercise] {
        let catalogue = [
            Exercise.fixture(name: "Back Squat", movement: .squat),
            Exercise.fixture(name: "Bench Press", movement: .bench),
            Exercise.fixture(name: "Deadlift", movement: .deadlift),
        ]
        for exercise in catalogue {
            try await repositories.exercises.save(exercise)
        }
        return catalogue
    }

    /// Each entry's stored `updatedAt`, keyed on the exercise it names.
    func entryTimestamps() async throws -> [UUID: Date] {
        guard let session = store.session else { return [:] }
        let entries = try await repositories.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.exerciseID, $0.updatedAt) })
    }
}

extension Exercise {
    /// A catalogue row with every field fixed but the two these tests vary.
    fileprivate static func fixture(name: String, movement: Movement) -> Exercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return Exercise(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            movement: movement,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
    }
}

extension SetEntry {
    /// A set with every field fixed but the two completion flags.
    fileprivate static func fixture(isWarmup: Bool, isCompleted: Bool) -> SetEntry {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: UUID(),
            order: 0,
            weight: Weight(grams: 100_000),
            reps: 5,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }
}

extension SessionExercise {
    /// One card's worth of workout, with only its sets varying.
    fileprivate static func fixture(sets: [SetEntry]) -> SessionExercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionExercise(
            entry: ExerciseEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: ""
            ),
            exercise: nil,
            sets: sets
        )
    }
}
