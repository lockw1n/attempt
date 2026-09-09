#if os(iOS)

    import DerivedValues
    import DesignSystem
    import Foundation
    import PowerliftingCore
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import ExerciseLibrary

    // TR-1.12 for `FR-16.2.4`'s record table. A suite of its own rather than more of
    // `ExerciseDetailSnapshotTests`, which is at SwiftLint's file ceiling: the two grow for different
    // reasons — a section being added to the detail screen, and a screen of its own being added.
    //
    // WHAT THE ACCESSIBILITY3 REFERENCE SHOWS, AND WHAT IT DOES NOT. The grid is the one thing on
    // this screen that cannot simply wrap: a load and a date per cell at the largest type size are
    // wider than a phone whichever way the table is turned — which is the measurement that settled
    // the task's own question, table or transposed, in favour of neither. Both orientations overflow;
    // what fixes it is the horizontal `ScrollView` `SchemeTableGrid` puts the grid in, and
    // `.fixedSize` on the grid so the columns keep their width instead of breaking `132.5 kg` across
    // two lines.
    //
    // The reference is what holds that: at `accessibility3` the grid is visibly wider than the
    // frame. The harness renders into a fixed 320-point frame, which CENTRES an oversized child — so
    // the picture is the middle of the table with both edges cut, not the leading edge the scroller
    // shows at rest. That framing is the harness's and not the screen's; where the scroller actually
    // starts is the simulator run's.
    //
    // SO THE GRID IS PICTURED AND ITS SCROLLER IS NOT, and that is not a shortcut: `ScrollView` is
    // UIKit-backed, and a first attempt at this reference took the picture through one and recorded
    // an EMPTY CARD — which the harness compares dimensions-first and would have matched forever.
    // `SchemeGrid` exists as a view of its own for exactly this.
    //
    // WHAT IS NOT PICTURED either is the `NavigationStack` a cell needs to be a control, on the
    // detail suite's terms. That a cell links to its session is `ExerciseRecordsSectionTests`' and
    // the simulator run's.

    @MainActor
    @Suite("Exercise record table snapshots")
    struct ExerciseRecordsTableSnapshotTests {
        @Test func schemeTable() throws {
            // A lifter's real shape: singles at the top, a five-by-five at the bottom, and holes
            // where a scheme has never been performed. **All three of `FR-17.2.2`'s states are in
            // this one picture**, which is the whole reason it is worth having — a record with a
            // beaten load, a first performance saying *First*, and a *Not yet* where nothing was
            // ever done. A fixture with only one of them would settle nothing about the other two.
            try assertSnapshots(named: "ExerciseRecords-table") {
                Card {
                    SchemeGrid(
                        table: ExerciseSchemeTable(TableFixtures.records),
                        unit: .kilograms,
                        sessions: [:]
                    )
                }
                .environment(\.locale, TableFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func schemeTableLinked() throws {
            // `FR-17.2.5`'s other half: a filled cell's tap through to its session is discoverable,
            // which is a chevron beside the day. It is drawn **only** where the source session
            // resolved, so the picture above — which resolves none — cannot show it, and this is the
            // same grid with the sessions supplied. Two cells are deliberately left unresolved, so
            // the reference settles that the chevron follows the link rather than the cell.
            try assertSnapshots(named: "ExerciseRecords-table-linked") {
                Card {
                    SchemeGrid(
                        table: ExerciseSchemeTable(TableFixtures.records),
                        unit: .kilograms,
                        sessions: TableFixtures.sessions
                    )
                }
                .environment(\.locale, TableFixtures.locale)
                .environment(\.timeZone, .gmt)
            }
        }

        @Test func schemeTableNothingYet() throws {
            // `FR-1.13.3`'s insufficient-data case. The sentence is the rule rather than an
            // instruction, because this screen cannot tell "nothing logged" from "nothing that
            // counts" — see `ExerciseRecordsTableState`.
            try assertSnapshots(named: "ExerciseRecords-table-none") {
                InsufficientDataView(message: Text(ExerciseLibraryStrings.recordsNoWorkingSets))
            }
        }
    }

    /// What the table reference renders: one exercise's cells, with real gaps in them.
    enum TableFixtures {
        /// Pinned because a Mac's region is not its language — see `ExerciseDetailSnapshotTests`.
        static let locale = Locale(identifier: "en_US")

        /// Four rep counts across three set counts, and not every pair filled.
        ///
        /// **The `3 × 6` is the row that makes the picture worth having**: it is a lighter load than
        /// the `3 × 1` two columns to its left, which is what a record table looks like when it is
        /// honest — more sets means less weight.
        ///
        /// **`beating` is what puts a cell in one state rather than the other** (`FR-17.2.2`), and
        /// the mix here is deliberate: four records, three first performances, and the five gaps the
        /// rows and columns leave. Every one of the three is drawn somewhere in the picture.
        static let records: [DatedSchemeRecord] = [
            cell(reps: 1, sets: 1, kilos: 160, daysAgo: 40, beating: 157.5),
            cell(reps: 3, sets: 1, kilos: 145, daysAgo: 12, beating: 140),
            cell(reps: 3, sets: 3, kilos: 130, daysAgo: 5),
            cell(reps: 3, sets: 6, kilos: 115, daysAgo: 2),
            cell(reps: 5, sets: 1, kilos: 132.5, daysAgo: 19, beating: 130),
            cell(reps: 5, sets: 3, kilos: 120, daysAgo: 5, beating: 117.5),
            cell(reps: 8, sets: 1, kilos: 110, daysAgo: 33),
        ]

        /// Where five of the seven cells' source sets were performed, keyed on the set.
        ///
        /// **Five of seven, not all of them**: a cell whose session did not resolve is not a link,
        /// and picturing every cell resolved would settle nothing about which cells get a chevron.
        static let sessions: [UUID: UUID] = Dictionary(
            uniqueKeysWithValues: records.dropLast(2).enumerated().map { index, record in
                (
                    record.record.sourceSetID,
                    UUID(uuidString: "1A5B2C36-4D7E-4F81-9062-0000000000\(String(format: "%02d", index))")
                        ?? UUID()
                )
            })

        /// One cell, spelled out once so a field nothing in the picture turns on is not repeated.
        private static func cell(
            reps: Int, sets: Int, kilos: Double, daysAgo: Int, beating: Double? = nil
        ) -> DatedSchemeRecord {
            DatedSchemeRecord(
                scheme: RecordScheme(reps: reps, sets: sets),
                record: DatedRecord(
                    weight: Weight(grams: Int(kilos * 1000)),
                    sourceSetID: UUID(
                        uuidString:
                            "0F5A1E24-9B7D-4C31-8E62-00000000\(String(format: "%02d%02d", reps, sets))"
                    ) ?? UUID(),
                    achievedAt: Date(timeIntervalSince1970: 1_700_000_000)
                        .addingTimeInterval(-Double(daysAgo) * 86_400)
                ),
                previous: beating.map { Weight(grams: Int($0 * 1000)) })
        }
    }

#endif
