#if os(iOS)

    import DerivedValues
    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Dashboard

    // TR-1.12 for FR-1.9.1, FR-1.9.2 and FR-1.9.4, on `RecentRecordsSnapshotTests`' terms: the
    // pieces are rendered rather than the screen, because the screen is three `.task`s over four
    // repositories and a reference through one is a reference over three spinners.
    //
    // THE REFERENCES PIN THEIR LOCALE AND THEIR TIME ZONE, for that file's reason — every tile
    // renders a load and the card renders a day.
    //
    // WHAT IS NOT PICTURED is the `NavigationStack` the picker link needs to be a control, and the
    // shell the primary action reads its `NavigationState` from. Both are UIKit-backed or
    // environment-fed; where they lead is the state tests' and the simulator run's.

    @MainActor
    @Suite("Dashboard snapshots")
    struct DashboardSnapshotTests {
        @Test func tiles() throws {
            // One picture with every tile variant in it: a rising estimate, a first estimate with
            // nothing to compare against, a manual override, and a refusal. They are only
            // comparable side by side, which is why this is one reference rather than four.
            //
            // THE FOURTH TILE IS FR-16.5.2's one-liner, beside three that have numbers — which is
            // what makes this reference the negative of `Dashboard-tiles-no-estimates` as well as
            // the picture of a refusal.
            //
            // NO FALLING TILE, and its absence is the point rather than an omission.
            // `EstimatedMax.delta` is strictly positive wherever it is not nil — see its own doc
            // comment — so a reference picturing a decline would be a committed image of a state
            // the app cannot produce, and the strongest kind of wrong: one a reader trusts.
            try assertSnapshots(named: "Dashboard-tiles") {
                EstimatedMaxTilesReading(
                    state: .ready(DashboardFixtures.tiles), unit: .kilograms, retry: {}
                )
                .environment(\.locale, DashboardFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func noTilesChosen() throws {
            // FR-1.13.1's empty state: the lifter removed every tile. Not the insufficient-data one
            // — nothing failed to compute, there is nothing to compute.
            try assertSnapshots(named: "Dashboard-tiles-none") {
                EstimatedMaxTilesReading(state: .noneTiled, unit: .kilograms, retry: {})
            }
        }

        @Test func noTileHasAnEstimate() throws {
            // FR-16.5.2's section-level half, and the state a fresh install's dashboard is in:
            // three tiles that would each say their own version of "nothing yet" say it once.
            //
            // THE TILES ARE STILL DRAWN, and the third is why (`FR-15.1.8`): it carries a training
            // max the lifter typed, which the section's own sentence cannot hold. Each names its
            // lift and nothing else, which is also what makes "one of these lifts" in that sentence
            // point at something.
            //
            // ITS NEGATIVE IS `Dashboard-tiles`, which holds three estimates and one refusal — so
            // the conditional that chooses between them is pictured true here and false there.
            try assertSnapshots(named: "Dashboard-tiles-no-estimates") {
                EstimatedMaxTilesReading(
                    state: .noEstimates(DashboardFixtures.untrainedTiles),
                    unit: .kilograms,
                    retry: {}
                )
                // The third tile renders a load, so this reference pins its locale like the rest —
                // it did not have to before the tiles were drawn under the message.
                .environment(\.locale, DashboardFixtures.locale)
            }
        }

        @Test func tilesUnreadable() throws {
            try assertSnapshots(named: "Dashboard-tiles-error") {
                EstimatedMaxTilesReading(state: .failed, unit: .kilograms, retry: {})
            }
        }

        @Test func lastWorkoutFinished() throws {
            try assertSnapshots(named: "Dashboard-last-workout") {
                LastWorkoutReading(
                    state: .finished(DashboardFixtures.finished),
                    hasFailedRepeat: false,
                    retry: {},
                    resume: {},
                    repeatWorkout: { _ in }
                )
                .environment(\.locale, DashboardFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func lastWorkoutInProgress() throws {
            // The other of FR-1.9.2's two actions, and the line that replaces the set count: a
            // running total presented as a finished one is the reading this avoids.
            try assertSnapshots(named: "Dashboard-last-workout-open") {
                LastWorkoutReading(
                    state: .inProgress(DashboardFixtures.open),
                    hasFailedRepeat: true,
                    retry: {},
                    resume: {},
                    repeatWorkout: { _ in }
                )
                .environment(\.locale, DashboardFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func nothingLogged() throws {
            try assertSnapshots(named: "Dashboard-last-workout-none") {
                LastWorkoutReading(
                    state: .nothingLogged,
                    hasFailedRepeat: false,
                    retry: {},
                    resume: {},
                    repeatWorkout: { _ in }
                )
            }
        }

        @Test func weekSummary() throws {
            // FR-1.9.5's two numbers side by side. At accessibility3 they stack — the reference
            // pair is what proves the switch, since a formatted tonnage beside a count is what
            // wraps first.
            try assertSnapshots(named: "Dashboard-week") {
                WeekSummaryReading(
                    state: .ready(WeekSummary(workoutCount: 4, tonnage: DashboardFixtures.volume)),
                    unit: .kilograms,
                    retry: {}
                )
                .environment(\.locale, DashboardFixtures.locale)
            }
        }

        @Test func weekSummaryQuiet() throws {
            // FR-1.13.3's whole point, pictured: this is what the card draws INSTEAD OF "0
            // workouts, 0 kg".
            try assertSnapshots(named: "Dashboard-week-quiet") {
                WeekSummaryReading(state: .quiet, unit: .kilograms, retry: {})
            }
        }

        @Test func weekSummaryUnweighed() throws {
            // A real workout count above a volume that cannot be computed — Tonnage's third clause
            // drawn as the two different things it is, rather than as one zero.
            try assertSnapshots(named: "Dashboard-week-unweighed") {
                WeekSummaryReading(
                    state: .unweighed(workouts: 3), unit: .kilograms, retry: {}
                )
                .environment(\.locale, DashboardFixtures.locale)
            }
        }

        @Test func weekSummaryUnreadable() throws {
            try assertSnapshots(named: "Dashboard-week-error") {
                WeekSummaryReading(state: .failed, unit: .kilograms, retry: {})
            }
        }

        @Test func firstLaunch() throws {
            // FR-1.13.2, and the one reference where what is NOT in the picture is the assertion:
            // no section cards, and one action rather than the separate "Start workout" button
            // above them.
            try assertSnapshots(named: "Dashboard-first-launch") {
                FirstLaunchReading(start: {})
            }
        }

        @Test func tilePicker() throws {
            // FR-16.5.3: the search field, the trained section with a date under each name, and the
            // remainder under its own heading. One picture, because the claim is the order of the
            // two sections relative to each other.
            try assertSnapshots(named: "Dashboard-tile-picker") {
                TiledExerciseSelectionReading(
                    state: .ready(DashboardFixtures.pickerSections),
                    searchText: .constant(""),
                    hasFailedWrite: false,
                    retry: {},
                    toggle: { _ in }
                )
                .environment(\.locale, DashboardFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func tilePickerSearchMatchedNothing() throws {
            // The negative of the reference above, and it pins two things a picture is the only
            // check for: the field keeps the query that caused the state — so the reader can see the
            // cause — and it is still on screen above the message, which is what makes replacing the
            // rows recoverable here (see `ExerciseChoiceList`'s own note).
            try assertSnapshots(named: "Dashboard-tile-picker-no-matches") {
                TiledExerciseSelectionReading(
                    state: .ready([]),
                    searchText: .constant("hack squat"),
                    hasFailedWrite: false,
                    retry: {},
                    toggle: { _ in }
                )
            }
        }
    }

    /// What these references render.
    enum DashboardFixtures {
        /// Pinned because a Mac's region is not its language — see this file's header.
        static let locale = Locale(identifier: "en_US")

        /// The day everything here is dated from, fixed so a reference committed today still
        /// matches next year.
        static let day = Date(timeIntervalSince1970: 1_700_000_000)

        /// Four tiles: up with a training max under it, first without one, up again, refused *with*
        /// one — every variant the pipeline can reach.
        ///
        /// **`FR-15.1.8`'s pair is the first tile, and the second is what makes it legible.** The
        /// squat carries both numbers, one under the other and each named by a word; the deadlift
        /// carries only the estimate, because most exercises have no training max and an absence
        /// drawn as a zero or a dash is the failure this arrangement is a picture of.
        ///
        /// **The row is the fourth tile's whole point: "the training max must not be invisible"
        /// applies to an exercise the app cannot estimate.** That is not a corner — it is the
        /// exercise a coach has just handed a number for and the lifter has not trained yet. The
        /// number sits beneath the insufficient-data view rather than inside it, so the explanation
        /// stays about the estimate.
        static let tiles: [EstimatedMaxTile] = [
            tile("Back Squat", kilos: 182.5, previousKilos: 175, trainingMaxKilos: 175),
            tile("Deadlift", kilos: 210, previousKilos: nil),
            tile("Overhead Press", kilos: 72.5, previousKilos: 70, trainingMaxKilos: 67.5),
            EstimatedMaxTile(
                exerciseID: id(5),
                name: "Barbell Row",
                estimate: EstimatedMax(
                    absence: .refused(.repsOutOfRange), formula: .epley, lookback: .default),
                trainingMax: Weight(grams: 100_000)),
        ]

        /// A week's load: 12,400 kg, enough digits that a grouping separator shows.
        static let volume = Weight(grams: 12_400_000)

        /// A finished workout, with what `FR-1.9.2` says about it.
        static let finished = LastWorkoutSummary(
            sessionID: id(6),
            date: day.addingTimeInterval(-2 * 86_400),
            isInProgress: false,
            exerciseNames: ["Back Squat", "Bench Press", "Barbell Row"],
            workingSetCount: 11)

        /// The same workout, still open.
        static let open = LastWorkoutSummary(
            sessionID: id(7),
            date: day,
            isInProgress: true,
            exerciseNames: ["Back Squat", "Bench Press"],
            workingSetCount: 4)

        /// The section with nothing to estimate from: three lifts, the last of them carrying the
        /// training max a coach handed over before any of it was trained (`FR-15.1.8`).
        static let untrainedTiles: [EstimatedMaxTile] = [
            untrained("Back Squat", absence: .noSetsLogged),
            untrained("Bench Press", absence: .noSetsLogged),
            untrained("Deadlift", absence: .refused(.warmup), trainingMaxKilos: 200),
        ]

        /// The picker's rows, two of them ticked.
        static let choices: [TiledExerciseChoice] = [
            TiledExerciseChoice(
                exerciseID: id(1),
                name: "Back Squat",
                isTiled: true,
                lastTrained: day.addingTimeInterval(-2 * 86_400)),
            TiledExerciseChoice(
                exerciseID: id(2),
                name: "Bench Press",
                isTiled: true,
                lastTrained: day.addingTimeInterval(-9 * 86_400)),
            TiledExerciseChoice(
                exerciseID: id(3), name: "Deadlift", isTiled: false, lastTrained: nil),
        ]

        /// Those rows split as `FR-16.5.3` draws them: two trained, one not.
        static let pickerSections = ExerciseChoiceSections.sections(choices, matching: "")

        /// One computed tile, with or without something to compare against.
        private static func tile(
            _ name: String, kilos: Double, previousKilos: Double?, trainingMaxKilos: Double? = nil
        ) -> EstimatedMaxTile {
            EstimatedMaxTile(
                exerciseID: id(name.count),
                name: name,
                estimate: EstimatedMax(
                    record: record(kilos, daysAgo: 3),
                    previous: previousKilos.map { record($0, daysAgo: 20) },
                    formula: .epley,
                    lookback: .default),
                trainingMax: trainingMaxKilos.map { Weight(grams: Int($0 * 1000)) })
        }

        /// One tile the app cannot put a number on.
        private static func untrained(
            _ name: String, absence: EstimateAbsence, trainingMaxKilos: Double? = nil
        ) -> EstimatedMaxTile {
            EstimatedMaxTile(
                exerciseID: id(name.count),
                name: name,
                estimate: EstimatedMax(absence: absence, formula: .epley, lookback: .default),
                trainingMax: trainingMaxKilos.map { Weight(grams: Int($0 * 1000)) })
        }

        /// One dated record.
        private static func record(_ kilos: Double, daysAgo: Int) -> DatedRecord {
            DatedRecord(
                weight: Weight(grams: Int(kilos * 1000)),
                sourceSetID: id(daysAgo),
                achievedAt: day.addingTimeInterval(-Double(daysAgo) * 86_400))
        }

        /// A stable identifier, so a reference does not change by run.
        private static func id(_ index: Int) -> UUID {
            UUID(uuidString: "5A5B0000-0000-4000-8000-0000000000\(String(format: "%02d", index))")
                ?? UUID()
        }
    }

#endif
