import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

@Suite("A workout read as a routine")
struct SessionAsRoutineTests {
    @Test("Consecutive sets at the same load and reps are one target group")
    func equalSetsCollapse() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 100_000, reps: 5),
            set(order: 1, grams: 100_000, reps: 5),
            set(order: 2, grams: 100_000, reps: 5),
        ])

        #expect(groups == [SessionAsRoutine.Target(weight: Weight(grams: 100_000), reps: 5, sets: 3)])
    }

    @Test("A change of load opens the next group, and a change of reps does too")
    func changesOpenGroups() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 140_000, reps: 3),
            set(order: 1, grams: 120_000, reps: 8),
            set(order: 2, grams: 120_000, reps: 8),
            set(order: 3, grams: 120_000, reps: 6),
        ])

        #expect(
            groups == [
                SessionAsRoutine.Target(weight: Weight(grams: 140_000), reps: 3, sets: 1),
                SessionAsRoutine.Target(weight: Weight(grams: 120_000), reps: 8, sets: 2),
                SessionAsRoutine.Target(weight: Weight(grams: 120_000), reps: 6, sets: 1),
            ])
    }

    @Test("A wave back to an earlier load is a third group, not a bigger first one")
    func equalButNotConsecutive() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 100_000, reps: 5),
            set(order: 1, grams: 120_000, reps: 5),
            set(order: 2, grams: 100_000, reps: 5),
        ])

        #expect(groups.count == 3)
        #expect(groups.map(\.sets) == [1, 1, 1])
    }

    @Test("Warmups are not the work, and are not prescribed")
    func warmupsAreLeftOut() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 60_000, reps: 5, isWarmup: true),
            set(order: 1, grams: 80_000, reps: 3, isWarmup: true),
            set(order: 2, grams: 100_000, reps: 5),
        ])

        #expect(groups == [SessionAsRoutine.Target(weight: Weight(grams: 100_000), reps: 5, sets: 1)])
    }

    @Test("A set that was not completed is not something to prescribe next time")
    func unperformedSetsAreLeftOut() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 100_000, reps: 5),
            set(order: 1, grams: 100_000, reps: 0, isCompleted: false),
        ])

        #expect(groups == [SessionAsRoutine.Target(weight: Weight(grams: 100_000), reps: 5, sets: 1)])
    }

    @Test("A warmup between two identical working sets does not split them")
    func warmupsDoNotBreakARun() {
        let groups = SessionAsRoutine.targets(from: [
            set(order: 0, grams: 100_000, reps: 5),
            set(order: 1, grams: 60_000, reps: 10, isWarmup: true),
            set(order: 2, grams: 100_000, reps: 5),
        ])

        #expect(groups == [SessionAsRoutine.Target(weight: Weight(grams: 100_000), reps: 5, sets: 2)])
    }

    @Test("The exercises are the routine's shape, in the order the workout did them")
    func slotsFollowTheEntries() {
        let squat = UUID()
        let bench = UUID()
        let plan = SessionAsRoutine([
            exercise(exerciseID: squat, order: 0, sets: [set(order: 0, grams: 180_000, reps: 3)]),
            exercise(exerciseID: bench, order: 1, sets: [set(order: 0, grams: 100_000, reps: 5)]),
        ])

        #expect(plan.slots.map(\.exerciseID) == [squat, bench])
        #expect(plan.slots.map { $0.groups.count } == [1, 1])
    }

    @Test("An exercise with nothing that qualifies is still a slot, with no targets under it")
    func anExerciseWithNoWorkIsStillASlot() {
        let plan = SessionAsRoutine([
            exercise(exerciseID: UUID(), order: 0, sets: []),
            exercise(
                exerciseID: UUID(),
                order: 1,
                sets: [set(order: 0, grams: 60_000, reps: 5, isWarmup: true)]),
        ])

        #expect(plan.slots.count == 2)
        #expect(plan.slots.allSatisfy { $0.groups.isEmpty })
    }

    @Test("The routine's groups are the display grouping, coarsened rather than recomputed")
    func theTwoGroupingsAgree() {
        // `FR-16.1.1` and `FR-15.2.6` read the same runs at two grains, and this is the claim that
        // there is one rule behind both: over a workout holding a warmup, a failure and a rating
        // that drifts, the targets are exactly the load-and-reps grouping of the sets a routine
        // keeps. A second walk anywhere would show up here.
        let sets = [
            set(order: 0, grams: 60_000, reps: 5, isWarmup: true),
            set(order: 1, grams: 100_000, reps: 5),
            set(order: 2, grams: 100_000, reps: 5),
            set(order: 3, grams: 100_000, reps: 5, isCompleted: false),
            set(order: 4, grams: 100_000, reps: 5),
            set(order: 5, grams: 90_000, reps: 8),
        ]

        let expected =
            SetGrouping
            .groups(sets.filter { !$0.isWarmup && $0.isCompleted }, at: .loadAndReps)
            .map { SessionAsRoutine.Target(weight: $0.weight, reps: $0.reps, sets: $0.count) }

        #expect(SessionAsRoutine.targets(from: sets) == expected)
        // Anchored against the literal as well, so the assertion cannot pass by both sides being
        // wrong in the same way — the shape a comparison of two reads has otherwise.
        #expect(
            SessionAsRoutine.targets(from: sets) == [
                SessionAsRoutine.Target(weight: Weight(grams: 100_000), reps: 5, sets: 3),
                SessionAsRoutine.Target(weight: Weight(grams: 90_000), reps: 8, sets: 1),
            ])
    }

    /// One logged set, with only the fields this conversion reads spelled out.
    ///
    /// - Parameters:
    ///   - order: Its place among the entry's sets.
    ///   - grams: The load.
    ///   - reps: The repetitions.
    ///   - isWarmup: Whether it was a ramp.
    ///   - isCompleted: Whether it was performed.
    /// - Returns: The set.
    private func set(
        order: Int, grams: Int, reps: Int, isWarmup: Bool = false, isCompleted: Bool = true
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: .distantPast,
            updatedAt: .distantPast,
            deletedAt: nil,
            entryID: UUID(),
            order: order,
            weight: Weight(grams: grams),
            reps: reps,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil)
    }

    /// One exercise of a session, with no catalogue row behind it — this conversion reads the
    /// entry's identifier and never the name.
    ///
    /// - Parameters:
    ///   - exerciseID: What the entry prescribes.
    ///   - order: Its place in the workout.
    ///   - sets: What was logged against it.
    /// - Returns: The join.
    private func exercise(exerciseID: UUID, order: Int, sets: [SetEntry]) -> SessionExercise {
        SessionExercise(
            entry: ExerciseEntry(
                id: UUID(),
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: exerciseID,
                order: order,
                notes: ""),
            exercise: nil,
            sets: sets)
    }
}
