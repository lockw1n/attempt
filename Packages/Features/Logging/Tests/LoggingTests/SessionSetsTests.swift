import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Logging a set against an exercise in the workout (`FR-1.2.3`, `FR-1.2.5`, `FR-1.2.6`,
/// `NFR-1.8`, `G-1.8`, `G-3.1`).
@Suite("Session sets")
struct SessionSetsTests {
    // MARK: - The write (FR-1.2.3, NFR-1.8, G-1.8)

    @Test("A logged set is written through and comes back on its card")
    func addWritesThrough() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        await workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 102_500), reps: 5, rpe: 8, notes: "belt")

        let held = try #require(workout.store.exercises.first?.sets.first)
        #expect(workout.store.exercises.first?.sets.count == 1)
        #expect(held.weight == Weight(grams: 102_500))
        #expect(held.reps == 5)
        #expect(held.rpe == 8)
        #expect(held.notes == "belt")
        #expect(workout.store.exercisesWriteFailure == nil)
        // NFR-1.8's claim: the set is in the store, not only in the list on screen.
        let stored = try await workout.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(stored.map(\.id) == [held.id])
    }

    @Test("A logged set is a performed working set — G-1.8's two flags, decided rather than defaulted")
    func flagsAreDecided() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        await workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 100_000), reps: 5, rpe: nil, notes: "")

        let held = try #require(workout.store.exercises.first?.sets.first)
        #expect(held.isCompleted == true)
        #expect(held.isWarmup == false)
        // Tracked live, which is the only thing that can establish it.
        #expect(held.completedAt != nil)
        // The exercise is therefore finished by FR-1.2.13's rule, which is what the screen has to
        // override for the card being logged into.
        #expect(workout.store.exercises.first?.isComplete == true)
    }

    @Test("Sets are appended in order, and the order is read rather than counted")
    func setsAreAppended() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        for reps in [5, 4, 3] {
            await workout.store.addSet(
                toEntryID: entry.id, weight: Weight(grams: 100_000), reps: reps, rpe: nil, notes: "")
        }

        let sets = try #require(workout.store.exercises.first?.sets)
        #expect(sets.map(\.reps) == [5, 4, 3])
        #expect(sets.map(\.order) == [0, 1, 2])
    }

    @Test("A gap a deleted set left is not filled — the order is read, not counted")
    func orderIsReadRatherThanCounted() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        for reps in [5, 4, 3] {
            await workout.store.addSet(
                toEntryID: entry.id, weight: Weight(grams: 100_000), reps: reps, rpe: nil, notes: "")
        }
        let middle = try #require(workout.store.exercises.first?.sets.dropFirst().first)

        try await workout.repositories.workouts.deleteSet(id: middle.id)
        await workout.store.loadExercises()
        await workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 100_000), reps: 2, rpe: nil, notes: "")

        // Two live rows remain when the fourth is written, so counting them would put it at 2 —
        // which the third set still holds. The gap has to be in the middle for that collision to
        // happen, which is why this case exists and the appended one above does not cover it.
        let sets = try #require(workout.store.exercises.first?.sets)
        #expect(sets.map(\.order) == [0, 2, 3])
        #expect(Set(sets.map(\.order)).count == sets.count)
    }

    @Test("A set lands on the exercise it was logged against, not on the workout's first")
    func setsLandOnTheirOwnEntry() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        await workout.store.addExercise(id: workout.bench.id)
        let bench = try #require(workout.store.exercises.last)

        await workout.store.addSet(
            toEntryID: bench.id, weight: Weight(grams: 60_000), reps: 8, rpe: nil, notes: "")

        #expect(workout.store.exercises.first?.sets.isEmpty == true)
        #expect(workout.store.exercises.last?.sets.count == 1)
        #expect(workout.store.exercises.last?.sets.first?.weight == Weight(grams: 60_000))
    }

    @Test("A failed set records zero reps rather than refusing to be logged (FR-1.2.5)")
    func zeroReps() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        await workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 140_000), reps: 0, rpe: nil, notes: "")

        #expect(workout.store.exercises.first?.sets.first?.reps == 0)
    }

    @Test("Two taps of Log set in flight together are two sets, not one")
    func concurrentWritesAreChained() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        // Both commands read the stored order when they run. Unchained, the second computes against
        // the list the first is about to replace and the two collide at position zero.
        async let first: Void = workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 100_000), reps: 5, rpe: nil, notes: "")
        async let second: Void = workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 100_000), reps: 3, rpe: nil, notes: "")
        _ = await (first, second)

        let sets = try #require(workout.store.exercises.first?.sets)
        #expect(sets.count == 2)
        #expect(sets.map(\.order) == [0, 1])
    }

    @Test("A set logged with no workout in progress is not written")
    func noWorkoutNoSet() async throws {
        let repositories = InMemoryRepositoryStack()
        let store = ActiveSessionStore.overWorkouts(repositories.workouts)
        let entryID = UUID()

        await store.addSet(
            toEntryID: entryID, weight: Weight(grams: 100_000), reps: 5, rpe: nil, notes: "")

        let stored = try await repositories.workouts.sets(
            forEntryID: entryID, includingDeleted: false)
        #expect(stored.isEmpty)
        #expect(store.exercisesWriteFailure == nil)
    }

    @Test("A write that fails is reported and costs the cards nothing")
    func failedWriteKeepsTheCards() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)

        // A dangling entry is what the repository refuses — the same refusal a set against a
        // deleted exercise would meet.
        await workout.store.addSet(
            toEntryID: UUID(), weight: Weight(grams: 100_000), reps: 5, rpe: nil, notes: "")

        #expect(workout.store.exercisesWriteFailure != nil)
        #expect(workout.store.exercises.count == 1)
        #expect(workout.store.exercises.first?.id == entry.id)
        #expect(workout.store.exercises.first?.sets.isEmpty == true)
    }

    @Test("Sets survive the workout being reopened — NFR-1.8's force-quit")
    func setsSurviveAReopen() async throws {
        let workout = try await Workout.started()
        await workout.store.addExercise(id: workout.squat.id)
        let entry = try #require(workout.store.exercises.first)
        await workout.store.addSet(
            toEntryID: entry.id, weight: Weight(grams: 102_500), reps: 5, rpe: 8, notes: "belt")

        let reopened = ActiveSessionStore(
            repository: workout.repositories.workouts,
            catalogue: workout.repositories.exercises,
            settings: workout.repositories.settings
        )
        await reopened.resume()
        await reopened.loadExercises()

        let held = try #require(reopened.exercises.first?.sets.first)
        #expect(held.weight == Weight(grams: 102_500))
        #expect(held.reps == 5)
        #expect(held.rpe == 8)
        #expect(held.notes == "belt")
    }

    // MARK: - The display unit (G-3.1, G-3.2, FR-1.10.2)

    @Test("The unit is the settings row's, and kilograms until one has been read")
    func displayUnitFollowsTheSettingsRow() async throws {
        let repositories = InMemoryRepositoryStack()
        let store = ActiveSessionStore(
            repository: repositories.workouts,
            catalogue: repositories.exercises,
            settings: repositories.settings
        )
        #expect(store.displayUnit == .kilograms)
        let stored = try await repositories.settings.settings()
        try await repositories.settings.save(stored.with(displayUnit: .pounds))

        await store.loadDisplayUnit()

        #expect(store.displayUnit == .pounds)
    }
}

extension UserSettings {
    /// This row with a different display unit and every other field untouched.
    ///
    /// Rebuilt rather than mutated because the record is a value with `let` properties.
    ///
    /// - Parameter unit: The unit to store.
    /// - Returns: The amended row.
    fileprivate func with(displayUnit unit: MassUnit) -> UserSettings {
        UserSettings(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            userID: userID,
            displayUnit: unit,
            e1RMFormula: e1RMFormula,
            theme: theme,
            defaultRoundingIncrement: defaultRoundingIncrement,
            defaultRoundingStrategy: defaultRoundingStrategy
        )
    }
}
