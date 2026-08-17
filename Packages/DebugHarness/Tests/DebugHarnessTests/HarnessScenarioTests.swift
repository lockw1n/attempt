import DebugHarness
import Foundation
import Persistence
import PowerliftingCore
import RepositoryFakes
import Testing

/// `DOD-0.3`: the harness seeds, logs, and reports the records the fixed log actually holds.
///
/// Every number below is stated as a literal rather than recomputed from the scenario, so a change
/// to either side fails instead of agreeing with itself.
struct HarnessScenarioTests {
    /// A fixed instant, so a run is reproducible and the two sessions land in a known order.
    static let now = Date(timeIntervalSince1970: 1_770_000_000)

    /// One expected rep max: the N, the load in grams, and the set holding it.
    struct ExpectedRepMax {
        let reps: Int
        let grams: Int
        let offset: Int
    }

    /// The rep maxes the eight logged sets hold.
    ///
    /// 105 kg × 3 survives from the older session, which the newer one never beat for three reps;
    /// the 1RM and the best e1RM are held by different sets.
    static let expectedRepMaxes = [
        ExpectedRepMax(reps: 1, grams: 120_000, offset: 7),
        ExpectedRepMax(reps: 2, grams: 112_500, offset: 6),
        ExpectedRepMax(reps: 3, grams: 105_000, offset: 2),
        ExpectedRepMax(reps: 4, grams: 102_500, offset: 5),
        ExpectedRepMax(reps: 5, grams: 102_500, offset: 5),
    ]

    @Test("the records are the ones the fixed log holds")
    func recordsOverTheFakes() async throws {
        let report = try await Self.runOverFakes()

        #expect(report.sets.count == 8)
        #expect(report.exerciseName == "Back Squat")
        #expect(report.formula == .epley)
        #expect(report.records.repMaxes.count == Self.expectedRepMaxes.count)
        for expected in Self.expectedRepMaxes {
            let record = try #require(report.records.repMax(forReps: expected.reps))
            #expect(record.weight == Weight(grams: expected.grams))
            #expect(record.setOffset == expected.offset)
        }
        // Nothing reached six reps, so `PersonalRecords.repRange`'s upper half is absent rather
        // than present at a weight of zero.
        for reps in 6...10 {
            #expect(report.records.repMax(forReps: reps) == nil)
        }
        let best = try #require(report.records.bestE1RM)
        #expect(best.weight == Weight(grams: 124_000))
        #expect(best.setOffset == 7)
    }

    @Test("the SwiftData store answers identically")
    func recordsOverTheRealStore() async throws {
        let stack = try PersistenceStack(location: .inMemory)
        let stored = try await HarnessScenario(
            exercises: stack.exercises, workouts: stack.workouts
        ).run(at: Self.now)

        // Neither the report nor anything in it carries a row id or a date, so two fresh stores
        // seeded and logged the same way produce equal values — which is the claim `DOD-0.3` makes
        // about the stack running end to end, rather than about the executable that opens one.
        #expect(stored == (try await Self.runOverFakes()))
    }

    @Test("a warmup and an abandoned set hold no estimate, and no record")
    func refusedSetsHoldNothing() async throws {
        let report = try await Self.runOverFakes()

        #expect(report.sets[0].isWarmup)
        #expect(report.sets[0].estimate == nil)
        #expect(report.sets[3].isCompleted == false)
        #expect(report.sets[3].estimate == nil)
        // 110 kg × 1 was abandoned and is heavier than everything before it, so it would hold the
        // 1RM of the older session outright had completion been ignored.
        #expect(report.sets[3].weight == Weight(grams: 110_000))
        // A rated working set does estimate: 100 kg × 5 under Epley is 100 000 × (1 + 5/30).
        #expect(report.sets[1].estimate == Weight(grams: 116_667))
        #expect(report.sets[1].rpe == 8)
    }

    @Test("the first run inserts the whole catalogue and the second writes nothing")
    func seedingIsAMerge() async throws {
        let stack = InMemoryRepositoryStack()
        let scenario = HarnessScenario(exercises: stack.exercises, workouts: stack.workouts)

        let first = try await scenario.run(at: Self.now)
        #expect(first.seed.inserted > 0)
        #expect(first.seed.writeCount == first.seed.inserted)
        #expect(first.seed.updated == 0)
        #expect(first.seed.archived == 0)
        #expect(first.seed.unchanged == 0)

        let second = try await scenario.run(at: Self.now)
        #expect(second.seed.writeCount == 0)
        #expect(second.seed.unchanged == first.seed.inserted)
        // The log half is not a merge and does not pretend to be: a second run logs the history a
        // second time, which is why the executable opens a throwaway store.
        #expect(second.sets.count == 16)
    }

    @Test("a name the catalogue does not carry is refused")
    func unknownExerciseIsRefused() async throws {
        let stack = InMemoryRepositoryStack()
        let scenario = HarnessScenario(
            exercises: stack.exercises,
            workouts: stack.workouts,
            exerciseName: "Nordic Hamstring Curl With A Hat On")

        await #expect(throws: HarnessError.exerciseNotFound(name: "Nordic Hamstring Curl With A Hat On")) {
            try await scenario.run(at: Self.now)
        }
    }

    @Test("the printed report carries the numbers a reader is looking for")
    func renderedText() async throws {
        let text = try await Self.runOverFakes().text

        #expect(text.contains("exercise   Back Squat"))
        #expect(text.contains("formula    epley"))
        // Kilograms at G-3.3's display precision beside the grams actually stored (G-1.1).
        #expect(text.contains("102.5 kg × 5"))
        #expect(text.contains("RPE 8.5"))
        #expect(text.contains("warmup"))
        #expect(text.contains("incomplete"))
        #expect(text.contains(" 1RM  120.0 kg (120000 g)"))
        #expect(text.contains(" 6RM  —"))
        #expect(text.contains("best e1RM  124.0 kg (124000 g)"))
        #expect(text.contains("from set [7]"))
    }

    /// The scenario over one in-memory fake stack, at ``now``.
    static func runOverFakes() async throws -> HarnessReport {
        let stack = InMemoryRepositoryStack()
        return try await HarnessScenario(exercises: stack.exercises, workouts: stack.workouts)
            .run(at: now)
    }
}
