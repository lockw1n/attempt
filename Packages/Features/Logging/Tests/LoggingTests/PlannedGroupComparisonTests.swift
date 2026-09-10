import DesignSystem
import Foundation
import PowerliftingCore
import Testing

@testable import Logging

/// `FR-17.9.4`'s difference, measured and said (`DOD-17.7`).
///
/// **The sentence rather than the pair of numbers**, because the sentence is the requirement: the
/// pair reads `30 kg × 8 × 3 · −2 reps`, and a lifter who has to subtract 8 from 10 has not been
/// told the difference.
@Suite("Planned against actual, as a group")
struct PlannedGroupComparisonTests {
    /// `DOD-17.7`'s prescription.
    private static let plan = [
        WeekPlanTarget(id: UUID(), weight: Weight(grams: 30_000), reps: 10, sets: 3)
    ]

    @Test("A group that hit everything says so rather than drawing a signed zero")
    func onTargetSaysSo() {
        #expect(Self.sentence(performed: Self.done(30_000, reps: 10, sets: 3)) == "as planned")
    }

    @Test("Each dimension is stated on its own, and only where it moved")
    func eachDimensionIsStatedOnItsOwn() {
        // DOD-17.7's own case.
        #expect(Self.sentence(performed: Self.done(30_000, reps: 8, sets: 3)) == "−2 reps")
        // The singular, which is why the clause is in the stringsdict rather than the table.
        #expect(Self.sentence(performed: Self.done(30_000, reps: 9, sets: 3)) == "−1 rep")
        #expect(Self.sentence(performed: Self.done(32_500, reps: 10, sets: 3)) == "+2.5 kg")
        #expect(Self.sentence(performed: Self.done(30_000, reps: 10, sets: 4)) == "+1 set")
        #expect(Self.sentence(performed: Self.done(30_000, reps: 10, sets: 1)) == "−2 sets")
    }

    @Test("Two that moved are both stated, in the order the form collects them")
    func twoAtOnce() {
        #expect(Self.sentence(performed: Self.done(27_500, reps: 8, sets: 3)) == "−2.5 kg, −2 reps")
        #expect(
            Self.sentence(performed: Self.done(27_500, reps: 8, sets: 2))
                == "−2.5 kg, −2 reps, −1 set")
    }

    @Test("A blank-weight plan is on target on its reps alone")
    func aBlankWeightPlanIsMeasuredOnWhatItPrescribed() throws {
        // `FR-15.2.2`: treating the absent load as a miss would make every set of a blank-weight
        // group deviate by construction.
        let open = [WeekPlanTarget(id: UUID(), weight: nil, reps: 12, sets: 3)]
        let comparison = try #require(
            PlannedGroupComparison(planned: open, performed: Self.done(60_000, reps: 12, sets: 3)))

        #expect(comparison.weight == nil)
        #expect(comparison.weightDifference == nil)
        #expect(comparison.isOnTarget)
    }

    @Test("A plan with two groups has no single difference, and none is invented")
    func aTwoGroupPlanHasNoSentence() {
        // Measured against the first half it would report a deviation the lifter did not make; the
        // pair still draws both lines, and what it drops is the sentence.
        let split = [
            WeekPlanTarget(id: UUID(), weight: Weight(grams: 100_000), reps: 5, sets: 3),
            WeekPlanTarget(id: UUID(), weight: Weight(grams: 90_000), reps: 8, sets: 2),
        ]

        #expect(PlannedGroupComparison(planned: split, performed: Self.done(100_000, reps: 5, sets: 5)) == nil)
        #expect(PlannedGroupComparison(planned: [], performed: Self.done(100_000, reps: 5, sets: 5)) == nil)
    }

    @Test("Adjacent groups prescribing the same thing are one prescription, not two")
    func adjacentGroupsCollapse() throws {
        // `DayRow.wasAsPlanned`'s rule: the group boundary is the routine's bookkeeping rather than
        // a claim about the work.
        let halves = [
            WeekPlanTarget(id: UUID(), weight: Weight(grams: 100_000), reps: 5, sets: 3),
            WeekPlanTarget(id: UUID(), weight: Weight(grams: 100_000), reps: 5, sets: 2),
        ]
        let comparison = try #require(
            PlannedGroupComparison(planned: halves, performed: Self.done(100_000, reps: 5, sets: 5)))

        #expect(comparison.isOnTarget)
    }

    @Test("Direction follows the arithmetic rather than the sentiment")
    func directionFollowsTheArithmetic() throws {
        let heavier = try #require(
            PlannedGroupComparison(planned: Self.plan, performed: Self.done(35_000, reps: 10, sets: 3)))
        let lighter = try #require(
            PlannedGroupComparison(planned: Self.plan, performed: Self.done(25_000, reps: 10, sets: 3)))

        #expect(heavier.weight == .increase)
        #expect(heavier.weightDifference == Weight(grams: 5_000))
        #expect(lighter.weight == .decrease)
        // Unsigned: the direction is carried separately, and the two cues are drawn separately.
        #expect(lighter.weightDifference == Weight(grams: 5_000))
    }

    /// One group as the form reports it.
    ///
    /// - Parameters:
    ///   - grams: The load.
    ///   - reps: The repetitions.
    ///   - sets: How many.
    /// - Returns: The group.
    private static func done(_ grams: Int, reps: Int, sets: Int) -> WeekPlanTarget {
        WeekPlanTarget(id: UUID(), weight: Weight(grams: grams), reps: reps, sets: sets)
    }

    /// What the pair's Actual line appends, against ``plan``.
    ///
    /// - Parameter performed: What the form says.
    /// - Returns: The sentence.
    private static func sentence(performed: WeekPlanTarget) -> String {
        guard let comparison = PlannedGroupComparison(planned: plan, performed: performed) else {
            return ""
        }
        return PlannedDeviation.sentence(
            comparison, unit: .kilograms, precision: nil, locale: .posix)
    }
}
