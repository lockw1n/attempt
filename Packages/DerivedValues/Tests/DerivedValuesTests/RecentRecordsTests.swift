import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-1.6.5`'s feed: what the cache's rows become once they are events rather than a table.
@Suite("Recent records — the feed")
struct RecentRecordFeedTests {
    /// One cached row, with only the columns the feed reads varying.
    ///
    /// The labels are short because the assertions below are about *which rows group together*, and
    /// a call spelling out six columns hides that.
    private func row(
        _ exerciseID: UUID,
        reps: Int,
        sets: Int = 1,
        set sourceSetID: UUID,
        on achievedAt: Date,
        grams: Int = 100_000,
        previous: Int? = nil,
        version: Int = PersonalRecordCalculator.computationVersion
    ) -> PersonalRecordCache {
        PersonalRecordCache(
            id: UUID(),
            createdAt: achievedAt,
            updatedAt: achievedAt,
            deletedAt: nil,
            exerciseID: exerciseID,
            repCount: reps,
            setCount: sets,
            weight: Weight(grams: grams),
            sourceSetID: sourceSetID,
            achievedAt: achievedAt,
            previousWeight: previous.map(Weight.init(grams:)),
            computationVersion: version)
    }

    /// Since `FR-17.2.1` a run writes one row, so a cache naming one set three times is one this
    /// build did not write — a restored backup. It is still **one** entry, and the scheme it reports
    /// is the maximal row rather than whichever came back first.
    @Test("Several rows under one set are one entry, at the maximal row's scheme")
    func oneSetIsOneEntry() {
        let (exercise, source) = (UUID(), UUID())
        let day = weeksAgo(1)
        let cached = (1...3).map { row(exercise, reps: $0, set: source, on: day, grams: 140_000) }

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.first?.scheme == RecordScheme(reps: 3, sets: 1))
        #expect(feed.first?.weight == Weight(grams: 140_000))
        #expect(feed.first?.sourceSetID == source)
        #expect(feed.first?.achievedAt == day)
    }

    /// `DOD-17.3` at the feed: one row per run, and the row names the cell that was performed.
    @Test("One run is one row, at the cell it was performed at")
    func oneRunIsOneRow() {
        let cached = [row(UUID(), reps: 8, set: UUID(), on: weeksAgo(1))]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.first?.scheme == RecordScheme(reps: 8, sets: 1))
        #expect(feed.first?.weight == Weight(grams: 100_000))
    }

    /// `G-1.5`: a row this build did not compute is not an answer this build may show, and
    /// recomputing it here would be the catalogue pass `NFR-1.6` rules out.
    @Test("A row produced under other rules is dropped rather than shown")
    func aStaleRowIsDropped() {
        let current = UUID()
        let other = PersonalRecordCalculator.computationVersion + 1
        let cached = [
            row(UUID(), reps: 3, set: UUID(), on: weeksAgo(1), version: other),
            row(UUID(), reps: 3, set: current, on: weeksAgo(4)),
        ]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.map(\.sourceSetID) == [current])
    }

    /// The whole reason this is not a filtered view over the cache: four *rows* can be one set.
    @Test("The limit counts PR-setting sets, not cached rows")
    func theLimitCountsEvents() {
        let exercise = UUID()
        let sets = (0..<3).map { _ in UUID() }
        let cached = sets.enumerated().flatMap { index, source in
            (1...4).map { row(exercise, reps: $0, set: source, on: weeksAgo(index)) }
        }

        let feed = RecentRecord.feed(from: cached, limit: 2)

        #expect(cached.count == 12)
        #expect(feed.map(\.sourceSetID) == [sets[0], sets[1]])
    }

    @Test("A group takes the position of its first row, so the cache's order is kept")
    func theOrderIsTheCaches() {
        let (recent, older) = (UUID(), UUID())
        let (squat, bench) = (UUID(), UUID())
        // Interleaved on purpose: two exercises' records share a session's date, so the repository's
        // tie-break can put another exercise's row between two of one set's.
        let cached = [
            row(squat, reps: 1, set: recent, on: weeksAgo(1), grams: 200_000),
            row(bench, reps: 5, set: older, on: weeksAgo(6), grams: 90_000),
            row(squat, reps: 2, set: recent, on: weeksAgo(1), grams: 200_000),
        ]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.map(\.sourceSetID) == [recent, older])
        #expect(feed.first?.scheme == RecordScheme(reps: 2, sets: 1))
    }

    /// A cache naming one set at two unrelated cells is one no build of this app wrote — a restored
    /// backup. It is grouped rather than refused, and the maximal row is what the row reports.
    @Test("Unrelated rows under one set group to the maximal one rather than being refused")
    func unrelatedRowsGroupToTheMaximal() {
        let (exercise, source) = (UUID(), UUID())
        let cached = [1, 4].map { row(exercise, reps: $0, set: source, on: weeksAgo(2)) }

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.map(\.scheme) == [RecordScheme(reps: 4, sets: 1)])
    }

    @Test("Two exercises' records are never merged, even sharing a set identifier")
    func exercisesAreNotMerged() {
        let source = UUID()
        let (mine, theirs) = (UUID(), UUID())
        let cached = [
            row(mine, reps: 1, set: source, on: weeksAgo(1)),
            row(theirs, reps: 1, set: source, on: weeksAgo(1)),
        ]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.map(\.exerciseID) == [mine, theirs])
    }

    // MARK: - FR-17.2.1, one row per run

    /// `DOD-17.2` at the feed: a `90 × 5 × 5` is one entry, at `5×5`, and nothing else moved.
    @Test("A run of five by five is one entry at its own cell")
    func aVolumeRunIsOneEntryAtItsOwnCell() {
        let (exercise, source) = (UUID(), UUID())
        let cached = [row(exercise, reps: 5, sets: 5, set: source, on: weeksAgo(1), grams: 90_000, previous: 80_000)]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.first?.scheme == RecordScheme(reps: 5, sets: 5))
        #expect(feed.first?.weight == Weight(grams: 90_000))
        #expect(feed.first?.previous == Weight(grams: 80_000))
    }

    /// `FR-16.3.2` shows a run's **maximal** scheme, so the delta beside it has to be that scheme's
    /// — a run that is a first-ever `5 × 5` and an improvement at `5 × 1` is a baseline `5 × 5`.
    @Test("The beaten load is the maximal scheme's, not any cell's")
    func theBeatenLoadIsTheMaximalSchemes() {
        let (exercise, source) = (UUID(), UUID())
        let day = weeksAgo(1)
        let cached = [
            row(exercise, reps: 5, sets: 1, set: source, on: day, previous: 95_000),
            row(exercise, reps: 5, sets: 2, set: source, on: day, previous: 90_000),
            row(exercise, reps: 5, sets: 3, set: source, on: day),
        ]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.first?.previous == nil)
        #expect(feed.first?.isBaseline == true)
        #expect(feed.first?.delta == nil)
    }

    @Test("An improvement carries the maximal scheme's beaten load and its delta")
    func anImprovementCarriesItsDelta() {
        let (exercise, source) = (UUID(), UUID())
        let cached = [
            row(exercise, reps: 5, sets: 1, set: source, on: weeksAgo(1), grams: 105_000),
            row(
                exercise,
                reps: 5,
                sets: 3,
                set: source,
                on: weeksAgo(1),
                grams: 105_000,
                previous: 100_000),
        ]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.first?.previous == Weight(grams: 100_000))
        #expect(feed.first?.delta == Weight(grams: 5_000))
        #expect(feed.first?.isBaseline == false)
    }

    /// A single set is the `sets == 1` column, and `FR-17.2.3` writes it `8 reps` rather than
    /// `8RM` — but the feed row carries the cell either way, which is what this pins.
    @Test("A single set's entry names a one-set cell")
    func aSingleSetsEntryNamesAOneSetCell() {
        let (exercise, source) = (UUID(), UUID())
        let cached = [row(exercise, reps: 3, set: source, on: weeksAgo(1))]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.first?.scheme == RecordScheme(reps: 3, sets: 1))
        #expect(feed.first?.scheme.sets == 1)
    }

    @Test("A limit of nothing draws nothing")
    func noLimitIsNoFeed() {
        let cached = [row(UUID(), reps: 1, set: UUID(), on: weeksAgo(1))]

        #expect(RecentRecord.feed(from: cached, limit: 0).isEmpty)
        #expect(RecentRecord.feed(from: cached, limit: -1).isEmpty)
        #expect(RecentRecord.feed(from: [], limit: 10).isEmpty)
    }
}

/// The read end to end, over a store that was actually written to — this task's own *done when*.
@Suite("Recent records — across exercises")
struct RecentRecordsAcrossExercisesTests {
    /// Three exercises, each trained once, in an order that is neither chronological nor reversed —
    /// so nothing under test can pass by insertion order.
    private func trainedLog() async throws -> (log: TrainingLog, exercises: [UUID]) {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        let deadlift = try await log.exercise(named: "Deadlift")
        try await log.session(of: squat, on: weeksAgo(6), sets: [working(140_000, 3)])
        try await log.session(of: bench, on: weeksAgo(1), sets: [working(100_000, 5)])
        try await log.session(of: deadlift, on: weeksAgo(3), sets: [working(200_000, 1)])
        return (log, [squat, bench, deadlift])
    }

    @Test("The feed spans every exercise, newest first")
    func theFeedIsChronologicalAcrossExercises() async throws {
        let (log, exercises) = try await trainedLog()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        for exerciseID in exercises {
            try await recomputer.recompute(forExerciseID: exerciseID)
        }

        let feed = try await recomputer.recentRecords(limit: 10)

        #expect(feed.map(\.exerciseID) == [exercises[1], exercises[2], exercises[0]])
        #expect(feed.map(\.achievedAt) == [weeksAgo(1), weeksAgo(3), weeksAgo(6)])
        // One cell each, and it is the one performed: `100 × 5` is the 5-rep cell, the deadlift's
        // single the 1-rep cell, the squat's `140 × 3` the 3-rep cell (`FR-17.2.1`).
        #expect(
            feed.map(\.scheme) == [
                RecordScheme(reps: 5, sets: 1),
                RecordScheme(reps: 1, sets: 1),
                RecordScheme(reps: 3, sets: 1),
            ])
    }

    @Test("An exercise nothing recomputed contributes nothing")
    func anUncomputedExerciseIsAbsent() async throws {
        let (log, exercises) = try await trainedLog()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: exercises[0])

        let feed = try await recomputer.recentRecords(limit: 10)

        #expect(feed.map(\.exerciseID) == [exercises[0]])
    }
}
