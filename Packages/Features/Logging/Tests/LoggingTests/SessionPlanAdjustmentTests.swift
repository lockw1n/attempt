import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-15.3.5`: an adjustment reaches the set it was made on, and nothing else.
///
/// **Every test here goes through the screen's own edit path rather than calling the store
/// directly** — ``ActiveSessionView/prescription(for:in:)`` for the target the sheet is handed,
/// ``ActiveSessionView/target(editing:prescribed:)`` for what it opens over, and
/// ``ActiveSessionView/write(_:over:)`` for what a confirmed one resolves to. **The lookup is in
/// that list because it was once not**: written out inline here instead, it left the production one
/// returning `nil` for every set with the whole suite still green. The requirement is
/// about the *blast radius* of an edit, and a test that issued `.rewrite` itself would be asserting
/// the radius of a write nobody makes: the one defect the store cannot catch is the branch above it
/// taken the wrong way, which appends a set where the user asked for a correction.
///
/// **The no-cascade claim is structural rather than defended**, and these tests are what pins that.
/// A session stores no routine id (`TR-15.3`) and carries its own ``PlannedTargetGroup`` rows,
/// written once at the start — so an in-session edit has no path back to the template even in
/// principle. That is exactly the kind of invariant that survives until somebody adds one
/// convenience lookup, which is why it is asserted from both ends: the routine's rows, and a second
/// workout started from it afterwards.
@MainActor
@Suite("Adjusting a planned set's actual result")
struct SessionPlanAdjustmentTests {
    // MARK: - Nothing but the record being edited (FR-15.3.5)

    @Test("An adjustment leaves the routine it was started from alone")
    func adjustmentLeavesTheRoutineAlone() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let before = try await fixture.template()
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 4)

        try await store.adjust(logged, to: Self.values(grams: 100_000, reps: 5))

        // The edit really landed. Without this every assertion below passes against a no-op, which
        // is the shape T-15.03's own retention test was built with.
        #expect(store.exercises.first?.sets.first?.reps == 5)
        let after = try await fixture.template()
        #expect(after.map(\.targetWeight) == [Weight(grams: 100_000), Weight(grams: 85_000)])
        #expect(after.map(\.targetReps) == [5, 8])
        #expect(after.map(\.targetSets) == [1, 3])
        // Whole rows rather than the three columns above, which is what carries the claim past the
        // numbers: `updatedAt` is `G-2.4`'s conflict key, so a template row restamped by an edit
        // that changed nothing about it would outrank a real remote edit of the routine. Compared
        // against a read taken before the adjustment, since the fixture's own rows are stamped as
        // they are written rather than with the day they name.
        #expect(after == before)
    }

    @Test("An adjustment leaves the session's own snapshotted plan alone")
    func adjustmentLeavesTheSessionsPlanAlone() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let planned = try #require(store.exercises.first?.planned)
        // Anchored to literals as well as to itself: two reads of a column nothing writes are
        // equal whatever the column holds.
        #expect(planned.map(\.targetReps) == [5, 8])
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 4)

        try await store.adjust(logged, to: Self.values(grams: 92_500, reps: 3))

        #expect(store.exercises.first?.sets.first?.reps == 3)
        #expect(store.exercises.first?.planned == planned)
    }

    /// The other end of the same claim, and the one a lifter would actually notice: next week's
    /// workout off the same routine opens on the numbers the routine holds, not on last week's.
    @Test("A second workout from the same routine still shows the original target")
    func secondWorkoutStillShowsTheOriginalTarget() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 4)
        try await store.adjust(logged, to: Self.values(grams: 92_500, reps: 3))
        await store.finish()

        try await fixture.start(store)

        let squat = try #require(store.exercises.first)
        #expect(squat.planned.map(\.targetWeight) == [Weight(grams: 100_000), Weight(grams: 85_000)])
        #expect(squat.planned.map(\.targetReps) == [5, 8])
        // A second workout, not the first one read again — the adjusted set is not in it.
        #expect(squat.sets.isEmpty)
    }

    /// "Only the record being edited" is a claim about sibling sets too, and this is the one an
    /// unconditional write loop would break rather than a cascade.
    @Test("An adjustment rewrites the set it was made on and no other")
    func adjustmentRewritesOneSetOnly() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let topSet = try await store.logFirstSquatSet(grams: 100_000, reps: 5)
        let entryID = topSet.entryID
        await store.addSet(toEntryID: entryID, values: Self.values(grams: 85_000, reps: 8))
        let backoff = try #require(store.exercises.first?.sets.last)

        try await store.adjust(backoff, to: Self.values(grams: 85_000, reps: 6))

        let sets = try #require(store.exercises.first?.sets)
        #expect(sets.count == 2)
        #expect(sets.last?.reps == 6)
        #expect(sets.first == topSet)
    }

    // MARK: - The deviation follows it (FR-15.3.2)

    /// Derived at read time rather than stored, so nothing needs invalidating — see
    /// ``PlannedTargetComparison``. This test is what pins that choice against a later
    /// "cache the comparison beside the set" optimisation, which would be correct until the first
    /// adjustment.
    @Test("The deviation indicator follows the adjustment")
    func deviationFollowsTheAdjustment() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 4)
        let before = try #require(store.comparisonForFirstSet())
        #expect(before.reps == .decrease)
        #expect(before.repsDifference == 1)
        #expect(before.isOnTarget == false)

        try await store.adjust(logged, to: Self.values(grams: 100_000, reps: 5))

        let after = try #require(store.comparisonForFirstSet())
        #expect(after.reps == .unchanged)
        #expect(after.repsDifference == 0)
        #expect(after.isOnTarget)
    }

    /// What was `unchanged` becoming a deviation, which is the direction the first test cannot
    /// reach: an adjustment can introduce a miss as well as correct one.
    @Test("An adjustment away from the target raises the indicator it did not have")
    func adjustmentAwayFromTheTargetRaisesTheIndicator() async throws {
        let fixture = try await RoutineFixture()
        let store = try await fixture.startedWorkout()
        let logged = try await store.logFirstSquatSet(grams: 100_000, reps: 5)
        #expect(store.comparisonForFirstSet()?.isOnTarget == true)

        try await store.adjust(logged, to: Self.values(grams: 102_500, reps: 5))

        let after = try #require(store.comparisonForFirstSet())
        #expect(after.weight == .increase)
        #expect(after.weightDifference == Weight(grams: 2_500))
        #expect(after.isOnTarget == false)
    }

    /// One logged set's four columns, with the two nobody here varies fixed.
    private static func values(grams: Int, reps: Int) -> SetEntryValues {
        SetEntryValues(weight: Weight(grams: grams), reps: reps, rpe: nil, isWarmup: false)
    }
}
