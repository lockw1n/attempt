import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Every list a repository returns is ordered, on a key ending in `id.uuidString` and therefore
/// total.
///
/// **Each test seeds ids that sort against the property being read**, rather than asserting that
/// two runs agree. Repeatability is not the claim — which order is. A probe on the other side found
/// exactly that hole: a test that ran the read eight times and compared the answers passed with the
/// id clause deleted, because one store's fetch order does not vary within a run. On this side the
/// failure is louder but the test would be no better: a dictionary's values have no order at all.
@Suite("Conformance — ordering")
struct OrderingConformanceTests {
    @Test("Exercises come back by name, and ties by id", arguments: Subject.all)
    func exercisesAreOrderedByNameThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.exercises.save(exerciseRecord(id: SortedIDs.third, name: "Squat"))
        try await repositories.exercises.save(exerciseRecord(name: "Bench Press"))
        try await repositories.exercises.save(exerciseRecord(id: SortedIDs.second, name: "Squat"))

        let read = try await repositories.exercises.exercises(includingDeleted: false)

        #expect(read.map(\.name) == ["Bench Press", "Squat", "Squat"])
        #expect(read.suffix(2).map(\.id) == [SortedIDs.second, SortedIDs.third])
    }

    @Test("Profiles come back by name, and ties by id", arguments: Subject.all)
    func profilesAreOrderedByNameThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.equipment.save(profileRecord(id: SortedIDs.third, name: "Gym"))
        try await repositories.equipment.save(profileRecord(id: SortedIDs.second, name: "Gym"))
        try await repositories.equipment.save(profileRecord(name: "Basement"))

        let read = try await repositories.equipment.profiles(includingDeleted: false)

        #expect(read.map(\.name) == ["Basement", "Gym", "Gym"])
        #expect(read.suffix(2).map(\.id) == [SortedIDs.second, SortedIDs.third])
    }

    @Test("Sessions come back newest first, and ties by descending id", arguments: Subject.all)
    func sessionsAreOrderedByDateDescending(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let range = fixtureCreatedAt...(fixtureCreatedAt + 2 * fixtureDay)
        try await repositories.workouts.save(sessionRecord(id: SortedIDs.second, date: fixtureCreatedAt))
        try await repositories.workouts.save(
            sessionRecord(date: fixtureCreatedAt + 2 * fixtureDay, notes: "newest"))
        try await repositories.workouts.save(sessionRecord(id: SortedIDs.third, date: fixtureCreatedAt))

        let read = try await repositories.workouts.sessions(in: range, includingDeleted: false)

        #expect(read.first?.notes == "newest")
        #expect(read.suffix(2).map(\.id) == [SortedIDs.third, SortedIDs.second])
    }

    @Test("A range read excludes what falls outside it, both ends", arguments: Subject.all)
    func aRangeReadIsClosed(_ subject: Subject) async throws {
        let repositories = try subject.make()
        try await repositories.bodyweight.save(
            bodyweightRecord(date: fixtureCreatedAt - fixtureDay, grams: 79_000))
        try await repositories.bodyweight.save(
            bodyweightRecord(date: fixtureCreatedAt, grams: 80_000))
        try await repositories.bodyweight.save(
            bodyweightRecord(date: fixtureCreatedAt + fixtureDay, grams: 81_000))
        try await repositories.bodyweight.save(
            bodyweightRecord(date: fixtureCreatedAt + 2 * fixtureDay, grams: 82_000))

        let read = try await repositories.bodyweight.entries(
            in: fixtureCreatedAt...(fixtureCreatedAt + fixtureDay), includingDeleted: false)

        #expect(read.map(\.weight) == [Weight(grams: 81_000), Weight(grams: 80_000)])
    }

    @Test("Training-max history comes back newest effective first", arguments: Subject.all)
    func historyIsOrderedByEffectiveDateDescending(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        // Saved oldest-effective first, so `updatedAt` runs with `effectiveFrom` rather than
        // against it — the ordering claim is about `effectiveFrom` and must not be satisfiable by
        // insertion order alone, which the id clause below is what pins.
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt, grams: 150_000))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(
                id: SortedIDs.second,
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                grams: 160_000))
        try await repositories.trainingMaxes.save(
            trainingMaxHistoryRecord(
                id: SortedIDs.third,
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                grams: 170_000))

        let history = try await repositories.trainingMaxes.history(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(
            history.map(\.newWeight) == [
                Weight(grams: 170_000), Weight(grams: 160_000), Weight(grams: 150_000),
            ])
        #expect(history.prefix(2).map(\.id) == [SortedIDs.third, SortedIDs.second])
    }

    /// The same claim on the other table. `configurationHistory` sorts in its own code in both
    /// implementations, so the case above does not reach it.
    @Test("Training-max configurations come back newest effective first", arguments: Subject.all)
    func configurationsAreOrderedByEffectiveDateDescending(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        // Saved oldest-effective first, for the case above's reason.
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(
                exerciseID: exerciseID, effectiveFrom: fixtureCreatedAt, percentage: 0.80))
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(
                id: SortedIDs.second,
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                percentage: 0.85))
        try await repositories.trainingMaxes.saveConfiguration(
            trainingMaxRecord(
                id: SortedIDs.third,
                exerciseID: exerciseID,
                effectiveFrom: fixtureCreatedAt + fixtureDay,
                percentage: 0.95))

        let history = try await repositories.trainingMaxes.configurationHistory(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(history.map(\.percentage) == [0.95, 0.85, 0.80])
        #expect(history.prefix(2).map(\.id) == [SortedIDs.third, SortedIDs.second])
    }

    @Test("Entries come back by order, and ties by id", arguments: Subject.all)
    func entriesAreOrderedByPositionThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let sessionID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        try await repositories.workouts.save(sessionRecord(id: sessionID))
        for (id, order) in [(SortedIDs.third, 0), (UUID(), 1), (SortedIDs.second, 0)] {
            try await repositories.workouts.save(
                entryRecord(id: id, sessionID: sessionID, exerciseID: exerciseID, order: order))
        }

        let read = try await repositories.workouts.entries(
            forSessionID: sessionID, includingDeleted: false)

        #expect(read.map(\.order) == [0, 0, 1])
        #expect(read.prefix(2).map(\.id) == [SortedIDs.second, SortedIDs.third])
    }

    @Test("An entry's sets come back by order, and ties by id", arguments: Subject.all)
    func setsAreOrderedByPositionThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        for (id, order) in [(SortedIDs.third, 0), (UUID(), 1), (SortedIDs.second, 0)] {
            try await repositories.workouts.save(
                setRecord(id: id, entryID: timeline.entryID, order: order))
        }

        let read = try await repositories.workouts.sets(
            forEntryID: timeline.entryID, includingDeleted: false)

        #expect(read.map(\.order) == [0, 0, 1])
        #expect(read.prefix(2).map(\.id) == [SortedIDs.second, SortedIDs.third])
    }

    /// The order `PersonalRecordCalculator` is handed, and the reason it is a *conformance* claim
    /// rather than an implementation detail.
    ///
    /// `TR-0.2.8` resolves a tie to "the earlier set", which is positional — earlier in the
    /// collection this layer supplied. So a fake that returned a different order would give the
    /// caller a defensible answer to a different question, silently, and only between sets that
    /// weigh the same. All four clauses are exercised, and no two of them agree.
    @Test("The personal-record feed is ordered on all four keys", arguments: Subject.all)
    func theFeedOrderIsTotal(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let early = try await repositories.timeline(
            exerciseID: exerciseID, date: fixtureCreatedAt, entryOrder: 0)
        let alsoEarly = try await repositories.timeline(
            exerciseID: exerciseID,
            sessionID: early.sessionID,
            date: fixtureCreatedAt,
            entryOrder: 1)
        let late = try await repositories.timeline(
            exerciseID: exerciseID, date: fixtureCreatedAt + fixtureDay, entryOrder: 0)

        // Saved in an order matching none of the four keys.
        try await repositories.workouts.save(
            setRecord(entryID: late.entryID, order: 0, grams: 40_000))
        try await repositories.workouts.save(
            setRecord(entryID: alsoEarly.entryID, order: 1, grams: 30_000))
        // `SortedIDs.first`, and it is load-bearing: this set is the only one whose position is
        // decided by the *entry order* clause alone. Left to `UUID()` it sorted after `a` and `b`
        // anyway, so dropping that clause from the key left the answer unchanged — a probe
        // survived on it. Given the smallest id in the fixture, collapsing entry order pulls it to
        // the front and the assertion moves.
        try await repositories.workouts.save(
            setRecord(
                id: SortedIDs.first, entryID: alsoEarly.entryID, order: 0, grams: 25_000))
        try await repositories.workouts.save(
            setRecord(id: SortedIDs.third, entryID: early.entryID, order: 0, grams: 10_000))
        try await repositories.workouts.save(
            setRecord(id: SortedIDs.second, entryID: early.entryID, order: 0, grams: 20_000))

        let feed = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(
            feed.map(\.weight) == [
                Weight(grams: 20_000),  // session 1, entry 0, set 0, id a
                Weight(grams: 10_000),  // session 1, entry 0, set 0, id b
                Weight(grams: 25_000),  // session 1, entry 1, set 0
                Weight(grams: 30_000),  // session 1, entry 1, set 1
                Weight(grams: 40_000),  // session 2
            ])
    }

    /// `FR-16.4.2`: an uncompleted set inside a workout that has not ended is one nobody has
    /// attempted, and it is not history.
    ///
    /// **The same fixture as the filter test above, with one column moved.** A session's `endedAt`
    /// is the whole difference between "the feed passes incomplete sets through" and this, which is
    /// what makes the exclusion a property of the session rather than of the set.
    ///
    /// The warmup and the completed set stay, so this cannot pass by dropping the entry.
    @Test(
        "A pending set is not in the feed; the same set in a finished workout is",
        arguments: Subject.all)
    func theFeedExcludesPendingSets(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let timeline = try await repositories.timeline(exerciseID: exerciseID, endedAt: nil)
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 0, grams: 60_000, isWarmup: true))
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 1, grams: 100_000, isCompleted: false))
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 2, grams: 110_000))

        let open = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(open.map(\.weight) == [Weight(grams: 60_000), Weight(grams: 110_000)])

        // The row is untouched — it is the session ending that puts it back, as a failed set.
        try await repositories.workouts.save(
            sessionRecord(id: timeline.sessionID, endedAt: fixtureCreatedAt))
        let finished = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)
        #expect(
            finished.map(\.weight)
                == [Weight(grams: 60_000), Weight(grams: 100_000), Weight(grams: 110_000)])
    }

    /// `TR-0.2.8`'s tie-break, at the one key `date` cannot decide.
    ///
    /// **Two workouts on one training day.** `date` is the day rather than an instant, so the first
    /// set of each ties on the day and the entry order; without `startedAt` the two fall through to
    /// a minted identifier, which says nothing about which came first. The earlier session is given
    /// the *higher* id, so a fall-through fails loudly rather than by luck.
    @Test("Two workouts on one day are ordered by when they started", arguments: Subject.all)
    func sameDayWorkoutsOrderByStart(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let morning = try await repositories.timeline(
            exerciseID: exerciseID,
            sessionID: SortedIDs.third,
            date: fixtureCreatedAt,
            startedAt: fixtureCreatedAt)
        let evening = try await repositories.timeline(
            exerciseID: exerciseID,
            sessionID: SortedIDs.first,
            date: fixtureCreatedAt,
            startedAt: fixtureCreatedAt + fixtureDay / 2)

        try await repositories.workouts.save(
            setRecord(entryID: evening.entryID, order: 0, grams: 110_000))
        try await repositories.workouts.save(
            setRecord(entryID: morning.entryID, order: 0, grams: 100_000))

        let feed = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)

        #expect(feed.map(\.weight) == [Weight(grams: 100_000), Weight(grams: 110_000)])
    }

    @Test("The feed passes warmups and incomplete sets through", arguments: Subject.all)
    func theFeedFiltersNothing(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        let timeline = try await repositories.timeline(exerciseID: exerciseID)
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 0, grams: 60_000, isWarmup: true))
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 1, grams: 100_000, isCompleted: false))
        try await repositories.workouts.save(
            setRecord(entryID: timeline.entryID, order: 2, grams: 110_000))

        let feed = try await repositories.workouts.sets(
            forExerciseID: exerciseID, includingDeleted: false)

        // Filtering here is not an optimisation; it would shift every `PersonalRecord.setOffset`
        // after the removed set, and the calculator excludes them itself.
        #expect(feed.count == 3)
        #expect(feed.map(\.isWarmup) == [true, false, false])
        #expect(feed.map(\.isCompleted) == [true, false, true])
    }

    @Test("The feed is empty for an exercise nothing was logged against", arguments: Subject.all)
    func anUnusedExerciseHasNoFeed(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let timeline = try await repositories.timeline()
        try await repositories.workouts.save(setRecord(entryID: timeline.entryID))
        let unused = UUID()
        try await repositories.exercises.save(exerciseRecord(id: unused, name: "Bench Press"))

        #expect(
            try await repositories.workouts.sets(forExerciseID: unused, includingDeleted: true)
                .isEmpty)
    }
}
