import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `NFR-1.6`'s figure, measured here as a first pass: PR and e1RM recalculation over 15,000 sets in
/// under 500 ms, off the main thread.
///
/// **This is not the formal verification, and the difference matters when reading the number.**
/// `T-1.83` owns that, against the real store. The subject here is `RepositoryFakes`, so what this
/// measures is the *pipeline* — the walk's ordering, the two calculators over 15,000 records, the
/// dating of the eleven record-holders and the cache write — with a dictionary where SwiftData will
/// be. A fake is faster than a store, so this can only fail early, never pass falsely: a number
/// anywhere near the budget here would mean the budget is already gone before persistence is
/// involved.
///
/// The ceiling below is `NFR-1.6`'s own, unrelaxed. If it ever fails on slower hardware, the
/// finding is the *measured* figure rather than the failure — record it and take it to `T-1.83`,
/// which is where the requirement is actually discharged.
@Suite("Recompute at scale")
struct RecomputeScaleTests {
    /// The requirement's population.
    private static let setCount = 15_000

    /// 1,500 sessions of ten sets each, one exercise, ascending so that the last set holds every
    /// record — the worst case for the tie-break, which only ever moves on a strict improvement.
    private func hugeHistory() async throws -> (log: TrainingLog, exerciseID: UUID) {
        let log = TrainingLog()
        let exerciseID = try await log.exercise()
        for session in 0..<(Self.setCount / 10) {
            try await log.session(
                of: exerciseID,
                on: weeksAgo(1_600 - session),
                sets: (0..<10).map { working(50_000 + session * 10 + $0, 5) })
        }
        return (log, exerciseID)
    }

    @Test("Recomputing over 15,000 sets stays inside NFR-1.6's budget")
    func fifteenThousandSets() async throws {
        let (log, exerciseID) = try await hugeHistory()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        let logged = try await log.repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(logged.count == Self.setCount)

        let clock = ContinuousClock()
        let elapsed = try await clock.measure {
            try await recomputer.recompute(forExerciseID: exerciseID)
        }

        // Printed whether or not it passes: the figure is the finding, and a green run that says
        // nothing leaves the next task guessing at how much headroom persistence has to spend.
        print("NFR-1.6 first pass: \(Self.setCount) sets recomputed in \(elapsed)")
        #expect(elapsed < .milliseconds(500))

        // The measurement is worthless if it computed nothing: the last set is the heaviest, so it
        // holds all five reachable rep maxes. It holds no *estimate* — every session here is at
        // least 101 weeks old, so `FR-1.7.1`'s window is empty over this fixture and what the
        // window itself costs is not part of this number. That read is bounded by the window rather
        // than by the history, and is asserted off the trigger path in `EstimatedMaxTests`.
        let cached = try await log.repositories.personalRecords.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(cached.map(\.repCount) == [1, 2, 3, 4, 5])
        #expect(cached.allSatisfy { $0.sourceSetID == logged[Self.setCount - 1].id })
    }

    /// The read `G-1.5`'s version exists to make cheap, at the size where cheap matters.
    @Test("A current cache answers the same history without walking it")
    func aCurrentCacheSkipsTheWalk() async throws {
        let (log, exerciseID) = try await hugeHistory()
        let seeding = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await seeding.recompute(forExerciseID: exerciseID)
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let reader = PersonalRecordRecomputer(
            workouts: counting,
            exercises: InMemoryRepositoryStack().exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let read = try await reader.repMaxes(forExerciseID: exerciseID)

        #expect(read.map(\.reps) == [1, 2, 3, 4, 5])
        #expect(await counting.exerciseWalks == 0)
    }
}
