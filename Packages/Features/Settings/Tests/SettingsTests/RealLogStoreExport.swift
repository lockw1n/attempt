import Foundation
import Persistence
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

/// Writes a restored store to a directory the caller names, so a real log can be put in front of
/// the app on a simulator or a device.
///
/// **It produces an artefact rather than asserting a claim, and that is what it is for.**
/// `NFR-1.5` and `NFR-1.6` are measured against ~15,000 sets *in the running app*, and the app's
/// only door for a log that size is `FR-1.11.4`'s restore — which is a screen, driven by a finger.
/// A store file can be copied into a container instead, and this is the only place in the
/// repository that can write one: `Settings` owns ``StoreRestore`` and the archive reader, and
/// `Persistence` is already a test-only edge here for `DOD-1.3`'s reason.
///
///     ATTEMPT_REAL_BACKUP=/path/backup.json ATTEMPT_STORE_OUT=/path/dir \
///         swift test --package-path Packages/Features/Settings --filter RealLogStoreExport
///
/// **The file is named `default.store` because that is the name the app opens.**
/// `StoreLocation.applicationDefault` takes SwiftData's own default, which is
/// `Application Support/default.store`; a store written under any other name has to be renamed
/// before it is copied, and a rename that missed the `-wal` sidecar would hand the app a store
/// missing its most recent writes.
///
/// **Off unless both variables are set**, for ``RealLogBackup``'s reason and one more: this writes
/// to a path the caller chose, which is not something a test run should do by default.
enum RealLogStoreDestination {
    /// The environment variable naming the directory to write into.
    nonisolated static let variable = "ATTEMPT_STORE_OUT"

    /// The directory the caller asked for, or `nil`.
    nonisolated static var directory: URL? {
        guard let named = ProcessInfo.processInfo.environment[variable], !named.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: named)
    }

    /// Whether both halves were supplied — a backup to read and somewhere to put it.
    nonisolated static var isRequested: Bool { directory != nil && RealLogBackup.isAvailable }

    /// What to do about it, printed when the suite is skipped.
    nonisolated static let howToRequestIt: Comment = """
        Set \(variable) to a directory and \(RealLogBackup.variable) to a full-backup .json to \
        write a store the app can open.
        """

}

/// The export itself.
///
/// **A second type, because a suite cannot gate itself.** `@Suite(.enabled(if:))` naming a static
/// on the very struct it is attached to is a circular macro reference and does not compile;
/// ``RealLogRecomputeTests`` does not hit it only because it gates on ``RealLogBackup``, which is
/// somewhere else. Splitting the condition out is the fix, not a preference.
@Suite(
    "Real-log store export",
    .enabled(if: RealLogStoreDestination.isRequested, RealLogStoreDestination.howToRequestIt)
)
struct RealLogStoreExportTests {
    @Test("A real log, restored into a store the app can open")
    func writesAStoreTheAppCanOpen() async throws {
        let directory = try #require(RealLogStoreDestination.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "default.store")

        let data = try Data(contentsOf: try #require(RealLogBackup.fileURL))
        let stack = try PersistenceStack(location: .file(storeURL))
        let recomputer = PersonalRecordRecomputer(
            workouts: stack.workouts,
            cache: stack.personalRecords)
        let archive = try StoreRestore.archive(from: data)
        try await RealLogBackup.restore(into: stack, records: recomputer).restore(archive)

        // The anchor `RealLogRecomputeTests` uses, for the same reason: a restore that wrote
        // nothing produces a file the app opens happily and measures nothing.
        let catalogue = try await stack.exercises.exercises(includingDeleted: false)
        let counts = try await RealLogBackup.liveSetCounts(in: stack, over: catalogue)
        let restored = counts.values.reduce(0, +)
        #expect(restored > 0)
        print(
            """
            store export: \(restored) sets over \(catalogue.count) exercises
            store export: \(storeURL.path)
            """)
    }
}
