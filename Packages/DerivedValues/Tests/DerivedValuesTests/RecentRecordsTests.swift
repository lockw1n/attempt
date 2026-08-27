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
        set sourceSetID: UUID,
        on achievedAt: Date,
        grams: Int = 100_000,
        version: Int = PersonalRecordCalculator.computationVersion
    ) -> PersonalRecordCache {
        PersonalRecordCache(
            id: UUID(),
            createdAt: achievedAt,
            updatedAt: achievedAt,
            deletedAt: nil,
            exerciseID: exerciseID,
            repCount: reps,
            weight: Weight(grams: grams),
            sourceSetID: sourceSetID,
            achievedAt: achievedAt,
            computationVersion: version)
    }

    @Test("Rows one set produced are one entry, spanning the N's it holds")
    func oneSetIsOneEntry() {
        let (exercise, source) = (UUID(), UUID())
        let day = weeksAgo(1)
        let cached = (1...3).map { row(exercise, reps: $0, set: source, on: day, grams: 140_000) }

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.first?.reps == 1...3)
        #expect(feed.first?.weight == Weight(grams: 140_000))
        #expect(feed.first?.sourceSetID == source)
        #expect(feed.first?.achievedAt == day)
    }

    @Test("A set holding one N reads as that N alone")
    func oneRepMaxIsASingleN() {
        let cached = [row(UUID(), reps: 8, set: UUID(), on: weeksAgo(1))]

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.count == 1)
        #expect(feed.first?.reps == 8...8)
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
        #expect(feed.first?.reps == 1...2)
    }

    /// The N's one set holds are contiguous by construction, so this is a store that was edited
    /// outside the app — a restored backup. Spanned rather than refused: the entry is still true
    /// about the heaviest and the lightest N it stands at.
    @Test("A gap in one set's rows is spanned rather than refused")
    func aGapIsSpanned() {
        let (exercise, source) = (UUID(), UUID())
        let cached = [1, 4].map { row(exercise, reps: $0, set: source, on: weeksAgo(2)) }

        let feed = RecentRecord.feed(from: cached, limit: 10)

        #expect(feed.map(\.reps) == [1...4])
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
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        for exerciseID in exercises {
            try await recomputer.recompute(forExerciseID: exerciseID)
        }

        let feed = try await recomputer.recentRecords(limit: 10)

        #expect(feed.map(\.exerciseID) == [exercises[1], exercises[2], exercises[0]])
        #expect(feed.map(\.achievedAt) == [weeksAgo(1), weeksAgo(3), weeksAgo(6)])
        // The bench's 100 × 5 holds the 1RM through the 5RM, the deadlift's single holds the 1RM
        // alone, and the squat's 140 × 3 holds three. One entry each, and the ranges say which.
        #expect(feed.map(\.reps) == [1...5, 1...1, 1...3])
    }

    @Test("An exercise nothing recomputed contributes nothing")
    func anUncomputedExerciseIsAbsent() async throws {
        let (log, exercises) = try await trainedLog()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: exercises[0])

        let feed = try await recomputer.recentRecords(limit: 10)

        #expect(feed.map(\.exerciseID) == [exercises[0]])
    }
}
