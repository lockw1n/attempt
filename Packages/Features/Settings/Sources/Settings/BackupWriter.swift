import Foundation
import RepositoryInterface

/// The one file a backup produces, and what the screen says about it (`FR-1.11.3`).
struct BackupFile: Equatable, Sendable {
    /// Where it was written.
    let url: URL

    /// How many workouts it holds.
    let workoutCount: Int

    /// How many rows it holds in total — ``TrainingLogArchive/recordCount``, which is where the
    /// reading it takes is argued.
    let recordCount: Int

    /// How many of those rows are ones the lifter deleted —
    /// ``TrainingLogArchive/deletedCount``.
    ///
    /// Drawn beside ``recordCount`` rather than folded into it, because it is the half of the file
    /// an export does not have and the only thing that makes "a backup is not the export" visible.
    let deletedCount: Int
}

/// Writes an archive out as the single file the share sheet hands on.
enum BackupWriter {
    /// Writes the backup into `directory`, replacing anything already there under the same name.
    ///
    /// **One directory per backup, emptied first** — ``TrainingLogExportWriter``'s rule and its
    /// reason: the name carries the day, so it is the *next* day's backup that needs the sweep. Two
    /// taken on one day share a name and the atomic write below replaces the first; taken a day
    /// apart they do not, and the directory would keep handing a share sheet a file describing a
    /// store the lifter has already moved past.
    ///
    /// - Parameters:
    ///   - archive: The store to write. Expected to be a ``TrainingLogArchive/Contents/fullBackup``;
    ///     nothing here refuses another, since the file's own `contents` is what a reader asks.
    ///   - directory: Where to write. Created if it does not exist.
    ///   - timeZone: The zone the day in the file's name is read in.
    /// - Returns: The file, and what is in it.
    /// - Throws: Whatever `FileManager` or the encoder throws.
    static func write(
        _ archive: TrainingLogArchive,
        into directory: URL,
        timeZone: TimeZone = .current
    ) throws -> BackupFile {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.removeItem(at: directory)
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appending(path: "\(name(for: archive.exportedAt, timeZone: timeZone)).json")
        try archive.encoded().write(to: url, options: .atomic)
        return BackupFile(
            url: url,
            workoutCount: archive.sessions.count,
            recordCount: archive.recordCount,
            deletedCount: archive.deletedCount)
    }

    /// The file's name: the app's name, what the file is, and the day it was taken.
    ///
    /// **`.json` rather than an extension of this app's own**, which is `FR-1.11.2`'s share sheet
    /// deciding it: a private extension would need a declared uniform type before any destination
    /// would accept the file, and would make the backup unreadable by anything but this app for no
    /// gain — the bytes are JSON, and what kind of JSON is
    /// ``TrainingLogArchive/contents``' answer rather than the file name's.
    ///
    /// - Parameters:
    ///   - takenAt: When the backup was taken.
    ///   - timeZone: The zone that date is read in.
    /// - Returns: A file name with no extension.
    static func name(for takenAt: Date, timeZone: TimeZone = .current) -> String {
        "Attempt-backup-\(TrainingLogCSV.day(takenAt, in: timeZone))"
    }
}
