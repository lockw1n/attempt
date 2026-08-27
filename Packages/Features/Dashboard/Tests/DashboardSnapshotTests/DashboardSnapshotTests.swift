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

        @Test func tilePicker() throws {
            try assertSnapshots(named: "Dashboard-tile-picker") {
                TiledExerciseSelectionReading(
                    state: .ready(DashboardFixtures.choices),
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

        /// Four tiles: up, first, manual, refused — every variant the pipeline can reach.
        static let tiles: [EstimatedMaxTile] = [
            tile("Back Squat", kilos: 182.5, previousKilos: 175),
            tile("Deadlift", kilos: 210, previousKilos: nil),
            EstimatedMaxTile(
                exerciseID: id(4),
                name: "Overhead Press",
                estimate: EstimatedMax(
                    manual: Weight(grams: 70_000), formula: .epley, lookback: .default)),
            EstimatedMaxTile(
                exerciseID: id(5),
                name: "Barbell Row",
                estimate: EstimatedMax(
                    absence: .refused(.repsOutOfRange), formula: .epley, lookback: .default)),
        ]

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

        /// The picker's rows, two of them ticked.
        static let choices: [TiledExerciseChoice] = [
            TiledExerciseChoice(exerciseID: id(1), name: "Back Squat", isTiled: true),
            TiledExerciseChoice(exerciseID: id(2), name: "Bench Press", isTiled: true),
            TiledExerciseChoice(exerciseID: id(3), name: "Deadlift", isTiled: false),
        ]

        /// One computed tile, with or without something to compare against.
        private static func tile(
            _ name: String, kilos: Double, previousKilos: Double?
        ) -> EstimatedMaxTile {
            EstimatedMaxTile(
                exerciseID: id(name.count),
                name: name,
                estimate: EstimatedMax(
                    record: record(kilos, daysAgo: 3),
                    previous: previousKilos.map { record($0, daysAgo: 20) },
                    formula: .epley,
                    lookback: .default))
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
