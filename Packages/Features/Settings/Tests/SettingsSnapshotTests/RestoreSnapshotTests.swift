#if os(iOS)

    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Settings

    // TR-1.12 for FR-1.11.4. The reading rather than the screen, on this module's other suites'
    // terms: the screen owns a `fileImporter`, and a reference through it is a reference of a
    // system sheet.
    //
    // NO `NavigationStack` AROUND THESE — this repo's standing finding, written out in the Health
    // suite. `ImageRenderer` draws none of a UIKit-backed container's content.
    //
    // SEVEN STATES DRAWN AS SIX. `reading` and `restoring` are one component with two sentences, so
    // the layout claim is made once; which sentence each phase resolves is `SettingsStringsTests`'
    // to answer. The three refusals are likewise one layout — `RestoreStateTests` is where the
    // three headline/message pairs are held apart.

    @MainActor
    @Suite("Restore snapshots")
    struct RestoreSnapshotTests {
        /// A file that does not exist, with counts that read as a real first year of training.
        static let summary = BackupSummary(
            takenAt: Date(timeIntervalSinceReferenceDate: 773_452_800),
            workoutCount: 96,
            recordCount: 2_418,
            deletedCount: 7)

        /// The calendar every state here is drawn in.
        ///
        /// **Without it these references are the recorder's time zone, not the screen's.** The
        /// instant above is midnight UTC, so a machine west of Greenwich draws the previous day —
        /// and `AppFormat.fullDate` names the weekday, so the two disagree in words rather than in
        /// a digit. Three of the states below draw that date, and they were the three that went red
        /// on CI while passing on the machine that recorded them.
        static var gmt: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            return calendar
        }

        /// One state, drawn in a zone that does not depend on where this is running.
        ///
        /// - Parameters:
        ///   - name: The reference's base name.
        ///   - state: The state to draw.
        /// - Throws: Whatever the harness throws.
        static func assertRestore(named name: String, _ state: RestoreScreenState) throws {
            try assertSnapshots(named: name) {
                RestoreReading(
                    state: state, chooseFile: {}, confirm: {}, chooseAnother: {}
                )
                .environment(\.calendar, gmt)
            }
        }

        @Test func waiting() throws {
            // FR-1.13.1's empty state, carrying the one command that changes it. The emptiness is
            // the screen's own — no file has been chosen — rather than the store's.
            try Self.assertRestore(named: "Restore-waiting", .waiting)
        }

        @Test func confirming() throws {
            // The destructive question: what the file holds, what writing it does, what it does not
            // do, and the sentence saying deleted records come back. Two commands, and the
            // destructive one raises a dialog rather than running.
            try Self.assertRestore(named: "Restore-confirming", .confirming(Self.summary))
        }

        @Test func confirmingWithNothingDeleted() throws {
            // The deleted count is dropped from the phrase rather than read as "0 deleted records
            // come back" — the backup screen's rule, and here it takes away a sentence's subject.
            let untouched = BackupSummary(
                takenAt: Self.summary.takenAt,
                workoutCount: 4,
                recordCount: 137,
                deletedCount: 0)
            try Self.assertRestore(
                named: "Restore-confirming-nothing-deleted", .confirming(untouched))
        }

        @Test func restoring() throws {
            // FR-1.13.1's loading state, and a real wait: it writes every row in the file.
            try Self.assertRestore(named: "Restore-restoring", .restoring)
        }

        @Test func restored() throws {
            // Not one of FR-1.13.1's five, and not meant to be: the screen has just done the thing
            // it exists for. The counts are the file's, which is what they were before the
            // confirmation too.
            try Self.assertRestore(named: "Restore-restored", .restored(Self.summary))
        }

        @Test func refused() throws {
            // FR-1.13.1's error state, and the retry is the picker: nothing this screen could do
            // again would make the same bytes acceptable.
            try Self.assertRestore(named: "Restore-refused", .refused(.notABackup))
        }

        @Test func failed() throws {
            // The other error state, and a different sentence: rows are already written, and the
            // retry runs the same file again — which is safe because every write is keyed on the
            // record's own identifier.
            try Self.assertRestore(named: "Restore-failed", .failed)
        }
    }

#endif
