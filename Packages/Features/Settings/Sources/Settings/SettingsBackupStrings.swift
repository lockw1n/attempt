import Foundation

/// The backup screen's copy (`G-3.4`), in the same type as the rest of this module's — a fifth file
/// rather than a fifth enum, so ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The Settings row that opens the screen.
    static let backupRow = resource("settings.landing.backup.row")

    /// What is behind that row.
    static let backupDetail = resource("settings.landing.backup.detail")

    /// The screen's own name, which a pushed screen supplies for itself.
    static let backupTitle = resource("settings.backup.title")

    /// What a backup is, and how it differs from the export beside it.
    static let backupIntro = resource("settings.backup.intro")

    /// The file's name. The format is in the name because the lifter has to keep the file somewhere.
    static let backupFileTitle = resource("settings.backup.file.title")

    /// What is in it.
    static let backupFileDetail = resource("settings.backup.file.detail")

    /// The command that hands it over.
    static let backupShare = resource("settings.backup.share")

    /// Where the file can go — `FR-1.11.2`'s two paths, which are one sheet.
    static let backupDestinations = resource("settings.backup.destinations")

    /// That a removed row **is** in this file, which is the sentence the export's opposite number
    /// says the other way round (`G-1.3`).
    static let backupIncludesDeleted = resource("settings.backup.deleted")

    /// The wait while the whole store is read.
    static let backupPreparing = resource("settings.backup.preparing")

    /// The heading when the store could not be read or the file could not be written.
    static let backupErrorHeadline = resource("settings.backup.error.headline")

    /// What that means, in the user's words rather than the store's.
    static let backupErrorMessage = resource("settings.backup.error.message")

    /// How many rows the file holds.
    ///
    /// - Parameter count: The number of records.
    /// - Returns: The phrase, pluralised.
    static func backupRecordCount(_ count: Int) -> LocalizedStringResource {
        resource("settings.backup.summary.records \(count)")
    }

    /// How many workouts are among them.
    ///
    /// - Parameter count: The number of sessions.
    /// - Returns: The phrase, pluralised.
    static func backupWorkoutCount(_ count: Int) -> LocalizedStringResource {
        resource("settings.backup.summary.workouts \(count)")
    }

    /// How many of them are rows the lifter deleted.
    ///
    /// - Parameter count: The number of soft-deleted rows.
    /// - Returns: The phrase, pluralised.
    static func backupDeletedCount(_ count: Int) -> LocalizedStringResource {
        resource("settings.backup.summary.deleted \(count)")
    }

    /// The backup screen's keys, for the test that proves each one resolves.
    static var allBackupStrings: [LocalizedStringResource] {
        [
            backupRow, backupDetail, backupTitle, backupIntro,
            backupFileTitle, backupFileDetail, backupShare,
            backupDestinations, backupIncludesDeleted, backupPreparing,
            backupErrorHeadline, backupErrorMessage,
            backupRecordCount(2), backupWorkoutCount(2), backupDeletedCount(2),
        ]
    }
}
