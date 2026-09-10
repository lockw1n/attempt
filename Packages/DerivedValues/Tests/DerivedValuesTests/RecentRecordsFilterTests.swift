import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.3`'s configuration, applied: what the feed reports on once the settings row narrows it.
///
/// **`FR-17.3.1` withdrew the "logged at least three times" threshold**, so what used to be three
/// tests of a derived scheme set is one test that a scheme performed twice reaches the feed, plus
/// the assertion that the read never touches a set history at all (`NFR-17.2`).
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
        /// The five improving lifts, newest record first — what a dashboard scope names.
        let dashboardLifts: [UUID]
    }

    /// **Five improving lifts and not one**, because `DOD-16.2` asserts on the *first five rows* and
    /// a feed holding one row satisfies "no baseline among the first five" by having nothing to
    /// look at. Each is trained on its own weeks so the five stand in a known order.
    private func programme() async throws -> Programme {
        let log = TrainingLog()
        let names = ["Back Squat", "Bench Press", "Deadlift", "Overhead Press", "Barbell Row"]
        var lifts: [UUID] = []
        for (index, name) in names.enumerated() {
            let lift = try await log.exercise(named: name)
            lifts.append(lift)
            // Three 5 × 3 runs, each heavier than the last: the third beats the second at 5 × 3, so
            // the standing record is an improvement rather than a baseline.
            for (offset, grams) in [(0, 120_000), (2, 130_000), (4, 140_000)] {
                try await log.session(
                    of: lift,
                    on: weeksAgo(20 - index * 3 - offset),
                    sets: (0..<3).map { _ in working(grams + index * 5_000, 5) })
            }
        }
        let kickback = try await log.exercise(named: "Triceps Kickback")
        // One light single, once, and never before: a baseline at a scheme trained once. Ten reps
        // rather than the twelve this fixture used to carry — twelve is outside `PersonalRecords`'
        // rep range, so since `FR-17.2.1` it sets no record at all and the accessory this suite is
        // about would never reach the feed to be scoped in or out of it.
        try await log.session(of: kickback, on: weeksAgo(1), sets: [working(10_000, 10)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        for lift in lifts + [kickback] { try await recomputer.recompute(forExerciseID: lift) }
        return Programme(
            log: log,
            recomputer: recomputer,
            squat: lifts[0],
            kickback: kickback,
            dashboardLifts: lifts)
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
        stored.dashboardExerciseIDs = fixture.dashboardLifts
        try await fixture.log.repositories.settings.save(stored)
        let filter = try await shippedFilter(fixture)

        let feed = try await fixture.recomputer.recentRecords(limit: 5, filter: filter)

        // Five rows, so "no baseline among the first five" is a statement about five of them
        // rather than one satisfied by a short feed.
        #expect(feed.count == 5)
        #expect(!feed.contains { $0.exerciseID == fixture.kickback })
        #expect(feed.allSatisfy { $0.previous != nil })
        #expect(feed.allSatisfy { $0.delta != nil })
    }

    /// `FR-16.3.1`: the chosen scope reads **its own** list, not the dashboard's.
    ///
    /// **The two columns name different lifts here**, on `mappingFeedExerciseID`'s rule: a fixture
    /// sharing one value between them passes for a resolution that read the wrong column, and
    /// reading the wrong column is the one way `.chosen` could stop being a second list at all.
    @Test("The chosen scope reads its own list, not the dashboard's")
    func theChosenScopeReadsItsOwnList() async throws {
        let fixture = try await programme()
        var stored = try await fixture.log.repositories.settings.settings()
        stored.recentRecordsScope = .chosen
        stored.recentRecordsExerciseIDs = [fixture.kickback]
        stored.dashboardExerciseIDs = [fixture.squat]
        try await fixture.log.repositories.settings.save(stored)

        let scope = await RecentRecordsFilter.scope(of: stored) { [fixture.squat] }
        let feed = try await fixture.recomputer.recentRecords(
            limit: 5,
            filter: RecentRecordsFilter(
                exerciseIDs: scope, schemes: .everyScheme, showsBaselines: true))

        #expect(scope == [fixture.kickback])
        #expect(feed.map(\.exerciseID) == [fixture.kickback])
    }

    /// The scope narrows on identifiers, so a lifter whose dashboard names the accessory sees it —
    /// the same selection, obeyed by the tiles and by the feed (`FR-16.3.1`).
    ///
    /// The baseline flag is relaxed on the row rather than in a hand-built filter, because under the
    /// shipped defaults a lift performed once is still hidden by it (`FR-16.3.4`). The scheme rule
    /// is left alone: since `FR-17.3.1` its shipped value narrows nothing, which is the point.
    @Test("A dashboard naming the accessory puts it back in the feed")
    func theScopeFollowsTheDashboard() async throws {
        let fixture = try await programme()
        var stored = try await fixture.log.repositories.settings.settings()
        stored.dashboardExerciseIDs = [fixture.kickback]
        stored.recentRecordsShowsBaselines = true
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
                exerciseIDs: [fixture.kickback], schemes: .everyScheme, showsBaselines: false))
        let shown = try await fixture.recomputer.recentRecords(
            limit: 5,
            filter: RecentRecordsFilter(
                exerciseIDs: [fixture.kickback], schemes: .everyScheme, showsBaselines: true))

        #expect(hidden.isEmpty)
        #expect(shown.count == 1)
    }

    /// `FR-17.3.1`, the whole of it: **a scheme performed twice reaches the feed.**
    ///
    /// The old threshold was three *runs* of a cell, and this fixture is deliberately one short of
    /// it — two sessions of `5 × 5`, the second heavier. Under `FR-16.3.2` the improvement the
    /// workout badges was filtered out of the feed, which is review finding 02.
    ///
    /// **The heavy single anchors it.** A test that only asserted the `5 × 5` appears would pass for
    /// a filter that admitted everything *and* for one that still admitted nothing but was reading
    /// an empty cache — so the fixture also holds a scheme performed exactly once, which the same
    /// widened rule has to admit for the same reason.
    @Test("A scheme performed twice reaches the feed")
    func everySchemeAdmitsASecondPerformance() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for (week, grams) in [(4, 80_000), (2, 90_000)] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<5).map { _ in working(grams, 5) })
        }
        try await log.session(of: squat, on: weeksAgo(1), sets: [working(200_000, 1)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)

        let feed = try await recomputer.recentRecords(
            limit: 10,
            filter: RecentRecordsFilter(
                exerciseIDs: nil, schemes: .everyScheme, showsBaselines: true))

        // The 5 × 5 is the improvement — it beat 80 kg — and it is what `FR-17.3.1` is about.
        let fiveByFive = feed.first { $0.scheme == RecordScheme(reps: 5, sets: 5) }
        #expect(fiveByFive?.weight == Weight(grams: 90_000))
        #expect(fiveByFive?.previous == Weight(grams: 80_000))
        #expect(feed.contains { $0.scheme == RecordScheme(reps: 1, sets: 1) })
    }

    /// The other half of `FR-17.3.2`: the chosen list is still a narrowing, and it is the only one
    /// of the three that touches schemes now.
    ///
    /// Same fixture as above, so the two tests differ in the filter and in nothing else — which is
    /// what makes this an assertion about the filter rather than about two logs.
    @Test("A chosen scheme list still narrows the feed")
    func aChosenListStillNarrows() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        for (week, grams) in [(4, 80_000), (2, 90_000)] {
            try await log.session(
                of: squat, on: weeksAgo(week), sets: (0..<5).map { _ in working(grams, 5) })
        }
        try await log.session(of: squat, on: weeksAgo(1), sets: [working(200_000, 1)])
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)

        let feed = try await recomputer.recentRecords(
            limit: 10,
            filter: RecentRecordsFilter(
                exerciseIDs: nil,
                schemes: .chosen([RecordScheme(reps: 5, sets: 5)]),
                showsBaselines: true))

        #expect(feed.map(\.scheme) == [RecordScheme(reps: 5, sets: 5)])
    }

    /// `NFR-17.2`: **the feed reads the cache and never a set history**, whatever the filter says.
    ///
    /// The walk this asserts is gone is `FR-16.3.2`'s derived schemes, which ran once per distinct
    /// exercise among the events examined — under `.everyExercise` that was the whole catalogue, on
    /// the tab the app launches into.
    ///
    /// **Anchored on a non-empty feed.** A counting fake reporting zero walks over a feed that came
    /// back empty would say nothing at all: the read could have been short-circuited by the limit,
    /// or by a cache the fixture never wrote.
    @Test("The feed walks no exercise's sets, at any scope")
    func theFeedReadsOnlyTheCache() async throws {
        let log = TrainingLog()
        for (name, week) in [("Back Squat", 4), ("Bench Press", 3), ("Deadlift", 2)] {
            let lift = try await log.exercise(named: name)
            try await log.session(of: lift, on: weeksAgo(week), sets: [working(100_000, 5)])
            try await log.session(of: lift, on: weeksAgo(week - 1), sets: [working(110_000, 5)])
            let seeding = PersonalRecordRecomputer(
                workouts: log.repositories.workouts,
                cache: log.repositories.personalRecords,
                now: { fixtureNow })
            try await seeding.recompute(forExerciseID: lift)
        }
        let counting = CountingWorkouts(wrapped: log.repositories.workouts)
        let reader = PersonalRecordRecomputer(
            workouts: counting,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })

        let feed = try await reader.recentRecords(
            limit: 10,
            filter: RecentRecordsFilter(
                exerciseIDs: nil, schemes: .everyScheme, showsBaselines: true))

        #expect(feed.count == 3)
        #expect(await counting.exerciseWalks == 0)
    }

    /// `DOD-17.2`'s feed half: a lift improved today is on the feed today, under the row that
    /// ships rather than under a filter this test wrote.
    ///
    /// **`90 × 5 × 5` after `80 × 5 × 5`**, which is the same run `FR-17.2.1`'s badge draws — so the
    /// badge and the feed are being asserted about one event. The lift is named on the dashboard,
    /// because `FR-16.3.1`'s shipped scope is the dashboard's lifts.
    @Test("A record set today appears on the feed today, under the shipped settings")
    func todaysRecordIsOnTheFeedToday() async throws {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        try await log.session(
            of: squat, on: weeksAgo(1), sets: (0..<5).map { _ in working(80_000, 5) })
        try await log.session(
            of: squat, on: fixtureNow, sets: (0..<5).map { _ in working(90_000, 5) })
        var stored = try await log.repositories.settings.settings()
        stored.dashboardExerciseIDs = [squat]
        try await log.repositories.settings.save(stored)
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)

        let filter = RecentRecordsFilter(
            exerciseIDs: await RecentRecordsFilter.scope(of: stored) { [] },
            schemes: stored.recentRecordsSchemes,
            showsBaselines: stored.recentRecordsShowsBaselines)
        let feed = try await recomputer.recentRecords(
            limit: RecentRecordsState.cardLimit, filter: filter)

        #expect(feed.count == 1)
        #expect(feed.first?.scheme == RecordScheme(reps: 5, sets: 5))
        #expect(feed.first?.weight == Weight(grams: 90_000))
        #expect(feed.first?.achievedAt == fixtureNow)
    }

    /// The limit counts what survives, not what was considered.
    ///
    /// **The rows the fixture excludes are excluded *after* grouping, which is the only way this
    /// can fail.** A first draft narrowed them out by exercise, and that filter runs over the
    /// cached rows *before* they are grouped — so the excluded events never reached the limit at
    /// all and the assertion held whether the limit was applied to candidates or to survivors. The
    /// baseline flag is the discriminator here because it is read off the grouped event.
    ///
    /// **Three separate accessories rather than three sessions of one**, because a record is the
    /// *current* holder of a cell: three improving sessions of one lift leave one event behind, not
    /// three, and the fixture would then not have the newer rows the limit has to look past.
    @Test("The limit is applied after the filter, not before it")
    func theLimitCountsSurvivors() async throws {
        let log = TrainingLog()
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        // Two improving lifts: each standing record beat something, so neither is a baseline.
        for (name, week, light, heavy) in [
            ("Back Squat", 9, 140_000, 150_000), ("Bench Press", 7, 100_000, 110_000),
        ] {
            let lift = try await log.exercise(named: name)
            try await log.session(of: lift, on: weeksAgo(week), sets: [working(light, 5)])
            try await log.session(of: lift, on: weeksAgo(week - 1), sets: [working(heavy, 5)])
            try await recomputer.recompute(forExerciseID: lift)
        }
        // Three newer events IN scope that the baseline flag drops, one per accessory so each
        // stands as its own event. Same scheme as the two above, so only the flag separates them.
        for (week, name) in [(3, "Cable Fly"), (2, "Lateral Raise"), (1, "Triceps Kickback")] {
            let accessory = try await log.exercise(named: name)
            try await log.session(of: accessory, on: weeksAgo(week), sets: [working(20_000, 5)])
            try await recomputer.recompute(forExerciseID: accessory)
        }

        let feed = try await recomputer.recentRecords(
            limit: 2,
            filter: RecentRecordsFilter(
                exerciseIDs: nil,
                schemes: .chosen([RecordScheme(reps: 5, sets: 1)]),
                showsBaselines: false))

        // A limit applied to candidates would take the three newest, drop all three as baselines
        // and draw nothing.
        #expect(feed.count == 2)
        #expect(feed.allSatisfy { !$0.isBaseline })
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
                exerciseIDs: scope, schemes: .everyScheme, showsBaselines: true))

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
