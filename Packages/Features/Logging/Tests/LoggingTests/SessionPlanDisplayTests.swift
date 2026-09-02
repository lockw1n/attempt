import DesignSystem
import Foundation
import Logging
import PowerliftingCore
import RepositoryInterface
import Testing

/// `FR-15.3.1`'s target per logged set — the same walk `FR-15.2.3` uses for the next one, asked at
/// each set instead.
@Suite("The target a logged set was planned against")
struct LoggedSetTargetTests {
    /// A top set and a backoff: one set at 100, then three at 85.
    private static let plan = [
        PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1),
        PlanFixture.group(order: 1, grams: 85_000, reps: 8, sets: 3),
    ]

    @Test("Each working set is placed in the group its position falls in")
    func eachWorkingSetIsPlacedInItsGroup() throws {
        let sets = (0..<4).map { PlanFixture.workingSet(order: $0) }
        let card = PlanFixture.card(sets: sets, planned: Self.plan)

        let targets = card.plannedTargets
        #expect(targets.count == 4)
        #expect(targets[sets[0].id]?.targetWeight == Weight(grams: 100_000))
        #expect(
            sets.dropFirst().allSatisfy { targets[$0.id]?.targetWeight == Weight(grams: 85_000) })
    }

    /// The warmup exists to *not* be placed: it consumes no planned set, so the working set after
    /// it is still the top set rather than the first backoff.
    @Test("A warmup has no target, and does not push the work down the plan")
    func warmupsAreNotPlaced() throws {
        let warmup = PlanFixture.warmupSet(order: 0)
        let working = PlanFixture.workingSet(order: 1)
        let card = PlanFixture.card(sets: [warmup, working], planned: Self.plan)

        let targets = card.plannedTargets
        #expect(targets[warmup.id] == nil)
        #expect(targets[working.id]?.targetWeight == Weight(grams: 100_000))
    }

    /// `FR-15.2.4`'s independence: an extra set is not an error and has nothing to be measured
    /// against — it is absent from the map rather than repeating the last group.
    @Test("A set past the end of the plan has no target")
    func setsPastThePlanHaveNoTarget() throws {
        let sets = (0..<5).map { PlanFixture.workingSet(order: $0) }
        let card = PlanFixture.card(sets: sets, planned: Self.plan)

        #expect(card.plannedTargets.count == 4)
        #expect(card.plannedTargets[sets[4].id] == nil)
    }

    @Test("An exercise nobody planned has no targets at all")
    func unplannedExerciseHasNoTargets() {
        let card = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0)], planned: [])

        #expect(card.plannedTargets.isEmpty)
    }
}

/// `FR-15.3.2`'s deviation, including the third state a blank target creates.
@Suite("Measuring a set against its target")
struct PlannedTargetComparisonTests {
    @Test(
        "The load's direction follows the arithmetic",
        arguments: [
            (100_000, DeltaDirection.unchanged), (102_500, .increase), (97_500, .decrease),
        ]
    )
    func loadDirection(grams: Int, expected: DeltaDirection) {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: grams, reps: 5),
            target: PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)
        )

        #expect(comparison.weight == expected)
    }

    @Test("The magnitudes are unsigned, and the direction carries the sign")
    func magnitudesAreUnsigned() {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 97_500, reps: 3),
            target: PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)
        )

        #expect(comparison.weightDifference == Weight(grams: 2_500))
        #expect(comparison.weight == .decrease)
        #expect(comparison.repsDifference == 2)
        #expect(comparison.reps == .decrease)
    }

    @Test("A set that matched everything the plan named is on target")
    func matchingSetIsOnTarget() {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5),
            target: PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)
        )

        #expect(comparison.isOnTarget)
        #expect(comparison.weight == .unchanged)
        #expect(comparison.repsDifference == 0)
    }

    /// The half of `FR-15.3.2` that a reps-only reading of ``isOnTarget`` would swallow: the load
    /// deviated and the reps did not, so the row owes the lifter a mark rather than "On target".
    @Test("A set that hit its reps and missed its load is not on target")
    func matchingRepsAloneIsNotOnTarget() {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 87_500, reps: 8),
            target: PlanFixture.group(order: 0, grams: 85_000, reps: 8, sets: 3)
        )

        #expect(comparison.isOnTarget == false)
        #expect(comparison.reps == .unchanged)
        #expect(comparison.movedWeight?.direction == .increase)
        #expect(comparison.movedWeight?.difference == Weight(grams: 2_500))
    }

    /// And the mirror, so the pair pins both clauses rather than one: the reps moved and the load
    /// did not.
    @Test("A set that hit its load and missed its reps is not on target either")
    func matchingLoadAloneIsNotOnTarget() {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 85_000, reps: 7),
            target: PlanFixture.group(order: 0, grams: 85_000, reps: 8, sets: 3)
        )

        #expect(comparison.isOnTarget == false)
        // `nil` rather than a signed zero: the load matched, so the row draws no load indicator.
        // Asked through a member, a tuple having no `Equatable` conformance to compare against.
        #expect(comparison.movedWeight?.direction == nil)
        #expect(comparison.weight == .unchanged)
        #expect(comparison.reps == .decrease)
    }

    /// `FR-15.2.2`: a blank target is not a target of zero. The load has no direction at all —
    /// anchored to `nil` on one side, because two optionals compared to each other would pass on a
    /// comparison that reported nothing.
    @Test("A blank-weight target gives the load no direction, whatever was lifted")
    func blankTargetHasNoLoadDirection() {
        let comparison = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 140_000, reps: 5),
            target: PlanFixture.group(order: 0, grams: nil, reps: 5, sets: 3)
        )

        #expect(comparison.weight == nil)
        #expect(comparison.weightDifference == nil)
    }

    /// The half of the blank case that still answers: the reps were prescribed, so they can miss.
    @Test("A blank-weight target still measures the reps, and is on target when they match")
    func blankTargetStillMeasuresReps() {
        let target = PlanFixture.group(order: 0, grams: nil, reps: 5, sets: 3)

        let matched = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 140_000, reps: 5), target: target)
        let missed = PlannedTargetComparison(
            set: PlanFixture.workingSet(order: 0, grams: 140_000, reps: 4), target: target)

        #expect(matched.isOnTarget)
        #expect(missed.isOnTarget == false)
        #expect(missed.reps == .decrease)
        #expect(missed.repsDifference == 1)
    }
}

/// `FR-15.3.4`'s check-off, and what it does to the card and the progress bar.
@Suite("The per-exercise check-off")
struct ExerciseCheckOffTests {
    @Test("An exercise is done when the lifter says so, whatever the sets say")
    func theLiftersVerdictCounts() {
        let short = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0, isCompleted: false)],
            planned: [],
            isMarkedDone: true
        )

        #expect(short.isComplete == false)
        #expect(short.isDone)
    }

    /// Phase 1's rule survives: the sets can finish an exercise without the lifter touching the
    /// control.
    @Test("An exercise is also done when every working set is completed and nobody checked it off")
    func theSetsStillCount() {
        let finished = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0)], planned: [], isMarkedDone: false)

        #expect(finished.isDone)
        #expect(finished.isSkipped == false)
    }

    @Test("Checked off with none of the work behind it is a skip, not a completion")
    func checkedOffWithNoWorkIsASkip() {
        let skipped = PlanFixture.card(sets: [], planned: [], isMarkedDone: true)

        #expect(skipped.isSkipped)
        #expect(skipped.isDone)
        #expect(skipped.isComplete == false)
    }

    /// Warmups are not the work anywhere else here either — warming up to a lift and then skipping
    /// it is still a skip.
    @Test("Warmups alone do not stop a check-off being a skip")
    func warmupsAloneAreStillASkip() {
        let skipped = PlanFixture.card(
            sets: [PlanFixture.warmupSet(order: 0)], planned: [], isMarkedDone: true)

        #expect(skipped.isSkipped)
    }

    @Test("An untouched exercise is neither done nor skipped")
    func untouchedExerciseIsNeither() {
        let fresh = PlanFixture.card(sets: [], planned: [], isMarkedDone: false)

        #expect(fresh.isDone == false)
        #expect(fresh.isSkipped == false)
    }

    /// A mark that changed nothing above the card would be a mark the lifter has to take on trust.
    @Test("A checked-off exercise advances the progress bar")
    func checkOffAdvancesProgress() {
        let workout = [
            PlanFixture.card(sets: [], planned: [], isMarkedDone: true),
            PlanFixture.card(sets: [], planned: [], isMarkedDone: false),
        ]

        let progress = SessionProgress(workout)
        #expect(progress.completed == 1)
        #expect(progress.total == 2)
    }
}

/// The fixtures the three suites above share — one card, one group, one set, each with only what
/// the test under it varies.
enum PlanFixture {
    /// A fixed stamp, so nothing here depends on the clock.
    static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    /// One card, with only its sets, its plan and its check-off varying.
    static func card(
        sets: [SetEntry], planned: [PlannedTargetGroup], isMarkedDone: Bool = false
    ) -> SessionExercise {
        SessionExercise(
            entry: ExerciseEntry(
                id: UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: "",
                isMarkedDone: isMarkedDone
            ),
            exercise: nil,
            sets: sets,
            planned: planned
        )
    }

    /// One planned group.
    static func group(order: Int, grams: Int?, reps: Int, sets: Int) -> PlannedTargetGroup {
        PlannedTargetGroup(
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

    /// One working set.
    static func workingSet(
        order: Int, grams: Int = 100_000, reps: Int = 5, isCompleted: Bool = true
    ) -> SetEntry {
        loggedSet(order: order, grams: grams, reps: reps, isWarmup: false, isCompleted: isCompleted)
    }

    /// One warmup.
    static func warmupSet(order: Int, grams: Int = 60_000, reps: Int = 5) -> SetEntry {
        loggedSet(order: order, grams: grams, reps: reps, isWarmup: true, isCompleted: true)
    }

    private static func loggedSet(
        order: Int, grams: Int, reps: Int, isWarmup: Bool, isCompleted: Bool
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
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
            completedAt: nil
        )
    }
}
