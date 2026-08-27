import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.9.1`'s "delta since the previous value": what the current estimate replaced, and the four
/// cases where there is nothing to compare it with.
@Suite("Estimated maximum, and what it moved from")
struct EstimateDeltaTests {
    @Test("The previous value is the best estimate from before the current one's day")
    func thePreviousValueIsTheBestEarlierOne() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(4), sets: [working(100_000, 5)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(110_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        // Epley: 110 kg × 5 → 128,333 g; 100 kg × 5 → 116,667 g.
        #expect(estimate.record?.weight == Weight(grams: 128_333))
        #expect(estimate.previous?.weight == Weight(grams: 116_667))
        #expect(estimate.delta == Weight(grams: 11_666))
    }

    /// **The case that shows the delta cannot fall.** A lighter session does not lower the estimate
    /// — the heavier one is still the best inside the window, so it is still what the tile shows,
    /// and nothing precedes it. Together with the tie rule below this is why
    /// ``DerivedValues/EstimatedMax/delta`` is strictly positive wherever it is not `nil`.
    @Test("A lighter session leaves the estimate, and its delta, where they were")
    func alighterSessionDoesNotLowerTheEstimate() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(4), sets: [working(110_000, 5)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        // The heavier set is still the best in the window, so the *current* estimate is the older
        // one — and nothing precedes it. The number on the tile did not move, so there is no delta
        // rather than a negative one, and no screen ever draws a fall.
        #expect(estimate.record?.weight == Weight(grams: 128_333))
        #expect(estimate.previous == nil)
        #expect(estimate.delta == nil)
    }

    /// The reason the comparison is by day rather than by set: two sets in one session are a ranking
    /// within that session, not a change over time.
    @Test("A second set on the same day is not a previous value")
    func thesamedaysBackOffSetIsNotAPreviousValue() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID,
            on: weeksAgo(1),
            sets: [working(110_000, 5), working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record?.weight == Weight(grams: 128_333))
        #expect(estimate.previous == nil)
    }

    /// `FR-1.7.1`'s window applies to the comparison as well as to the number: a value the tile
    /// stopped showing months ago is not what today's number moved from.
    @Test("A value from outside the window is not a previous value")
    func aValueOutsideTheWindowIsNotAPreviousValue() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(30), sets: [working(200_000, 5)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record?.weight == Weight(grams: 116_667))
        #expect(estimate.previous == nil)
        #expect(estimate.delta == nil)
    }

    /// **A tie is won by the earlier set** (`PersonalRecordCalculator`'s rule, not this one's), so an
    /// estimate that was matched and not beaten keeps the day it was first set on — and therefore has
    /// nothing before it. That is the honest reading: the number on the tile has not moved since the
    /// day it appeared, so there is no change to report rather than a change of zero.
    @Test("An estimate that was matched and not beaten has no previous value")
    func amatchedEstimateHasNoPreviousValue() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(4), sets: [working(100_000, 5)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.record?.achievedAt == weeksAgo(4))
        #expect(estimate.previous == nil)
        #expect(estimate.delta == nil)
    }

    /// A refused set is not a previous value either — the comparison reads what the estimator
    /// accepted, which is what makes the delta a change in the *displayed* number.
    @Test("A refused earlier set leaves nothing to compare with")
    func arefusedEarlierSetIsNotAPreviousValue() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(
            of: exerciseID,
            on: weeksAgo(4),
            sets: [LoggedSet(grams: 100_000, reps: 5, isWarmup: true, isCompleted: true)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(100_000, 5)])

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.previous == nil)
    }

    /// `FR-1.7.5`: a number the user typed has no history behind it, so a tile draws the manual mark
    /// where a delta would be.
    @Test("A manual override carries no previous value and no delta")
    func amanualOverrideHasNoDelta() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        try await log.session(of: exerciseID, on: weeksAgo(4), sets: [working(100_000, 5)])
        try await log.session(of: exerciseID, on: weeksAgo(1), sets: [working(110_000, 5)])
        let subject = recomputer(over: log)
        try await subject.setManualEstimate(Weight(grams: 150_000), forExerciseID: exerciseID)

        let estimate = try await subject.estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.manual == Weight(grams: 150_000))
        #expect(estimate.previous == nil)
        #expect(estimate.delta == nil)
    }

    @Test("An absent estimate carries no delta")
    func anabsentEstimateHasNoDelta() async throws {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()

        let estimate = try await recomputer(over: log).estimatedMax(forExerciseID: exerciseID)

        #expect(estimate.absence == .noSetsLogged)
        #expect(estimate.delta == nil)
    }

    // MARK: - Fixtures

    /// A recomputer over `log`, with "now" pinned to the fixture reference.
    private func recomputer(over log: TrainingLog) -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
    }
}
