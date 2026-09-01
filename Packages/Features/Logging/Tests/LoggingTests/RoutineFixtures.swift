import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

// The routine every `FR-15.2`/`FR-15.3` suite starts a workout from, in a file of its own because
// two suites now need it: `SessionRoutineStartTests` proves the snapshot is taken, and
// `SessionPlanAdjustmentTests` proves an adjustment made afterwards cannot reach back to it.

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
struct RoutineFixture {
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

/// What a `FR-15.3` suite does to a workout, in one place: start it, log into it, adjust a set,
/// and read the plan back off the cards.
///
/// **Here rather than in the suite that first wrote them**, because two suites now issue the same
/// commands — `SessionPlanAdjustmentTests` and `SessionAdherenceTests` — and an adjustment routed
/// through the production lookup in one file and re-derived in the other is exactly the split that
/// let a broken `prescription(for:in:)` ship green once already.
///
/// An extension rather than free functions so each reads as the command a screen issues.
@MainActor
extension ActiveSessionStore {
    /// Logs a set against the first card and hands it back as the store holds it.
    ///
    /// - Parameters:
    ///   - grams: The load logged.
    ///   - reps: The repetitions logged.
    /// - Returns: The set, read back from the card rather than reconstructed.
    func logFirstSquatSet(grams: Int, reps: Int) async throws -> SetEntry {
        let entryID = try #require(exercises.first?.id)
        await addSet(
            toEntryID: entryID,
            values: SetEntryValues(weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false))
        return try #require(exercises.first?.sets.last)
    }

    /// Adjusts one logged set through the sheet the card opens over it (`FR-15.3.5`).
    ///
    /// - Parameters:
    ///   - set: The set being corrected.
    ///   - values: What the confirmed form holds.
    func adjust(_ set: SetEntry, to values: SetEntryValues) async throws {
        let target = ActiveSessionView.target(
            editing: set,
            prescribed: ActiveSessionView.prescription(for: set, in: exercises))
        // The prescription is carried by an edit and seeds nothing — the form opens holding the set
        // as it was logged. Asserted here rather than in a test of its own because every adjustment
        // below depends on it: a target that seeded would overwrite the correction being made.
        #expect(target.prescribed != nil)
        #expect(target.planned == nil)
        let draft = SetDraft(editing: values, unit: .kilograms, locale: .posix)
        let write = try #require(ActiveSessionView.write(draft, over: target))
        await self.write(write)
    }

    /// The first card's first set measured against the group it was planned in, or `nil`.
    ///
    /// - Returns: The comparison, where the set was planned.
    func comparisonForFirstSet() -> PlannedTargetComparison? {
        guard let card = exercises.first, let set = card.sets.first,
            let target = card.plannedTargets[set.id]
        else { return nil }
        return PlannedTargetComparison(set: set, target: target)
    }
}

@MainActor
extension RoutineFixture {
    /// A workout started from the fixture's routine, with its cards loaded.
    ///
    /// - Returns: The store holding it.
    func startedWorkout() async throws -> ActiveSessionStore {
        let store = ActiveSessionStore.over(stack)
        try await start(store)
        return store
    }

    /// The routine's own target groups for the squat, as the store holds them.
    ///
    /// - Returns: The template rows, in order.
    func template() async throws -> [RoutineTargetGroup] {
        try await stack.routines.targetGroups(
            forRoutineExerciseID: squatSlotID, includingDeleted: false)
    }

    /// Starts a workout from the fixture's routine on an existing store, cards loaded.
    ///
    /// - Parameter store: The store to start it on.
    func start(_ store: ActiveSessionStore) async throws {
        #expect(await store.start(on: today, fromRoutineID: routineID, in: stack.routines))
        await store.loadExercises()
    }
}
