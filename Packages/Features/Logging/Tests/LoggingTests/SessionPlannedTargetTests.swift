import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import Testing

/// Which planned group the next set falls in (`FR-15.2.3`) — the walk that makes a multi-group
/// exercise pre-populate the right target rather than the first one four times.
@Suite("The next planned group")
struct NextPlannedGroupTests {
    /// A top set and a backoff: one set at 100, then three at 85.
    private static let plan = [
        plannedGroup(order: 0, grams: 100_000, reps: 5, sets: 1),
        plannedGroup(order: 1, grams: 85_000, reps: 8, sets: 3),
    ]

    @Test(
        "Each logged working set advances the walk, and the group boundary is where it moves",
        arguments: [
            (0, 100_000), (1, 85_000), (2, 85_000), (3, 85_000),
        ]
    )
    func thewalkAdvancesWithTheWorkingSets(logged: Int, expected: Int) {
        let card = card(sets: (0..<logged).map { workingSet(order: $0) }, planned: Self.plan)

        #expect(card.nextPlannedGroup?.targetWeight == Weight(grams: expected))
    }

    @Test("A set beyond the plan has no planned group, rather than repeating the last one")
    func asetBeyondThePlanHasNoGroup() {
        let card = card(sets: (0..<4).map { workingSet(order: $0) }, planned: Self.plan)

        #expect(card.nextPlannedGroup == nil)
    }

    /// A routine prescribes the work; warming up to it is the lifter's own business.
    @Test("Warmups do not consume a planned set")
    func warmupsDoNotConsumeAPlannedSet() {
        let card = card(sets: [warmupSet(order: 0), warmupSet(order: 1)], planned: Self.plan)

        #expect(card.nextPlannedGroup?.targetWeight == Weight(grams: 100_000))
    }

    /// `NFR-15.3`'s second tap: the form opens carrying the target, so confirming it is one tap
    /// rather than a keyboard.
    @Test("The set form is seeded from the planned group's weight and reps")
    func thesetFormIsSeededFromThePlan() throws {
        let card = card(sets: [], planned: Self.plan)

        let values = try #require(card.plannedValues)
        #expect(values.weight == Weight(grams: 100_000))
        #expect(values.reps == 5)
        #expect(values.isWarmup == false)
    }

    /// `FR-15.2.2`: blank is not zero, so a blank-weight group seeds nothing rather than seeding a
    /// load the lifter never chose.
    @Test("A blank-weight group seeds nothing")
    func ablankWeightGroupSeedsNothing() {
        let blank = [Self.plannedGroup(order: 0, grams: nil, reps: 5, sets: 3)]

        #expect(card(sets: [], planned: blank).plannedValues == nil)
    }

    @Test("An exercise nobody planned has no planned group")
    func anunplannedExerciseHasNone() {
        #expect(card(sets: [], planned: []).nextPlannedGroup == nil)
    }

    /// One card, with only its sets and its plan varying.
    private func card(sets: [SetEntry], planned: [PlannedTargetGroup]) -> SessionExercise {
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
            sets: sets,
            planned: planned
        )
    }

    private static func plannedGroup(
        order: Int, grams: Int?, reps: Int, sets: Int
    ) -> PlannedTargetGroup {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return PlannedTargetGroup(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            exerciseEntryID: UUID(),
            order: order,
            targetWeight: grams.map(Weight.init(grams:)),
            targetReps: reps,
            targetSets: sets
        )
    }

    private func workingSet(order: Int) -> SetEntry { loggedSet(order: order, isWarmup: false) }
    private func warmupSet(order: Int) -> SetEntry { loggedSet(order: order, isWarmup: true) }

    private func loggedSet(order: Int, isWarmup: Bool) -> SetEntry {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: UUID(),
            order: order,
            weight: Weight(grams: 100_000),
            reps: 5,
            rpe: nil,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }
}
