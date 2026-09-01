import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-15.3.3`: how much of what a routine prescribed was performed as prescribed.
///
/// **The three absences this has to keep apart, none of which is a miss**: an exercise nobody
/// planned, a set logged past the end of a plan, and a workout with no plan at all. Only the last
/// changes the figure into no figure; the first two leave it alone, and a rule that folded any of
/// them into "not adherent" would report a lifter's extra work as a failure.
@MainActor
@Suite("Session adherence")
struct SessionAdherenceTests {
    // MARK: - The figure itself (FR-15.3.3)

    @Test("A mix of fulfilled, adjusted and skipped exercises reads correctly")
    func mixedSessionReadsCorrectly() throws {
        // The squat prescribes four — a top set and three backoffs — and gets the top set exactly,
        // one backoff exactly, and one adjusted away from the plan. The press prescribes three and
        // is skipped outright. Seven prescribed, two as prescribed.
        let adherence = try #require(
            SessionAdherence([
                PlanFixture.card(
                    sets: [
                        PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5),
                        PlanFixture.workingSet(order: 1, grams: 85_000, reps: 8),
                        PlanFixture.workingSet(order: 2, grams: 85_000, reps: 6),
                    ],
                    planned: [
                        PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1),
                        PlanFixture.group(order: 1, grams: 85_000, reps: 8, sets: 3),
                    ]
                ),
                PlanFixture.card(
                    sets: [],
                    planned: [PlanFixture.group(order: 0, grams: 40_000, reps: 8, sets: 3)],
                    isMarkedDone: true
                ),
            ]))

        #expect(adherence.asPrescribed == 2)
        #expect(adherence.prescribed == 7)
    }

    /// The denominator is the plan, so a skip costs what it prescribed rather than nothing.
    @Test("A skipped exercise keeps its prescribed sets in the total")
    func aSkipKeepsItsSetsInTheTotal() throws {
        let skipped = PlanFixture.card(
            sets: [],
            planned: [PlanFixture.group(order: 0, grams: 60_000, reps: 5, sets: 4)],
            isMarkedDone: true
        )

        let adherence = try #require(SessionAdherence([skipped]))

        #expect(skipped.isSkipped)
        #expect(adherence.asPrescribed == 0)
        #expect(adherence.prescribed == 4)
    }

    /// `FR-1.2.5`'s outcome is half of "completed as prescribed", and it is the half a comparison
    /// alone cannot see: a failed set can hit its numbers exactly.
    @Test("A set that matched its target but was not completed does not count")
    func anUncompletedSetDoesNotCount() throws {
        let adherence = try #require(
            SessionAdherence([
                PlanFixture.card(
                    sets: [
                        PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5, isCompleted: false)
                    ],
                    planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)]
                )
            ]))

        #expect(adherence.asPrescribed == 0)
        #expect(adherence.prescribed == 1)
    }

    // MARK: - A blank target is judged, not excluded (FR-15.2.2)

    /// The Scope decision, recorded here as well as in the task file: a group prescribing no load
    /// stays in the denominator and is judged on its reps alone. Excluding it would drop sets the
    /// routine explicitly prescribed — `FR-15.2.2`'s own note is that the reps and the sets stay
    /// prescribed — and counting its absent load as a miss would make every such set deviate by
    /// construction. It is ``PlannedTargetComparison/isOnTarget``'s rule, reached from here.
    @Test("A blank-weight group counts, and counts on its reps alone")
    func aBlankTargetIsJudgedOnItsRepsAlone() throws {
        let adherence = try #require(
            SessionAdherence([
                PlanFixture.card(
                    sets: [
                        // Two loads nobody prescribed, and only the second misses the reps.
                        PlanFixture.workingSet(order: 0, grams: 60_000, reps: 5),
                        PlanFixture.workingSet(order: 1, grams: 62_500, reps: 4),
                    ],
                    planned: [PlanFixture.group(order: 0, grams: nil, reps: 5, sets: 3)]
                )
            ]))

        #expect(adherence.asPrescribed == 1)
        #expect(adherence.prescribed == 3)
    }

    // MARK: - The absences that are not misses

    /// `FR-15.2.4`'s independence: an extra set is not an error, and it has no target to be
    /// measured against.
    @Test("Sets logged past the end of the plan count on neither side")
    func setsPastThePlanCountNeitherWay() throws {
        let card = PlanFixture.card(
            sets: [
                PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5),
                PlanFixture.workingSet(order: 1, grams: 100_000, reps: 5),
            ],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)]
        )

        let adherence = try #require(SessionAdherence([card]))

        // The second set is genuinely past the plan rather than simply unmatched.
        #expect(card.plannedTargets.count == 1)
        #expect(adherence.asPrescribed == 1)
        #expect(adherence.prescribed == 1)
    }

    /// Warmups are not the work anywhere else in this module either, and they do not consume a
    /// planned set — so a lifter who warmed up three times has not thereby met the plan.
    @Test("Warmups count on neither side")
    func warmupsCountNeitherWay() throws {
        let adherence = try #require(
            SessionAdherence([
                PlanFixture.card(
                    sets: [
                        PlanFixture.warmupSet(order: 0, grams: 100_000, reps: 5),
                        PlanFixture.warmupSet(order: 1, grams: 100_000, reps: 5),
                    ],
                    planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 2)]
                )
            ]))

        #expect(adherence.asPrescribed == 0)
        #expect(adherence.prescribed == 2)
    }

    /// An exercise added by hand to a planned workout is not part of the plan, so its sets can
    /// neither raise the figure nor lower it.
    @Test("An unplanned exercise in a planned workout contributes to neither side")
    func anUnplannedExerciseContributesToNeitherSide() throws {
        let planned = PlanFixture.card(
            sets: [PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5)],
            planned: [PlanFixture.group(order: 0, grams: 100_000, reps: 5, sets: 1)]
        )
        let added = PlanFixture.card(
            sets: [
                PlanFixture.workingSet(order: 0, grams: 30_000, reps: 12),
                PlanFixture.workingSet(order: 1, grams: 30_000, reps: 12),
            ],
            planned: []
        )

        let adherence = try #require(SessionAdherence([planned, added]))

        #expect(adherence.asPrescribed == 1)
        #expect(adherence.prescribed == 1)
    }

    // MARK: - No plan is no figure, not zero (FR-1.13.3)

    @Test("A workout nobody planned has no adherence at all")
    func anUnplannedWorkoutHasNoAdherence() {
        // Not 0 and not 1: the ratio is undefined, and the screen draws no row for it. A workout
        // with sets in it and no plan is the ordinary case here — every hand-started session.
        #expect(
            SessionAdherence([
                PlanFixture.card(
                    sets: [PlanFixture.workingSet(order: 0, grams: 100_000, reps: 5)], planned: [])
            ]) == nil)
        #expect(SessionAdherence([]) == nil)
    }

    // MARK: - It follows an adjustment, with nothing to invalidate (FR-15.3.5)

    /// Derived at read time, so an edit re-derives on the next read — the claim
    /// ``PlannedTargetComparison`` makes about one set, asked of the whole workout. This is what
    /// pins it against a later "store the count beside the session" optimisation, which would be
    /// correct until the first correction.
    ///
    /// **Through the screen's own edit path**, for `SessionPlanAdjustmentTests`' reason: an
    /// adjustment re-issued here rather than routed through
    /// ``ActiveSessionView/prescription(for:in:)`` would test a write nobody makes.
    @Test("An adjustment onto the target raises adherence")
    func anAdjustmentOntoTheTargetRaisesAdherence() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        // Two exercises, prescribing 1 + 3 + 3 between them, and nothing logged yet.
        #expect(store.adherence?.prescribed == 7)
        #expect(store.adherence?.asPrescribed == 0)
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 4)
        #expect(store.adherence?.asPrescribed == 0)

        try await store.adjust(logged, to: Self.values(grams: 100_000, reps: 5))

        #expect(store.adherence?.asPrescribed == 1)
        #expect(store.adherence?.prescribed == 7)
    }

    /// The other direction, which an over-eager cache breaks and the first test cannot reach: an
    /// adjustment can introduce a miss as well as correct one.
    @Test("An adjustment away from the target lowers adherence")
    func anAdjustmentAwayFromTheTargetLowersAdherence() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 5)
        #expect(store.adherence?.asPrescribed == 1)

        try await store.adjust(logged, to: Self.values(grams: 102_500, reps: 5))

        #expect(store.adherence?.asPrescribed == 0)
        #expect(store.adherence?.prescribed == 7)
    }

    /// One logged set's four columns, with the two nobody here varies fixed.
    private static func values(grams: Int, reps: Int) -> SetEntryValues {
        SetEntryValues(weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false)
    }
}
