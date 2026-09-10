import Foundation
import Persistence
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

/// `DOD-16.4`, `DOD-16.2` and `DOD-17.4`'s restored-log half: the record pipeline measured — and,
/// since `FR-17.2.1`, *checked* — over the author's own training log, in a real SwiftData store,
/// restored through the app's own path.
///
/// **Off unless a backup is named, because the subject cannot be committed.** It is one lifter's
/// training history — `G-5.2`'s data stays on their device, and a fixture cannot stand in for it
/// without becoming the synthetic measurement `RecomputeScaleTests` already takes. Run it with:
///
///     ATTEMPT_REAL_BACKUP=/path/to/backup.json swift test --package-path Packages/Features/Settings
///
/// **Why this target rather than `DerivedValuesTests`, where the synthetic figure lives.**
/// `DerivedValues` declares no `Persistence` dependency — see its manifest — so the suite that owns
/// `NFR-16.1`'s algorithm cannot reach a real store at all. `Settings` is the one existing target
/// that depends on both, and it owns ``StoreRestore``, which is the door a real log comes in
/// through.
///
/// **A real *file* store, not `.inMemory`.** The figure is about SwiftData's fetch and
/// materialization under a live log; an in-memory container would measure something a lifter never
/// runs.
@Suite(
    "Real-log recompute",
    .enabled(if: RealLogBackup.isAvailable, RealLogBackup.howToSupplyIt)
)
struct RealLogRecomputeTests {
    /// Whether this is a hosted runner rather than a machine whose speed is known.
    ///
    /// It never is today — CI has no backup to name, so the suite is skipped there — but the
    /// distinction is `RecomputeScaleTests`' and is kept for the same reason: a number taken on
    /// hardware the requirement is not about must not be read as the requirement being met.
    private static let isHostedRunner =
        ProcessInfo.processInfo.environment["CI"] == "true"
        || ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"

    /// What this run asserts against — `NFR-16.1`'s ceiling, or a sanity ceiling standing in for it.
    private static var budget: Duration {
        isHostedRunner ? .seconds(5) : .milliseconds(500)
    }

    /// The floor a restore has to clear before any timing here means anything.
    ///
    /// **A restore that wrote nothing recomputes nothing in ~0 ms and passes every assertion below.**
    /// `DOD-16.4` names a 3,065-set log; this is well under it so that the author trimming or
    /// growing their history does not fail a test about speed, and well over anything an empty or
    /// half-written store could reach.
    private static let minimumSets = 1_000

    /// `FR-16.3`'s feed depth, and `DOD-16.2`'s own claim: five rows, so "none of them is a
    /// baseline" is a statement about five and not one satisfied by a short feed.
    private static let feedLimit = 5

    @Test("DOD-16.4 and DOD-16.2 over the author's real log, in one restored store")
    func theRealLogRecomputesInsideTheBudget() async throws {
        let data = try Data(contentsOf: try #require(RealLogBackup.fileURL))
        let store = try RealLogBackup.temporaryStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let stack = store.stack

        let recomputer = PersonalRecordRecomputer(
            workouts: stack.workouts,
            cache: stack.personalRecords)
        let archive = try StoreRestore.archive(from: data)
        let clock = ContinuousClock()

        // The restore is reported, never asserted on — it is a whole-catalogue sweep, which is not
        // the shape `NFR-16.1` budgets, and printing it beside the figure that is keeps the
        // difference visible. **T-1.93 took the fan-out out of it**: it announced once per restored
        // session and each announcement walked every exercise that session touched, so an exercise
        // trained fifty times was walked fifty times over its whole history. It is now one walk per
        // distinct exercise, after every session has landed. The figure below is what that costs;
        // `RestoreFanOutTests` is what holds the shape, since a clock cannot.
        let restoreElapsed = try await clock.measure {
            try await RealLogBackup.restore(into: stack, records: recomputer).restore(archive)
        }

        // The anchor, before anything is timed: a store the restore left empty would meet every
        // ceiling in this file.
        let catalogue = try await stack.exercises.exercises(includingDeleted: false)
        let setCounts = try await RealLogBackup.liveSetCounts(in: stack, over: catalogue)
        let restoredSets = setCounts.values.reduce(0, +)
        #expect(restoredSets >= Self.minimumSets)
        // Every restored row comes back live (`RecordMapping.swift` rule 1), so the file's whole set
        // section is what a live read has to find — a lost row is a defect in the restore. **The
        // read that says so is the one through the entries**, not the one through the catalogue.
        //
        // T-16.16 asserted the catalogue count against the file's section and that claim is unsound:
        // `sets(forExerciseID:)` applies `FR-16.4.2` and drops a **pending** set — one not completed,
        // in a session still open — because a set nobody has attempted is not history. So the two
        // counts differ by exactly the pending sets, and equating the first with the archive fails on
        // any log holding an open session. Measured on the author's 2026-09-04 backup: 3,065 sets in
        // the file, 3,065 stored, 3,023 in history, and the 42 between them are the pending sets of
        // the two sessions they left open. The restore lost nothing.
        //
        // Both are still counted, because the pair is what says *which* thing is wrong: a shortfall
        // through the entries is a row the restore never wrote; a shortfall through the catalogue
        // alone is `FR-16.4.2` doing its job, and the assertion below names the difference rather
        // than tolerating it.
        try await expectTheRestoreLostNothing(stack, archive, inHistory: restoredSets)

        // `NFR-16.1`'s own shape: one walk per exercise, which is what a lifter's device does when
        // a cache is cold. `recompute` is unconditional, so this is the full walk rather than the
        // cached read.
        // Per call as well as in total, because the two answer different readings of the same
        // requirement: `NFR-16.1` budgets *a recomputation*, and the app's own hot path is one
        // exercise after one logged set, where this walk is all 132 at once. The costed loop is the
        // brief's, and the maximum beside it is what says which reading the figure fails.
        var perExercise: [Duration] = []
        perExercise.reserveCapacity(catalogue.count)
        let recomputeElapsed = try await clock.measure {
            for exercise in catalogue {
                perExercise.append(
                    try await clock.measure {
                        try await recomputer.recompute(forExerciseID: exercise.id)
                    })
            }
        }

        // The asserted figure, and the size of what it walked. `perExercise` is appended in
        // `catalogue` order, so the index carries back to the exercise and to its set count.
        let slowestIndex = perExercise.indices.max { perExercise[$0] < perExercise[$1] }
        let slowest = slowestIndex.map { perExercise[$0] } ?? .zero
        let slowestSets = slowestIndex.flatMap { setCounts[catalogue[$0].id] } ?? 0

        // `OUT-17.4`'s markers are dropped once, here, and every claim below is about records.
        // One is written per exercise holding none — 132 of them on a catalogue this size — so a
        // count that kept them would report a cache four times the size of the records in it.
        let cached = try await stack.personalRecords.personalRecords(includingDeleted: false)
            .filter { !$0.isConfirmedZero }
        // What the write side costs now that a run writes one cell (`FR-17.2.1`). A row at one set
        // is `FR-1.6.1`'s column; the rest are the schemes this lifter actually trains in groups,
        // where under the withdrawn dominance rule they were the rectangle beneath every one.
        let singleSet = cached.count { $0.setCount == 1 }
        let multiplier = String(
            format: "%.2f", Double(cached.count) / Double(max(singleSet, 1)))
        let ceiling = Self.isHostedRunner ? "hosted-runner sanity" : "NFR-16.1"
        print(
            """
            DOD-16.4 real log:  \(restoredSets) sets, \(archive.sessions.count) sessions, \
            \(catalogue.count) exercises
            DOD-16.4 recompute: max \(slowest) for ONE exercise over \(slowestSets) of this \
            log's \(restoredSets) sets (ceiling \(Self.budget), \(ceiling))
            DOD-16.4 catalogue: \(recomputeElapsed) over \(catalogue.count) exercises, \
            mean \(recomputeElapsed / max(catalogue.count, 1)) — reported, not asserted
            DOD-16.4 write side: \(cached.count) cached rows, \(singleSet) of them at one set — \
            a x\(multiplier) multiplier
            DOD-16.4 restore:   \(restoreElapsed) (reported, not asserted — the fan-out above)
            """)
        // ASSERTED ON THE SLOWEST SINGLE RECOMPUTE, NOT ON THE SUM, and the difference is the
        // requirement's own subject rather than a relaxation. `NFR-16.1` budgets *a* scheme-record
        // recomputation whose input is 15,000 sets, which is what `RecomputeScaleTests` measures:
        // one `recompute(forExerciseID:)` call. The loop above makes 132 of them, and summing 132
        // calls against a one-call budget compares a catalogue sweep to a figure never written for
        // one. What the app does on the hot path is a single exercise after a single logged set,
        // which is this number.
        //
        // NEITHER READING IS CLEAN, AND THIS IS A CHOICE RATHER THAN A DERIVATION. `NFR-16.1` fixes
        // both a unit (one call) and an input (15,000 sets), and over a real log the two come
        // apart: the log is spread across the whole catalogue, so NO single call ever sees all of
        // it. Asserting one call compares an input of `slowestSets` against a budget written for
        // 15,000; asserting the sum compares 132 calls against a budget written for one. The unit
        // is the harder of the two to argue away — it is what `RecomputeScaleTests` measures and
        // what the app's hot path actually runs — so it is the one asserted, and the printed line
        // states the asserted call's input size so that the choice is auditable rather than
        // implied by a bare duration.
        //
        // THE SUM IS REPORTED AND NOT ASSERTED, because it is a real finding at ~0.53 s over 3,065
        // sets where the fake takes 0.155 s over 15,000 — the store is roughly 25x the cost per
        // set, and nothing recomputes the whole catalogue on a lifter's device except the restore,
        // whose own figure is worse and is already filed. It belongs with
        // `repMaxes(forExerciseID:)`'s stored-derivation question on `T-1.83`, not against a
        // ceiling this requirement does not set.
        #expect(slowest < Self.budget)
        // The walk is worthless if it cached nothing, and a log this size has records.
        #expect(!cached.isEmpty)

        try await expectEveryCachedCellWasPerformed(stack, catalogue, cached)
        try await expectTheShippedDefaultsFillTheFeed(stack, recomputer, catalogue, clock)
    }

    /// The restore's own claim, counted by both joins.
    ///
    /// - Parameters:
    ///   - stack: The restored store.
    ///   - archive: The decoded backup.
    ///   - inHistory: How many sets the catalogue read found.
    /// - Throws: Whatever the repository throws.
    private func expectTheRestoreLostNothing(
        _ stack: PersistenceStack,
        _ archive: TrainingLogArchive,
        inHistory restoredSets: Int
    ) async throws {
        let byEntry = try await RealLogBackup.liveSetCount(
            in: stack, overEntryIDs: archive.entries.map(\.id))
        let pending = RealLogBackup.pendingSetCount(in: archive)
        print(
            """
            DOD-16.4 sets:      \(archive.sets.count) in the file, \(byEntry) stored, \
            \(restoredSets) in history — \(archive.sets.count - restoredSets) pending \
            (FR-16.4.2), of \(pending) the file says are
            """)
        // The restore's own claim: nothing in the file failed to land.
        #expect(byEntry == archive.sets.count)
        // And history is the file minus exactly the pending sets, rather than minus something else.
        #expect(restoredSets == archive.sets.count - pending)
    }

    /// `DOD-17.4`: over the author's restored log, no cached cell names a scheme they never did.
    ///
    /// **The witness is built here rather than read from `SchemeRuns`**, and that is the whole value
    /// of the check: comparing the cache to the grouping that wrote it would agree by construction.
    /// The rule is re-stated from `FR-17.2.1` and `NFR-16.2` — a run is consecutive completed
    /// working sets at one load and one rep count, a dropped set ends the run it interrupted, and
    /// the corner clamps to the table's bounds — so a disagreement is the engine and the requirement
    /// disagreeing, not two spellings of one function.
    ///
    /// **Subset, not equality.** A cell the lifter performed and then beat at a heavier load is one
    /// row, not two, and a scheme performed only at a load already standing writes nothing at all;
    /// so the cache is properly contained in what was performed, and asserting equality would fail
    /// on every tie the log holds.
    ///
    /// **`OUT-17.4`'s markers are already out of `cached` when this is called**, and they have to
    /// be: the marker occupies the `0 × 0` cell precisely because nothing can be performed there, so
    /// it is *by construction* a row at a scheme never performed — the exact thing this catches.
    /// Excluded at the caller's read rather than tolerated in the predicate here, so what is
    /// compared is still every row claiming a record.
    ///
    /// - Parameters:
    ///   - stack: The restored store.
    ///   - catalogue: Its live exercises.
    ///   - cached: Every cached record row.
    /// - Throws: Whatever the repository throws.
    private func expectEveryCachedCellWasPerformed(
        _ stack: PersistenceStack,
        _ catalogue: [Exercise],
        _ cached: [PersonalRecordCache]
    ) async throws {
        var performed: [UUID: Set<RecordScheme>] = [:]
        for exercise in catalogue {
            let stored = try await stack.workouts.sets(
                forExerciseID: exercise.id, includingDeleted: false)
            performed[exercise.id] = Self.schemesPerformed(in: stored)
        }

        let invented = cached.filter { row in
            !(performed[row.exerciseID] ?? []).contains(
                RecordScheme(reps: row.repCount, sets: row.setCount))
        }
        let named = Dictionary(catalogue.map { ($0.id, $0.name) }) { first, _ in first }
        print(
            """
            DOD-17.4 cells: \(cached.count) cached, \(performed.values.reduce(0) { $0 + $1.count }) \
            distinct schemes performed, \(invented.count) cached at a scheme never performed
            """)
        for row in invented.prefix(5) {
            print(
                "  invented: \(named[row.exerciseID] ?? "?") at \(row.repCount)×\(row.setCount)")
        }
        #expect(invented.isEmpty)
        // Anchored: an empty cache, or one whose exercises did not resolve, would satisfy the line
        // above without the check having compared anything.
        #expect(
            cached.contains { row in
                (performed[row.exerciseID] ?? []).contains(
                    RecordScheme(reps: row.repCount, sets: row.setCount))
            })
    }

    /// Every cell `stored` was performed at, by `FR-17.2.1`'s rule stated independently.
    ///
    /// **The repository's own order is the chronological one and this must not re-sort it.**
    /// `SetEntry.order` is a set's position *within its entry*, so sorting one exercise's whole
    /// history by it interleaves every session's first set, then every session's second — which
    /// fabricates runs out of sets months apart. Measured: sorting here reported 104 of 119 cached
    /// cells as never performed, all of them false.
    ///
    /// **A run outside either bound is not a cell and is not recorded as one.** `cell(for:)`
    /// refuses it (`FR-17.2.1`), and the witness has to refuse it here rather than clamp: a witness
    /// that clamped would call a run of twelve a `10 × n` performance, which is the one claim
    /// `FR-17.2.1` can be violated at — so the check would agree with the engine by construction
    /// exactly where it needs to disagree.
    ///
    /// - Parameter stored: One exercise's live sets, oldest first, as the repository returned them.
    /// - Returns: The cells performed at, within the table's bounds.
    private static func schemesPerformed(in stored: [SetEntry]) -> Set<RecordScheme> {
        var schemes: Set<RecordScheme> = []
        var current: [SetEntry] = []

        // One line, because a multi-clause `while` puts its brace where `swift format` wants it and
        // SwiftLint's `opening_brace` does not — the two disagree and only the condition can yield.
        let joins: (SetEntry, SetEntry) -> Bool = { $0.weight == $1.weight && $0.reps == $1.reps }

        // And for the same reason, the bounds are one closure rather than a two-clause `if`.
        let isACell: (Int, Int) -> Bool = {
            PersonalRecords.repRange.contains($0) && SchemeRecordCalculator.setRange.contains($1)
        }

        func close() {
            var index = current.startIndex
            while index < current.endIndex {
                var end = index
                while end + 1 < current.endIndex, joins(current[index], current[end + 1]) {
                    end += 1
                }
                let reps = current[index].reps
                let sets = end - index + 1
                if isACell(reps, sets) { schemes.insert(RecordScheme(reps: reps, sets: sets)) }
                index = end + 1
            }
            current = []
        }

        for set in stored {
            // A warmup, a failure, or a row this build cannot analyse **ends** the run it stood in
            // rather than being dropped out of it — filter-then-group would fabricate adjacency.
            guard !set.isWarmup, set.isCompleted, (try? set.setRecord()) != nil else {
                close()
                continue
            }
            // And a run never spans two entries: "consecutive" (`NFR-16.2`) is within one session's
            // work on one exercise, so the last set of Monday's bench and the first of Wednesday's
            // are not two of a run of two. Measured: without this the witness merged four sets into
            // a six and reported the real `5 × 4` cell as invented.
            if let last = current.last, last.entryID != set.entryID { close() }
            current.append(set)
        }
        close()
        return schemes
    }

    /// `DOD-16.2`'s restored-log half, in the store the measurement above already restored.
    ///
    /// **A second restore is the expensive part, not the assertion**, so this is a method rather
    /// than a test of its own — 25 seconds of fan-out to re-state four lines.
    ///
    /// - Parameters:
    ///   - stack: The restored store.
    ///   - recomputer: The actor whose cache that restore filled.
    ///   - catalogue: The restored exercises.
    ///   - clock: The clock the caller is already timing with.
    /// - Throws: Whatever a repository throws.
    private func expectTheShippedDefaultsFillTheFeed(
        _ stack: PersistenceStack,
        _ recomputer: PersonalRecordRecomputer,
        _ catalogue: [Exercise],
        _ clock: ContinuousClock
    ) async throws {
        // Read off the settings row the file restored, not restated here: the criterion is a claim
        // about what ships, so a filter this test wrote itself would prove nothing about it.
        let stored = try await stack.settings.settings()
        let mostTrained = try await recomputer.mostTrainedExerciseIDs()
        let scope = await RecentRecordsFilter.scope(of: stored) {
            RealLogBackup.defaultDashboardExerciseIDs(in: catalogue, mostTrained: mostTrained)
        }
        try expectTheDefaultTilesAreAllTrained(catalogue, mostTrained)
        let filter = RecentRecordsFilter(
            exerciseIDs: scope,
            schemes: stored.recentRecordsSchemes,
            showsBaselines: stored.recentRecordsShowsBaselines)
        var feed: [RecentRecord] = []
        let feedElapsed = try await clock.measure {
            feed = try await recomputer.recentRecords(limit: Self.feedLimit, filter: filter)
        }

        // `FR-16.3.2`'s derived schemes cost one full set-history walk per exercise reached,
        // memoised per call and bounded by the scope — so this figure is the shipped default's,
        // and `FR-16.3.4`'s offer (which writes `.everyExercise`) removes that bound. No
        // requirement targets it; a bad number here is a finding for `T-1.83`, not a failure.
        print(
            """
            DOD-16.2 feed: \(feed.count) rows in \(feedElapsed) \
            (scope \(stored.recentRecordsScope), schemes \(stored.recentRecordsSchemes), \
            baselines \(stored.recentRecordsShowsBaselines))
            """)
        #expect(feed.count == Self.feedLimit)
        #expect(feed.allSatisfy { $0.previous != nil })
        #expect(feed.allSatisfy { !$0.isBaseline })
    }

    /// `FR-16.5.1` over a real log: every default tile names a lift the lifter actually trains.
    ///
    /// **The claim is "no tile is empty", not "the tiles are these three names."** The author's log
    /// holds a bench press and no barbell squat or deadlift, so the seeded three would draw one
    /// number and two apologies — which is review finding 04 and the reason this requirement
    /// exists. Asserting the two replacements by name would be asserting the shape of one person's
    /// training, which changes; asserting that each resolved tile has history is the requirement.
    ///
    /// - Parameters:
    ///   - catalogue: The restored exercises.
    ///   - mostTrained: The ranking the defaults fall back to.
    /// - Throws: Nothing; `throws` for the assertion helpers' sake.
    private func expectTheDefaultTilesAreAllTrained(
        _ catalogue: [Exercise], _ mostTrained: [UUID]
    ) throws {
        let tiled = RealLogBackup.defaultDashboardExerciseIDs(
            in: catalogue, mostTrained: mostTrained)
        let named = Dictionary(catalogue.map { ($0.id, $0.name) }) { first, _ in first }
        print("FR-16.5.1 default tiles: \(tiled.compactMap { named[$0] })")

        #expect(tiled.count == 3)
        #expect(Set(tiled).count == 3)
        // The whole of finding 04: a log this size cannot leave a default tile with no history.
        #expect(tiled.allSatisfy(Set(mostTrained).contains))
    }
}
