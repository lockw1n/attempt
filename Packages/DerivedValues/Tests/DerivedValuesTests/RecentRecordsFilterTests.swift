import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.3`'s configuration, applied: what the feed reports on once the settings row narrows it.
@Suite("Recent records — the feed's configuration")
struct RecentRecordsFilterTests {
    /// A log holding a squat programme and one accessory lift, with the cache written for both.
    ///
    /// **Shaped like review finding 03**, which is what this whole task is against: the squat is
    /// trained repeatedly and improves, and the accessory is performed once at a light load. Left
    /// unfiltered the accessory's first-ever set is a record like any other and sits at the top of
    /// the feed, because it is the most recent thing that happened.
    private struct Programme {
        let log: TrainingLog
        let recomputer: PersonalRecordRecomputer
        let squat: UUID
        let kickback: UUID
    }

    private func programme() async throws -> Programme {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let kickback = try await log.exercise(named: "Triceps Kickback")
        // Three 5 × 3 runs, each heavier than the last: the third beats the second at 5 × 3, so the
        // squat's newest record is an improvement rather than a baseline.
        for (week, grams) in [(6, 120_000), (4, 130_000), (2, 140_000)] {
            try await log.session(
                of: squat,
                on: weeksAgo(week),
                sets: (0..<3).map { _ in working(grams, 5) })
        }
        // One light single, once, and never before: a baseline at a scheme trained once.
        try await log.session(of: kickback, on: weeksAgo(1), sets: [working(10_000, 12)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        try await recomputer.recompute(forExerciseID: kickback)
        return Programme(log: log, recomputer: recomputer, squat: squat, kickback: kickback)
    }

    /// The state the filter replaces — kept as a test, because every assertion below is only worth
    /// something if the unfiltered feed really does lead with the accessory.
    @Test("Unfiltered, the newest record leads however light the lift")
    func unfilteredLeadsWithTheAccessory() async throws {
        let fixture = try await programme()

        let feed = try await fixture.recomputer.recentRecords(limit: 5, filter: .unfiltered)

        #expect(feed.first?.exerciseID == fixture.kickback)
        #expect(feed.first?.isBaseline == true)
    }

    /// `DOD-16.2`, over a fixture rather than the author's log: **under untouched defaults the feed
    /// shows no baseline accessory record, and every row shows what it beat.**
    ///
    /// The defaults are read off the settings row rather than restated here, which is what makes
    /// this a test of `FR-16.3.1` and `FR-16.3.4` as shipped rather than of a filter this test
    /// built.
    @Test("Under the shipped defaults the first rows are improvements on the dashboard lifts")
    func defaultsHideBaselineAccessories() async throws {
        let fixture = try await programme()
        var stored = try await fixture.log.repositories.settings.settings()
        stored.dashboardExerciseIDs = [fixture.squat]
        try await fixture.log.repositories.settings.save(stored)
        let filter = try await shippedFilter(fixture)

        let feed = try await fixture.recomputer.recentRecords(limit: 5, filter: filter)

        #expect(!feed.isEmpty)
        #expect(!feed.contains { $0.exerciseID == fixture.kickback })
        #expect(feed.allSatisfy { $0.previous != nil })
        #expect(feed.allSatisfy { $0.delta != nil })
    }

    /// The scope narrows on identifiers, so a lifter whose dashboard names the accessory sees it —
    /// the same selection, obeyed by the tiles and by the feed (`FR-16.3.1`).
    ///
    /// The two other filters are relaxed on the row rather than in a hand-built filter, because
    /// under the shipped defaults a lift performed once passes neither: it is a baseline, and its
    /// scheme is one run short of being derived. What is under test here is the scope alone.
    @Test("A dashboard naming the accessory puts it back in the feed")
    func theScopeFollowsTheDashboard() async throws {
        let fixture = try await programme()
        var stored = try await fixture.log.repositories.settings.settings()
        stored.dashboardExerciseIDs = [fixture.kickback]
        stored.recentRecordsShowsBaselines = true
        stored.recentRecordsSchemes = .chosen([RecordScheme(reps: 10, sets: 1)])
        try await fixture.log.repositories.settings.save(stored)
        let filter = try await shippedFilter(fixture)

        let feed = try await fixture.recomputer.recentRecords(limit: 5, filter: filter)

        #expect(feed.map(\.exerciseID) == [fixture.kickback])
    }

    /// `FR-16.3.4`: the flag is what shows them, and nothing else does.
    @Test("The baseline flag is what puts a first-ever record on screen")
    func baselinesAreShownByTheFlag() async throws {
        let fixture = try await programme()

        let hidden = try await fixture.recomputer.recentRecords(
            limit: 5,
            filter: RecentRecordsFilter(
                exerciseIDs: [fixture.kickback], schemes: .derived, showsBaselines: false))
        let shown = try await fixture.recomputer.recentRecords(
            limit: 5,
            filter: RecentRecordsFilter(
                exerciseIDs: [fixture.kickback],
                schemes: .chosen([RecordScheme(reps: 10, sets: 1)]),
                showsBaselines: true))

        #expect(hidden.isEmpty)
        #expect(shown.count == 1)
    }

    /// `FR-16.3.2`'s threshold, counted in runs: two performances of a scheme is not enough and
    /// three is, and the boundary is the assertion rather than the direction.
    @Test("A scheme trained twice derives nothing; a third run derives it")
    func theDerivedThresholdIsThree() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for (week, grams) in [(6, 120_000), (4, 130_000)] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<3).map { _ in working(grams, 5) })
        }
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        #expect(try await recomputer.derivedSchemes(forExerciseID: squat).isEmpty)

        try await log.session(
            of: squat, on: weeksAgo(2), sets: (0..<3).map { _ in working(140_000, 5) })

        let derived = try await recomputer.derivedSchemes(forExerciseID: squat)
        #expect(derived == [RecordScheme(reps: 5, sets: 3)])
    }

    /// A run establishes sixty cells by dominance and is one performance of one scheme. Counting
    /// cells would put `1 × 1` over the threshold after three sessions of anything, and the filter
    /// would stop filtering.
    @Test("Dominance does not count: three runs derive their own cell and no other")
    func dominatedCellsAreNotCounted() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for week in [6, 4, 2] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<3).map { _ in working(140_000, 5) })
        }
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let derived = try await recomputer.derivedSchemes(forExerciseID: squat)

        #expect(derived == [RecordScheme(reps: 5, sets: 3)])
        #expect(!derived.contains(RecordScheme(reps: 1, sets: 1)))
    }

    /// A run past either bound clamps rather than being refused, so the cell it derives is the
    /// table's corner — the same clamp the records themselves are computed through.
    @Test("A run past the table's bounds derives the clamped cell")
    func aRunPastTheBoundsClamps() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for week in [6, 4, 2] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<8).map { _ in working(60_000, 12) })
        }
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        #expect(
            try await recomputer.derivedSchemes(forExerciseID: squat)
                == [RecordScheme(reps: 10, sets: 6)])
    }

    /// The derived set filters the feed as well as being computable: a scheme the lifter has
    /// performed once holds a record and does not appear.
    @Test("Derived schemes keep a habitual scheme and drop a one-off")
    func derivedSchemesFilterTheFeed() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for (week, grams) in [(8, 120_000), (6, 130_000), (4, 140_000)] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<3).map { _ in working(grams, 5) })
        }
        // A one-off heavy single, newer than every 5 × 3 above.
        try await log.session(of: squat, on: weeksAgo(1), sets: [working(200_000, 1)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        let filter = RecentRecordsFilter(
            exerciseIDs: nil, schemes: .derived, showsBaselines: true)

        let feed = try await recomputer.recentRecords(limit: 10, filter: filter)

        #expect(feed.allSatisfy { $0.scheme == RecordScheme(reps: 5, sets: 3) })
        #expect(!feed.contains { $0.weight == Weight(grams: 200_000) })
    }

    /// The limit counts what survives, not what was considered — a feed of two under a scope that
    /// excludes the three newest events still draws two.
    ///
    /// **Three separate accessories rather than three sessions of one**, because a record is the
    /// *current* holder of a cell: three improving sessions of one lift leave one event behind, not
    /// three, and the fixture would then not have the newer rows the limit has to look past.
    @Test("The limit is applied after the filter, not before it")
    func theLimitCountsSurvivors() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        try await log.session(of: squat, on: weeksAgo(9), sets: [working(140_000, 5)])
        try await log.session(of: bench, on: weeksAgo(8), sets: [working(100_000, 5)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            exercises: log.repositories.exercises,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        try await recomputer.recompute(forExerciseID: bench)
        // Three newer records the scope excludes, one per accessory so each stands as its own event.
        for (week, name) in [(3, "Cable Fly"), (2, "Lateral Raise"), (1, "Triceps Kickback")] {
            let accessory = try await log.exercise(named: name)
            try await log.session(of: accessory, on: weeksAgo(week), sets: [working(20_000, 10)])
            try await recomputer.recompute(forExerciseID: accessory)
        }

        let feed = try await recomputer.recentRecords(
            limit: 2,
            filter: RecentRecordsFilter(
                exerciseIDs: [squat, bench],
                schemes: .chosen([RecordScheme(reps: 5, sets: 1)]),
                showsBaselines: true))

        #expect(feed.count == 2)
        #expect(Set(feed.map(\.exerciseID)) == [squat, bench])
    }

    /// `FR-16.3.1`'s default scope reads `FR-1.9.1`'s selection, and where the lifter has made none
    /// it is the caller's resolver that answers — this is the seam that says so.
    @Test("An unconfigured dashboard resolves the scope through the caller's default")
    func anUnconfiguredDashboardUsesTheDefault() async throws {
        let fixture = try await programme()
        let stored = try await fixture.log.repositories.settings.settings()
        #expect(stored.dashboardExerciseIDs == nil)

        let scope = await RecentRecordsFilter.scope(of: stored) { [fixture.squat] }

        #expect(scope == [fixture.squat])
    }

    /// A chosen scope with nothing ticked is a choice, not an absence: it draws nothing rather than
    /// falling back to everything.
    @Test("A chosen scope naming no exercise draws nothing")
    func anEmptyChosenScopeDrawsNothing() async throws {
        let fixture = try await programme()
        var stored = try await fixture.log.repositories.settings.settings()
        stored.recentRecordsScope = .chosen
        try await fixture.log.repositories.settings.save(stored)

        let scope = await RecentRecordsFilter.scope(of: stored) { [fixture.squat] }
        let feed = try await fixture.recomputer.recentRecords(
            limit: 5,
            filter: RecentRecordsFilter(
                exerciseIDs: scope, schemes: .derived, showsBaselines: true))

        #expect(scope == [])
        #expect(feed.isEmpty)
    }

    /// The filter the app builds from a stored row, so a test asserting on "the defaults" asserts on
    /// what ships rather than on a filter it wrote itself.
    private func shippedFilter(_ fixture: Programme) async throws -> RecentRecordsFilter {
        let stored = try await fixture.log.repositories.settings.settings()
        let scope = await RecentRecordsFilter.scope(of: stored) { [] }
        return RecentRecordsFilter(
            exerciseIDs: scope,
            schemes: stored.recentRecordsSchemes,
            showsBaselines: stored.recentRecordsShowsBaselines)
    }
}
