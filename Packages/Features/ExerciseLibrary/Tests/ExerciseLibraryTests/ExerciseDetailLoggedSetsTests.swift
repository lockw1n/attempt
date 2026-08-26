import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What the three derived sections are allowed to say, and when (`FR-1.1.6`, `FR-1.13.3`).
///
/// **The copy behind them is conditioned on a fact, not on the build.** "Log a set against this
/// exercise and its history appears here" is true only while no set can exist; the moment one can,
/// a user who has logged sets would be told to log a set they have already logged. That is what
/// ``ExerciseDetail/hasLoggedSets`` carries, and it is the half of the problem that is answerable
/// here — *which* sentence the non-empty branch shows is the display's own, and the estimate's is
/// not a set-count question at all.
@Suite("Exercise detail: logged sets")
struct ExerciseDetailLoggedSetsTests {
    @Test("An exercise nothing has been logged against reports no sets")
    func noSetsLogged() async throws {
        let repositories = InMemoryRepositoryStack()
        let exercise = try await seedExercise(into: repositories)
        let state = ExerciseDetailState(
            exerciseID: exercise.id,
            repository: repositories.exercises,
            // The same stack, not a fresh one: this suite is the one where the workout store is
            // the subject rather than a dependency, so it has to be the store the sets are in.
            workouts: repositories.workouts
        )

        await state.load()

        #expect(state.detail?.hasLoggedSets == false)
    }

    @Test("One logged set is enough, whatever kind of set it was")
    func aSetIsASet() async throws {
        let repositories = InMemoryRepositoryStack()
        let exercise = try await seedExercise(into: repositories)
        // A warmup, and an incomplete one at that: the sections behind this flag are about whether
        // there is anything to show, not about whether it produces an estimate.
        try await logSet(against: exercise, into: repositories, isWarmup: true, isCompleted: false)
        let state = ExerciseDetailState(
            exerciseID: exercise.id,
            repository: repositories.exercises,
            // The same stack, not a fresh one: this suite is the one where the workout store is
            // the subject rather than a dependency, so it has to be the store the sets are in.
            workouts: repositories.workouts
        )

        await state.load()

        #expect(state.detail?.hasLoggedSets == true)
    }

    @Test("A set logged against another exercise is not this one's")
    func setsAreNotShared() async throws {
        let repositories = InMemoryRepositoryStack()
        let exercise = try await seedExercise(into: repositories)
        let other = try await seedExercise(into: repositories, name: "Bench Press")
        try await logSet(against: other, into: repositories, isWarmup: false, isCompleted: true)
        let state = ExerciseDetailState(
            exerciseID: exercise.id,
            repository: repositories.exercises,
            // The same stack, not a fresh one: this suite is the one where the workout store is
            // the subject rather than a dependency, so it has to be the store the sets are in.
            workouts: repositories.workouts
        )

        await state.load()

        #expect(state.detail?.hasLoggedSets == false)
    }

    @Test("A workout store that cannot answer costs the screen the sentence, not the exercise")
    func aFailedSetReadDoesNotFailTheScreen() async throws {
        let repositories = InMemoryRepositoryStack()
        let exercise = try await seedExercise(into: repositories)
        let state = ExerciseDetailState(
            exerciseID: exercise.id,
            repository: repositories.exercises,
            workouts: RefusingWorkoutRepository()
        )

        await state.load()

        // The exercise's own fields came from the catalogue and are unaffected: a fault in a store
        // this screen reads one count from must not hide the movement, equipment and notes.
        #expect(state.detail?.exercise.name == "Back Squat")
        #expect(state.detail?.hasLoggedSets == false)
    }

    /// Puts one exercise in the catalogue.
    private func seedExercise(
        into repositories: InMemoryRepositoryStack,
        name: String = "Back Squat"
    ) async throws -> Exercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let exercise = Exercise(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
        try await repositories.exercises.save(exercise)
        return exercise
    }

    /// Logs one set against `exercise`, session and entry included — the three writes a set needs.
    private func logSet(
        against exercise: Exercise,
        into repositories: InMemoryRepositoryStack,
        isWarmup: Bool,
        isCompleted: Bool
    ) async throws {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            date: stamp,
            startedAt: stamp,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await repositories.workouts.save(session)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise.id,
            order: 0,
            notes: ""
        )
        try await repositories.workouts.save(entry)
        try await repositories.workouts.save(
            SetEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                entryID: entry.id,
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
        )
    }
}

/// A `WorkoutRepository` that refuses everything.
///
/// The detail screen makes exactly one call into this store, and this fake exists to fail it — the
/// faithful fake in `RepositoryFakes` will not.
private actor RefusingWorkoutRepository: WorkoutRepository {
    private var refusal: RepositoryError { .recordNotFound(id: UUID()) }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw refusal
    }

    func sessions(in range: ClosedRange<Date>, includingDeleted: Bool) async throws -> [WorkoutSession] {
        throw refusal
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw refusal }

    func save(_ session: WorkoutSession) async throws { throw refusal }

    func deleteSession(id: UUID) async throws { throw refusal }

    func entries(forSessionID sessionID: UUID, includingDeleted: Bool) async throws -> [ExerciseEntry] {
        throw refusal
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw refusal }

    func save(_ entry: ExerciseEntry) async throws { throw refusal }

    func deleteExerciseEntry(id: UUID) async throws { throw refusal }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw refusal
    }

    func save(_ set: SetEntry) async throws { throw refusal }

    func deleteSet(id: UUID) async throws { throw refusal }
}
