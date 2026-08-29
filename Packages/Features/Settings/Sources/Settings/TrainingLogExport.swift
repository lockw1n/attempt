import Foundation
import PowerliftingCore
import RepositoryInterface

/// Reads the whole training log out of the store and writes both export files (`FR-1.11.1`).
///
/// **It reads through the repository protocols one at a time**, like every other screen here
/// (`TR-0.1.2`) — there is no bulk read and there does not need to be: the store is local and
/// synchronous (`G-2.2`), so the cost of walking it is the cost of the file.
struct TrainingLogExport {
    /// The catalogue.
    let exercises: any ExerciseRepository

    /// Sessions, entries and sets.
    let workouts: any WorkoutRepository

    /// The bodyweight log.
    let bodyweight: any BodyweightRepository

    /// Every date a repository read can be asked for: this export is the whole log, not a window.
    private static let allTime = Date.distantPast...Date.distantFuture

    /// Gathers the log into one archive.
    ///
    /// **Live rows only.** A soft-deleted set is one the lifter removed, and an export is what they
    /// have — see ``TrainingLogArchive`` for the whole of that argument.
    ///
    /// - Parameter exportedAt: When the file is being written.
    /// - Returns: The archive.
    /// - Throws: Whatever the repositories throw. One failed read fails the export, because a file
    ///   missing the rows a read could not answer is worse than no file.
    func archive(exportedAt: Date = .now) async throws -> TrainingLogArchive {
        let sessions = try await workouts.sessions(in: Self.allTime, includingDeleted: false)
        var entries: [ExerciseEntry] = []
        var sets: [SetEntry] = []
        for session in sessions {
            let sessionEntries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            entries.append(contentsOf: sessionEntries)
            for entry in sessionEntries {
                sets.append(contentsOf: try await workouts.sets(forEntryID: entry.id, includingDeleted: false))
            }
        }
        return TrainingLogArchive(
            exportedAt: exportedAt,
            exercises: try await exercises.exercises(includingDeleted: false),
            sessions: sessions,
            entries: entries,
            sets: sets,
            bodyweight: try await bodyweight.entries(in: Self.allTime, includingDeleted: false))
    }
}

/// The two files one export action produces, and what the screen says about them (`FR-1.11.2`).
struct TrainingLogExportFiles: Equatable, Sendable {
    /// The spreadsheet file, one row per set.
    let csv: URL

    /// The lossless file.
    let json: URL

    /// How many workouts are in them.
    let sessionCount: Int

    /// How many sets are in them.
    let setCount: Int
}

/// Writes an archive out as the two files the share sheet hands on.
enum TrainingLogExportWriter {
    /// The BOM Excel needs to read a UTF-8 CSV as UTF-8.
    ///
    /// **On the file rather than in the rendered text**, so that the text a test asserts on is the
    /// text a parser sees. Without it a note containing anything outside ASCII is decoded in the
    /// reader's legacy encoding and comes out as mojibake — the failure mode this file's whole point
    /// is to avoid.
    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    /// Writes both files into `directory`, replacing anything already there under the same names.
    ///
    /// **One directory per export, emptied first.** The names carry the export's date, so two
    /// exports on one day would otherwise leave the second sharing a directory with the first and a
    /// share sheet handing on a file the lifter has already changed.
    ///
    /// - Parameters:
    ///   - archive: The log to write.
    ///   - unit: The unit the CSV's weight column is in.
    ///   - directory: Where to write. Created if it does not exist.
    ///   - timeZone: The zone the dates in the file and in its name are read in.
    /// - Returns: Both files, and what is in them.
    /// - Throws: Whatever `FileManager` or the encoder throws.
    static func write(
        _ archive: TrainingLogArchive,
        unit: MassUnit,
        into directory: URL,
        timeZone: TimeZone = .current
    ) throws -> TrainingLogExportFiles {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.removeItem(at: directory)
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let stem = name(for: archive.exportedAt, timeZone: timeZone)
        let csv = directory.appending(path: "\(stem).csv")
        let json = directory.appending(path: "\(stem).json")
        let text = TrainingLogCSV.render(archive, unit: unit, timeZone: timeZone)
        try (byteOrderMark + Data(text.utf8)).write(to: csv, options: .atomic)
        try archive.encoded().write(to: json, options: .atomic)
        return TrainingLogExportFiles(
            csv: csv,
            json: json,
            sessionCount: archive.sessions.count,
            setCount: archive.sets.count)
    }

    /// Both files' shared stem: the app's name, what the file is, and the day it was taken.
    ///
    /// - Parameters:
    ///   - exportedAt: When the export was taken.
    ///   - timeZone: The zone that date is read in.
    /// - Returns: A file name with no extension.
    static func name(for exportedAt: Date, timeZone: TimeZone = .current) -> String {
        "Attempt-training-log-\(TrainingLogCSV.day(exportedAt, in: timeZone))"
    }
}
