#if os(iOS)

    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.11.3. The reading rather than the screen, on this module's other suites'
    // terms: the screen is a `.task` that walks the whole store, and a reference through it is a
    // reference of a spinner.
    //
    // NO `NavigationStack` AROUND THESE — this repo's standing finding, written out in the Health
    // suite beside this one. `ImageRenderer` draws none of a UIKit-backed container's content.
    //
    // THREE STATES AND NOT FOUR: there is no empty one. A backup is a question about the store, and
    // the store always holds the preferences row — the argument is on `BackupState.Phase`.

    @MainActor
    @Suite("Backup snapshots")
    struct BackupSnapshotTests {
        /// A file that does not exist, with counts that read as a real first month of training.
        static let file = BackupFile(
            url: URL(filePath: "/tmp/Attempt-backup-2026-08-28.json"),
            workoutCount: 12,
            recordCount: 431,
            deletedCount: 7)

        @Test func ready() throws {
            // The file, what is in it, and the two qualifications under it — including the one that
            // is the export's sentence turned round: deleted rows ARE in this file.
            try assertSnapshots(named: "Backup-ready") {
                BackupReading(state: .ready(Self.file), retry: {})
            }
        }

        @Test func readyWithNothingDeleted() throws {
            // The deleted count is dropped from the phrase rather than read as "0 deleted records",
            // so the summary is two counts here and three above.
            let untouched = BackupFile(
                url: Self.file.url, workoutCount: 1, recordCount: 118, deletedCount: 0)
            try assertSnapshots(named: "Backup-ready-nothing-deleted") {
                BackupReading(state: .ready(untouched), retry: {})
            }
        }

        @Test func preparing() throws {
            // FR-1.13.1's loading state, and a real wait: it walks every table in the store before
            // the file exists.
            try assertSnapshots(named: "Backup-preparing") {
                BackupReading(state: .preparing, retry: {})
            }
        }

        @Test func failed() throws {
            // FR-1.13.1's error state, with the retry — the read may well succeed on the next tap.
            try assertSnapshots(named: "Backup-failed") {
                BackupReading(state: .failed, retry: {})
            }
        }
    }

#endif
