#if os(iOS)

    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.11.1/FR-1.11.2. The reading rather than the screen, on this module's other
    // suites' terms: the screen is a `.task` that walks the whole store, and a reference through it
    // is a reference of a spinner.
    //
    // NO `NavigationStack` AROUND THESE — this repo's standing finding, written out in the Health
    // suite beside this one. `ImageRenderer` draws none of a UIKit-backed container's content.
    //
    // THE FILES ARE FICTIONS, and they have to be: a reference that wrote two real files would
    // re-record itself on every run through the export's date-stamped name. What the ready state
    // draws of a file is its share command, never its path.

    @MainActor
    @Suite("Data export snapshots")
    struct DataExportSnapshotTests {
        /// Two files that do not exist, with counts that read as a real first month of training.
        static let files = TrainingLogExportFiles(
            csv: URL(filePath: "/tmp/Attempt-training-log-2026-08-28.csv"),
            json: URL(filePath: "/tmp/Attempt-training-log-2026-08-28.json"),
            sessionCount: 12,
            setCount: 148)

        @Test func ready() throws {
            // Both formats, each with the sentence saying what it is for, and the two qualifications
            // under them: where a shared file can go, and that deleted rows are not in it.
            try assertSnapshots(named: "Data-export-ready") {
                DataExportReading(state: .ready(Self.files), retry: {})
            }
        }

        @Test func readyWithOneOfEach() throws {
            // The plural forms, which are the reason the counts are in the `.stringsdict`: a first
            // export is very often one workout and one set, and "1 workouts" is the reading that
            // makes a lifter distrust the file.
            let single = TrainingLogExportFiles(
                csv: Self.files.csv, json: Self.files.json, sessionCount: 1, setCount: 1)
            try assertSnapshots(named: "Data-export-ready-singular") {
                DataExportReading(state: .ready(single), retry: {})
            }
        }

        @Test func preparing() throws {
            // FR-1.13.1's loading state, and a real wait rather than a decorative one: it walks
            // every session in the store before either file exists.
            try assertSnapshots(named: "Data-export-preparing") {
                DataExportReading(state: .preparing, retry: {})
            }
        }

        @Test func empty() throws {
            // FR-1.13.1's empty state. The catalogue is seeded at first launch, so this is what a
            // store with a hundred exercises and no training in it looks like.
            try assertSnapshots(named: "Data-export-empty") {
                DataExportReading(state: .empty, retry: {})
            }
        }

        @Test func failed() throws {
            // FR-1.13.1's error state, with the retry — the read may well succeed on the next tap,
            // which is what ErrorStateView's own doc comment makes the condition for offering one.
            try assertSnapshots(named: "Data-export-failed") {
                DataExportReading(state: .failed, retry: {})
            }
        }
    }

#endif
