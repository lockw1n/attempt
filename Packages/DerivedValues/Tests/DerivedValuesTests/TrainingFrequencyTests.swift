import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.5.1`'s ranking: which exercises the lifter has actually been doing lately, most first.
@Suite("Training frequency")
struct TrainingFrequencyTests {
    @Test("The ranking counts completed working sets, not sessions")
    func therankingCountsSetsRatherThanSessions() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        // Two sessions of five squat sets against three sessions of two bench sets: more bench
        // *days*, more squat *sets*. The requirement is about what is being trained, and a set is
        // the unit every other count in this module already uses.
        for week in 1...2 {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<5).map { working(100_000 + $0, 5) })
        }
        for week in 1...3 {
            try await log.session(
                of: bench, on: weeksAgo(week), sets: (0..<2).map { working(80_000 + $0, 5) })
        }

        #expect(try await recomputer(over: log).mostTrainedExerciseIDs() == [squat, bench])
    }

    @Test("Warmups, failed sets and untrained exercises are not history")
    func onlyCompletedWorkingSetsAreHistory() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let deadlift = try await log.exercise(named: "Deadlift")
        try await log.session(of: squat, on: weeksAgo(1), sets: [working(100_000, 5)])
        try await log.session(
            of: bench,
            on: weeksAgo(1),
            sets: [
                LoggedSet(grams: 60_000, reps: 10, isWarmup: true, isCompleted: true),
                LoggedSet(grams: 100_000, reps: 5, isWarmup: false, isCompleted: false),
            ])

        let ranked = try await recomputer(over: log).mostTrainedExerciseIDs()

        // The bench press was *touched* and not trained, which is the distinction a tile turns on:
        // an exercise whose only sets are warmups produces no estimate either.
        #expect(ranked == [squat])
        #expect(!ranked.contains(bench))
        #expect(!ranked.contains(deadlift))
    }

    @Test("The window is the lookback, so an exercise dropped months ago is not what is trained")
    func therankingIsBoundedByTheLookbackWindow() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let retired = try await log.exercise(named: "Good Morning")
        try await log.session(of: squat, on: weeksAgo(1), sets: [working(100_000, 5)])
        // Twenty sets, and all of them a year old: more training than the squat, and none of it
        // recent. `FR-16.5.1` says "in the lookback window" for exactly this lifter.
        try await log.session(
            of: retired, on: weeksAgo(52), sets: (0..<20).map { working(60_000 + $0, 5) })

        #expect(try await recomputer(over: log).mostTrainedExerciseIDs() == [squat])
    }

    @Test("Equal training ranks the same way on every read")
    func atieResolvesTheSameWayEveryTime() async throws {
        let log = TrainingLog()
        let first = try await log.exercise(id: idA, named: "Back Squat")
        let second = try await log.exercise(id: idB, named: "Bench Press")
        try await log.session(of: first, on: weeksAgo(1), sets: [working(100_000, 5)])
        try await log.session(of: second, on: weeksAgo(2), sets: [working(80_000, 5)])

        let once = try await recomputer(over: log).mostTrainedExerciseIDs()
        let twice = try await recomputer(over: log).mostTrainedExerciseIDs()

        // The order, not merely the membership: `Set(once) == [first, second]` and `once == twice`
        // are both true of a tiebreak that runs the other way, so neither of them tests the rule.
        // `idA` sorts above `idB` as a string, which is the whole of what the rule promises.
        #expect(once == [first, second])
        #expect(twice == [first, second])
    }

    /// A store with nothing in it: no ranking, and so nothing a default tile could be replaced by.
    @Test("An empty log ranks nothing")
    func anemptyLogRanksNothing() async throws {
        let log = TrainingLog()
        try await log.exercise(named: "Back Squat")

        #expect(try await recomputer(over: log).mostTrainedExerciseIDs().isEmpty)
    }

    // MARK: - Fixtures

    /// Two identifiers whose order is fixed, so the tiebreak has something to be asserted against.
    private let idA = UUID(uuidString: "00000000-0000-4000-8000-00000000000A") ?? UUID()
    private let idB = UUID(uuidString: "00000000-0000-4000-8000-00000000000B") ?? UUID()

    /// The actor over `log`, with "now" pinned so the window is a fixed span.
    private func recomputer(over log: TrainingLog) -> PersonalRecordRecomputer {
        PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
    }
}
