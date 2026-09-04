#if os(iOS)

    import DerivedValues
    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Dashboard

    // TR-1.12 for FR-1.6.5's feed, in the same four configurations as every other suite and on the
    // same terms — see `ExerciseListSnapshotTests` for why the pieces are rendered rather than the
    // screen, and why the copy is the real copy.
    //
    // THE REFERENCES PIN THEIR LOCALE AND THEIR TIME ZONE. Every row here renders a load and a date,
    // and the harness pins neither: an unpinned reference records whatever REGION the recording Mac
    // is set to, which is the trap `ExerciseDetailSnapshotTests` and `SessionListSnapshotTests` both
    // met before it was written down.
    //
    // WHAT IS NOT PICTURED is the `NavigationStack` a row needs to be a control at all — it is
    // UIKit-backed, so a reference taken through one is the renderer's placeholder. Where the row
    // navigates to is `RecentRecordsScreenStateTests`' and the simulator run's.

    @MainActor
    @Suite("Recent records snapshots")
    struct RecentRecordsSnapshotTests {
        @Test func feed() throws {
            // One picture with every row variant in it: a rep max that beat a standing one, a rep
            // max set for the first time — which says **First** where the delta would be
            // (`FR-16.3.4`) — and a run that set no rep max at all, whose exercise the catalogue
            // would not name either. Four references over three rows rather than three suites: what
            // each variant does to the row is a label, a reading and a delta, and they are only
            // comparable side by side.
            try assertSnapshots(named: "RecentRecords-feed") {
                GroupedSection(Text(DashboardStrings.recentRecordsTitle)) {
                    ForEach(FeedFixtures.entries, id: \.self) { record in
                        RecentRecordRow(
                            record: record,
                            exerciseName: FeedFixtures.names[record.exerciseID],
                            unit: .kilograms
                        )
                    }
                }
                .environment(\.locale, FeedFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func nothingYet() throws {
            // FR-1.13.3's insufficient-data case, which is what a store with no records draws — not
            // an empty state, because nothing was filtered away.
            try assertSnapshots(named: "RecentRecords-none") {
                InsufficientDataView(message: Text(DashboardStrings.recentRecordsNone))
            }
        }

        @Test func unreadable() throws {
            try assertSnapshots(named: "RecentRecords-error") {
                ErrorStateView(message: Text(DashboardStrings.recentRecordsError), retry: {})
            }
        }
    }

    /// What these references render: three entries across two exercises, one of them unnamed.
    enum FeedFixtures {
        /// Pinned because a Mac's region is not its language — see this file's header.
        static let locale = Locale(identifier: "en_US")

        /// The day every entry is dated from, fixed so a reference committed today still matches
        /// next year.
        static let day = Date(timeIntervalSince1970: 1_700_000_000)

        static let squat = UUID(uuidString: "1E4E2A62-0000-4000-8000-000000000001") ?? UUID()
        static let bench = UUID(uuidString: "1E4E2A62-0000-4000-8000-000000000002") ?? UUID()
        static let retired = UUID(uuidString: "1E4E2A62-0000-4000-8000-000000000003") ?? UUID()

        /// Only two of the three exercises resolve: a record outlives its exercise, and a row with
        /// no name still has to render.
        static let names: [UUID: String] = [squat: "Back Squat", bench: "Bench Press"]

        /// `FR-16.3.3`'s row at each of its shapes: a rep max that improved on one, a rep max set
        /// for the first time, and a run that set no rep max at all.
        ///
        /// **The first row's label is `3RM` and not `1–3-rep max`** — the retired form (see
        /// ``Dashboard/DashboardStrings/recentRecordsRepMax(_:)``), and the reference is where that
        /// is visible rather than argued.
        static let entries: [RecentRecord] = [
            entry(exerciseID: squat, reps: 1...3, kilos: 142.5, daysAgo: 2, beating: 140),
            entry(exerciseID: bench, reps: 5...5, kilos: 102.5, daysAgo: 9),
            run(exerciseID: retired, reps: 5, sets: 5, kilos: 100, daysAgo: 30, beating: 95),
        ]

        /// One rep-max entry, spelled out once so a field nothing in the picture turns on is not
        /// repeated.
        private static func entry(
            exerciseID: UUID,
            reps: ClosedRange<Int>,
            kilos: Double,
            daysAgo: Int,
            beating: Double? = nil
        ) -> RecentRecord {
            RecentRecord(
                exerciseID: exerciseID,
                scheme: RecordScheme(reps: reps.upperBound, sets: 1),
                repMaxReps: reps,
                weight: Weight(grams: Int(kilos * 1000)),
                sourceSetID: sourceSetID(daysAgo),
                achievedAt: day.addingTimeInterval(-Double(daysAgo) * 86_400),
                previous: beating.map { Weight(grams: Int($0 * 1000)) }
            )
        }

        /// One entry for a run that set no rep max — `FR-16.2.1`'s second dimension on the feed.
        private static func run(
            exerciseID: UUID,
            reps: Int,
            sets: Int,
            kilos: Double,
            daysAgo: Int,
            beating: Double? = nil
        ) -> RecentRecord {
            RecentRecord(
                exerciseID: exerciseID,
                scheme: RecordScheme(reps: reps, sets: sets),
                repMaxReps: nil,
                weight: Weight(grams: Int(kilos * 1000)),
                sourceSetID: sourceSetID(daysAgo),
                achievedAt: day.addingTimeInterval(-Double(daysAgo) * 86_400),
                previous: beating.map { Weight(grams: Int($0 * 1000)) }
            )
        }

        /// A fixed identifier per entry, so a reference does not move between runs.
        private static func sourceSetID(_ daysAgo: Int) -> UUID {
            UUID(
                uuidString: "0F5A1E24-9B7D-4C31-8E62-0000000000\(String(format: "%02d", daysAgo))"
            ) ?? UUID()
        }
    }

#endif
