import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// What an exercise's history does with a workout nobody has performed yet (`FR-16.4.2`).
///
/// **The case that put the requirement there**: a restored backup carrying a planned workout, its
/// sets written and none of them attempted. Read without the exclusion, the exercise-detail screen
/// lists a training day that has not happened — dated in the future, and every row of it marked
/// failed.
@Suite("Exercise history: pending sets")
struct ExerciseHistoryPendingTests {
    @Test("A planned workout nobody has started is not in the exercise's history")
    func aPlannedWorkoutIsNotHistory() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        // Last week, performed.
        try await gym.train(squat, onDay: -7, reps: [5, 5, 5])
        // Next week, written and untouched: no `endedAt`, no completed set.
        let planned = try await gym.session(onDay: 7)
        try await gym.perform(squat, in: planned, order: 0, reps: [5, 5, 5], isCompleted: false)

        let state = gym.history(of: squat)
        await state.load()

        // One group, and it is last week's — anchored to the count rather than to "does not
        // contain", which an empty history would also satisfy.
        #expect(state.groups.count == 1)
        #expect(state.groups.first?.id != planned.id)
        #expect(state.groups.first?.sets.count == 3)
        #expect(state.groups.allSatisfy { $0.date < planned.date })
    }

    @Test("Finishing that workout puts it in the history, its sets marked failed")
    func finishingPutsItBack() async throws {
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        try await gym.train(squat, onDay: -7, reps: [5, 5, 5])
        let planned = try await gym.session(onDay: 7)
        try await gym.perform(squat, in: planned, order: 0, reps: [5, 5, 5], isCompleted: false)

        let ended = try await gym.session(id: planned.id, onDay: 7, endedAt: planned.date)
        #expect(ended.isFinished)

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.groups.count == 2)
        let newest = try #require(state.groups.first)
        #expect(newest.id == planned.id)
        #expect(newest.sets.map(\.isCompleted) == [false, false, false])
    }

    @Test("A workout in progress keeps the sets that were performed in it")
    func anOpenWorkoutKeepsWhatWasPerformed() async throws {
        // The exclusion is of sets nobody attempted, not of the workout: `FR-1.6.3` badges a set at
        // the moment it is logged, which is inside the workout that logged it.
        let gym = TrainingHistory()
        let squat = try await gym.exercise(named: "Back Squat")
        let today = try await gym.session(onDay: 0)
        try await gym.perform(squat, in: today, order: 0, reps: [5, 5])
        try await gym.perform(squat, in: today, order: 1, reps: [5], isCompleted: false)

        let state = gym.history(of: squat)
        await state.load()

        #expect(state.groups.count == 1)
        #expect(state.groups.first?.sets.count == 2)
        #expect(state.groups.first?.sets.map(\.isCompleted) == [true, true])
    }
}
