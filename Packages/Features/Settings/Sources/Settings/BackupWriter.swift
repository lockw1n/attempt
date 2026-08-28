import Foundation
import RepositoryInterface

/// The one file a backup produces, and what the screen says about it (`FR-1.11.3`).
struct BackupFile: Equatable, Sendable {
    /// Where it was written.
    let url: URL

    /// How many workouts it holds.
    let workoutCount: Int

    /// How many rows it holds in total, across every section and counting the preferences row.
    ///
    /// **Records the store holds, not rows a restore gives back**, and the two differ today: a
    /// soft-deleted row is in this count and in the file, and `FR-1.11.4`'s restore currently
    /// reinstates it as a live row rather than a deleted one. The completeness reading is the one a
    /// backup's count has to mean — a number that quietly excluded rows the file contains would be
    /// the number that makes a lifter think the backup is short.
    let recordCount: Int

    /// How many of those rows are ones the lifter deleted.
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
    /// reason: the name carries the day, so two backups taken on one day would otherwise leave the
    /// second sharing a directory with the first and a share sheet handing on a file the lifter has
    /// already moved past.
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
            recordCount: recordCount(of: archive),
            deletedCount: deletedCount(of: archive))
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

    /// Every row in the file, across every section.
    ///
    /// - Parameter archive: The backup.
    /// - Returns: The total, counting the preferences row as the one row it is.
    private static func recordCount(of archive: TrainingLogArchive) -> Int {
        archive.exercises.count + archive.sessions.count + archive.entries.count
            + archive.sets.count + archive.bodyweight.count + archive.equipment.count
            + archive.trainingMaxes.count + (archive.settings == nil ? 0 : 1)
    }

    /// How many of those rows carry a ``StoredRecord/deletedAt``.
    ///
    /// - Parameter archive: The backup.
    /// - Returns: The count of soft-deleted rows.
    private static func deletedCount(of archive: TrainingLogArchive) -> Int {
        deleted(archive.exercises) + deleted(archive.sessions) + deleted(archive.entries)
            + deleted(archive.sets) + deleted(archive.bodyweight) + deleted(archive.equipment)
            + deleted(archive.trainingMaxes) + deleted(archive.settings.map { [$0] } ?? [])
    }

    /// How many of one section's rows are soft-deleted.
    ///
    /// - Parameter rows: One section.
    /// - Returns: The count.
    private static func deleted(_ rows: [some StoredRecord]) -> Int {
        rows.count { $0.deletedAt != nil }
    }
}
