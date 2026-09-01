import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-15.2.3`'s third way into a workout, and `TR-15.3`'s snapshot.
@MainActor
@Suite("Starting a workout from a routine")
struct SessionRoutineStartTests {
    @Test("The workout holds the routine's exercises, in the routine's order")
    func theWorkoutHoldsTheRoutinesExercises() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        #expect(
            await store.start(
                on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines))

        let session = try #require(store.session)
        let entries = try await fixture.stack.workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        #expect(entries.map(\.exerciseID) == [fixture.squat, fixture.bench])
        #expect(entries.map(\.order) == [0, 1])
    }

    /// The multi-group case `FR-15.2.1`'s amendment exists for: a top set and a backoff under one
    /// exercise, both snapshotted, in order.
    @Test("Every target group is snapshotted onto the entry, multi-group exercises included")
    func everyTargetGroupIsSnapshotted() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        await store.start(
            on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines)
        await store.loadExercises()

        let squatCard = try #require(store.exercises.first)
        #expect(squatCard.planned.map(\.order) == [0, 1])
        #expect(
            squatCard.planned.map(\.targetWeight) == [
                Weight(grams: 100_000), Weight(grams: 85_000),
            ])
        #expect(squatCard.planned.map(\.targetReps) == [5, 8])
        #expect(squatCard.planned.map(\.targetSets) == [1, 3])
    }

    /// `FR-15.2.2`'s blank target: the load is the lifter's to decide in the session, and the reps
    /// and sets are prescribed all the same.
    @Test("A blank target arrives blank, with its reps and sets intact")
    func ablankTargetArrivesBlank() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        await store.start(
            on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines)
        await store.loadExercises()

        let benchCard = try #require(store.exercises.last)
        #expect(benchCard.planned.count == 1)
        // Anchored to `nil` on one side: two optionals compared to each other pass on a column
        // that was never written.
        #expect(benchCard.planned.first?.targetWeight == nil)
        #expect(benchCard.planned.first?.targetReps == 5)
        #expect(benchCard.planned.first?.targetSets == 3)
    }

    /// `TR-15.3` itself, and the reason the snapshot is a copy rather than a reference.
    @Test("Editing the routine afterwards leaves the session's targets alone")
    func editingTheRoutineLeavesTheSessionAlone() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)
        await store.start(
            on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines)
        await store.loadExercises()

        try await fixture.stack.routines.save(
            RoutineTargetGroup(
                id: fixture.topSetID,
                createdAt: fixture.today,
                updatedAt: fixture.today,
                deletedAt: nil,
                routineExerciseID: fixture.squatSlotID,
                order: 0,
                targetWeight: Weight(grams: 140_000),
                targetReps: 1,
                targetSets: 1
            )
        )
        await store.loadExercises()

        let squatCard = try #require(store.exercises.first)
        #expect(squatCard.planned.first?.targetWeight == Weight(grams: 100_000))
        #expect(squatCard.planned.first?.targetReps == 5)
        // And the routine really did change — without this the assertion above passes against an
        // edit that never landed.
        let template = try await fixture.stack.routines.targetGroups(
            forRoutineExerciseID: fixture.squatSlotID, includingDeleted: false)
        #expect(template.first?.targetWeight == Weight(grams: 140_000))
    }

    /// ``ActiveSessionStore/start(on:)``'s invariant, not a new one.
    @Test("A routine start is refused while a workout is in progress")
    func aroutineStartIsRefusedWhileAWorkoutIsInProgress() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)
        await store.start(on: fixture.today)
        let held = try #require(store.session)

        #expect(
            await store.start(
                on: fixture.today, fromRoutineID: fixture.routineID, in: fixture.stack.routines)
                == false)

        #expect(store.session?.id == held.id)
        await store.loadExercises()
        #expect(store.exercises.isEmpty)
    }

    /// A routine that is not there is a read that returns nothing, not a failure — but the workout
    /// is kept either way, which is the half worth pinning.
    @Test("A routine with no slots still leaves a workout to log into")
    func anemptyRoutineStillLeavesAWorkout() async throws {
        let fixture = try await RoutineFixture()
        let store = ActiveSessionStore.over(fixture.stack)

        #expect(
            await store.start(on: fixture.today, fromRoutineID: UUID(), in: fixture.stack.routines))

        #expect(store.session != nil)
        #expect(store.exercises.isEmpty)
    }
}

/// `TR-15.4`'s one resolution rule, at the seam where a routine's prescription becomes a number.
@Suite("Resolving a routine's target")
struct PlannedTargetResolutionTests {
    /// Gap §24's second half, which had lived only in a doc comment: the rounding rule applies
    /// where a `Double` factor entered, and a weight somebody typed is returned untouched. A
    /// deliberately coarse rule is what makes the claim falsifiable — under a 5 kg rule a rounded
    /// 102 483 g would come back as 100 000 or 105 000 g.
    @Test("A fixed weight is not rounded, however coarse the context's rule")
    func afixedWeightIsNotRounded() throws {
        let coarse = try #require(RoundingRule(increment: Weight(grams: 5_000), strategy: .nearest))
        let group = group(grams: 102_483)

        let resolved = ActiveSessionStore.resolvedTarget(
            for: group,
            using: PrescriptionResolver(),
            in: PrescriptionContext(rounding: coarse))

        #expect(resolved == Weight(grams: 102_483))
    }

    @Test("A blank target resolves to no weight rather than to zero")
    func ablankTargetResolvesToNoWeight() {
        let resolved = ActiveSessionStore.resolvedTarget(
            for: group(grams: nil),
            using: PrescriptionResolver(),
            in: PrescriptionContext(rounding: .unrounded))

        #expect(resolved == nil)
    }

    /// Assisted work is a negative load, and `.fixedWeight` accepts one — the resolver's sign guard
    /// belongs to the cases that scale a basis, not to a weight the lifter typed.
    @Test("A negative target survives, being assisted work rather than an error")
    func anegativeTargetSurvives() {
        let resolved = ActiveSessionStore.resolvedTarget(
            for: group(grams: -20_000),
            using: PrescriptionResolver(),
            in: PrescriptionContext(rounding: .unrounded))

        #expect(resolved == Weight(grams: -20_000))
    }

    private func group(grams: Int?) -> RoutineTargetGroup {
        RoutineTargetGroup(
            id: UUID(),
            createdAt: .now,
            updatedAt: .now,
            deletedAt: nil,
            routineExerciseID: UUID(),
            order: 0,
            targetWeight: grams.map(Weight.init(grams:)),
            targetReps: 5,
            targetSets: 3
        )
    }
}

/// One target group's three numbers, as a value: a helper taking all three plus an id, a slot and
/// an order is a six-parameter function, and a tuple of three is a large tuple.
private struct TargetSpec {
    let grams: Int?
    let reps: Int
    let sets: Int
}

/// The day every record in the fixture is stamped with, at file scope so the helpers below can
/// be called while the fixture is still initialising.
private let routineFixtureDay = Date(timeIntervalSince1970: 1_700_000_000)

/// A routine of two exercises: a squat with a top set and a backoff, and a bench with a blank
/// target — the three shapes `FR-15.2.1` and `FR-15.2.2` between them allow.
@MainActor
private struct RoutineFixture {
    let stack = InMemoryRepositoryStack()
    let squat = UUID()
    let bench = UUID()
    let routineID = UUID()
    let squatSlotID = UUID()
    let today = routineFixtureDay

    /// The squat's top set, whose id the "a later edit changes nothing" test rewrites.
    let topSetID = UUID()

    init() async throws {
        for (id, name) in [(squat, "Back Squat"), (bench, "Bench Press")] {
            try await stack.exercises.save(exercise(id: id, named: name))
        }
        try await stack.routines.save(
            Routine(
                id: routineID,
                createdAt: today,
                updatedAt: today,
                deletedAt: nil,
                name: "Squat day"
            )
        )

        try await stack.routines.save(slot(id: squatSlotID, exerciseID: squat, order: 0))
        try await stack.routines.save(
            group(id: topSetID, slotID: squatSlotID, order: 0, target: TargetSpec(grams: 100_000, reps: 5, sets: 1)))
        try await stack.routines.save(
            group(id: UUID(), slotID: squatSlotID, order: 1, target: TargetSpec(grams: 85_000, reps: 8, sets: 3)))

        let benchSlotID = UUID()
        try await stack.routines.save(slot(id: benchSlotID, exerciseID: bench, order: 1))
        try await stack.routines.save(
            group(id: UUID(), slotID: benchSlotID, order: 0, target: TargetSpec(grams: nil, reps: 5, sets: 3)))
    }

    private func slot(id: UUID, exerciseID: UUID, order: Int) -> RoutineExercise {
        RoutineExercise(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            routineID: routineID,
            exerciseID: exerciseID,
            order: order
        )
    }

    private func group(
        id: UUID,
        slotID: UUID,
        order: Int,
        target: TargetSpec
    ) -> RoutineTargetGroup {
        RoutineTargetGroup(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            routineExerciseID: slotID,
            order: order,
            targetWeight: target.grams.map(Weight.init(grams:)),
            targetReps: target.reps,
            targetSets: target.sets
        )
    }

    private func exercise(id: UUID, named name: String) -> Exercise {
        Exercise(
            id: id,
            createdAt: today,
            updatedAt: today,
            deletedAt: nil,
            name: name,
            ukrainianName: nil,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: "",
            manualE1RM: nil
        )
    }
}
