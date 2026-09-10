import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues

/// `FR-16.3.4`'s offer, from the side that decides whether to make it: what counts as a narrowing,
/// and what taking the offer writes.
///
/// **Its own file rather than `RecentRecordsStateTests`'**, which took that one past the file-length
/// ceiling — and the split follows a line that was already there: everything here is about
/// ``RecentRecordsState/isNarrowed`` and ``RecentRecordsState/showEverything()``, where that file is
/// about the read.
@Suite("Recent records — what counts as narrowed")
@MainActor
struct RecentRecordsNarrowingTests {
    /// A log, the recomputer over it, and the exercises in it.
    private struct Trained {
        let log: TrainingLog
        let recomputer: PersonalRecordRecomputer
        let exercises: [UUID]
    }

    /// Two exercises trained on different days, both recomputed, both improving — so neither
    /// standing record is a baseline and `FR-16.3.4`'s own default is not what empties the feed.
    private func trainedLog() async throws -> Trained {
        let log = TrainingLog()
        let squat = try await log.exercise(named: "Back Squat")
        let bench = try await log.exercise(named: "Bench Press")
        for (week, grams) in [(6, 130_000), (4, 140_000)] {
            try await log.session(of: squat, on: weeksAgo(week), sets: [working(grams, 3)])
        }
        for (week, grams) in [(3, 90_000), (1, 100_000)] {
            try await log.session(of: bench, on: weeksAgo(week), sets: [working(grams, 5)])
        }
        let recomputer = PersonalRecordRecomputer(
            workouts: log.repositories.workouts,
            cache: log.repositories.personalRecords,
            now: { fixtureNow })
        try await recomputer.recompute(forExerciseID: squat)
        try await recomputer.recompute(forExerciseID: bench)
        return Trained(log: log, recomputer: recomputer, exercises: [squat, bench])
    }

    /// `FR-16.3.4`'s offer is only honest where something was actually narrowed, and there are three
    /// ways to narrow the feed — so this is four readings of one flag rather than one.
    ///
    /// **Every scheme is the un-configured value and does not count**, which since `FR-17.3.1` is
    /// arithmetic: it drops nothing. A chosen list does count, on `T-16.07`'s rule — it drops cells
    /// from a choice the lifter made.
    @Test(
        "isNarrowed counts each narrowing and not the un-configured value",
        arguments: [
            (RecentRecordsScope.everyExercise, true, RecentRecordsSchemes.everyScheme, false),
            (RecentRecordsScope.dashboardLifts, true, RecentRecordsSchemes.everyScheme, true),
            (RecentRecordsScope.everyExercise, false, RecentRecordsSchemes.everyScheme, true),
            (
                RecentRecordsScope.everyExercise, true,
                RecentRecordsSchemes.chosen([RecordScheme(reps: 5, sets: 5)]), true
            ),
        ])
    func isNarrowedCountsEachNarrowing(
        scope: RecentRecordsScope, baselines: Bool, schemes: RecentRecordsSchemes, narrowed: Bool
    ) async throws {
        let trained = try await trainedLog()
        var stored = try await trained.log.repositories.settings.settings()
        stored.recentRecordsScope = scope
        stored.recentRecordsShowsBaselines = baselines
        stored.recentRecordsSchemes = schemes
        try await trained.log.repositories.settings.save(stored)
        let state = RecentRecordsState(
            recomputer: trained.recomputer,
            catalogue: trained.log.repositories.exercises,
            settings: trained.log.repositories.settings,
            limit: 10,
            defaultDashboardExerciseIDs: everyExercise(_:_:))

        await state.load()

        #expect(state.isNarrowed == narrowed)
    }

    /// `FR-16.3.4`'s offer taken, from the side that writes it: all three narrowings are relaxed on
    /// the stored row, and the schemes are written as the un-configured value rather than as a
    /// chosen list holding every cell.
    ///
    /// **The re-read is asserted through the feed rather than through the row**, because a write
    /// that landed and a screen that never looked again are the same row and different screens.
    @Test("Show everything writes every scheme and re-reads under it")
    func showEverythingWritesEveryScheme() async throws {
        let trained = try await trainedLog()
        var stored = try await trained.log.repositories.settings.settings()
        stored.recentRecordsScope = .chosen
        stored.recentRecordsExerciseIDs = []
        stored.recentRecordsShowsBaselines = false
        stored.recentRecordsSchemes = .chosen([])
        try await trained.log.repositories.settings.save(stored)
        let state = RecentRecordsState(
            recomputer: trained.recomputer,
            catalogue: trained.log.repositories.exercises,
            settings: trained.log.repositories.settings,
            limit: 10,
            defaultDashboardExerciseIDs: everyExercise(_:_:))
        await state.load()
        #expect(state.records.isEmpty)
        #expect(state.isNarrowed)

        await state.showEverything()

        let widened = try await trained.log.repositories.settings.settings()
        #expect(widened.recentRecordsScope == .everyExercise)
        #expect(widened.recentRecordsShowsBaselines)
        #expect(widened.recentRecordsSchemes == .everyScheme)
        #expect(!state.isNarrowed)
        #expect(state.records.count == 2)
    }
}
