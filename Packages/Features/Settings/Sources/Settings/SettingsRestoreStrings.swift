import Foundation

/// The restore screen's copy (`G-3.4`), in the same type as the rest of this module's — a sixth file
/// rather than a sixth enum, so ``SettingsStrings/all`` stays the module's one list.
///
/// **The summary's three counts are the backup screen's own keys.** A restore says how many records,
/// how many workouts and how many deleted rows a file holds, which is exactly the sentence the backup
/// screen says about the same file — a second set would be two spellings of one phrase. What is
/// different here is what those deleted rows *do*, and that is a sentence of this screen's own rather
/// than a word inside a count.
extension SettingsStrings {
    /// The Settings row that opens the screen.
    static let restoreRow = resource("settings.landing.restore.row")

    /// What is behind that row.
    static let restoreDetail = resource("settings.landing.restore.detail")

    /// The screen's own name, which a pushed screen supplies for itself.
    static let restoreTitle = resource("settings.restore.title")

    /// That no file has been chosen yet.
    static let restoreWaitingHeadline = resource("settings.restore.waiting.headline")

    /// Which file to look for, and that choosing one changes nothing on its own.
    static let restoreWaitingMessage = resource("settings.restore.waiting.message")

    /// The command that opens the picker.
    static let restoreChoose = resource("settings.restore.choose")

    /// The wait while the file is read and checked.
    static let restoreReading = resource("settings.restore.reading")

    /// The heading over the destructive question.
    static let restoreConfirmTitle = resource("settings.restore.confirm.title")

    /// What restoring does, and what it does not do.
    static let restoreConfirmDetail = resource("settings.restore.confirm.detail")

    /// That deleted rows in the file come back as ordinary ones — gap in the mapping layer stated
    /// rather than left silent, which is this screen's own call (`G-1.3`).
    static let restoreConfirmDeleted = resource("settings.restore.confirm.deleted")

    /// The command that raises the confirmation.
    static let restoreConfirmAction = resource("settings.restore.confirm.action")

    /// The way back out to the picker.
    static let restoreConfirmOther = resource("settings.restore.confirm.other")

    /// The confirmation's own question, asked again in the dialog.
    static let restoreDialogTitle = resource("settings.restore.dialog.title")

    /// What the dialog says under it.
    static let restoreDialogMessage = resource("settings.restore.dialog.message")

    /// The destructive answer.
    static let restoreDialogAction = resource("settings.restore.dialog.action")

    /// The way out of the dialog, spelled rather than left to the system's own.
    static let restoreDialogCancel = resource("settings.restore.dialog.cancel")

    /// The wait while the rows are written.
    static let restoreRestoring = resource("settings.restore.restoring")

    /// That it finished.
    static let restoreDoneHeadline = resource("settings.restore.done.headline")

    /// What the lifter should do next, which is look at their own log.
    static let restoreDoneDetail = resource("settings.restore.done.detail")

    /// When the backup was taken.
    ///
    /// - Parameter day: The date, already rendered in the reader's locale.
    /// - Returns: The phrase.
    static func restoreTakenOn(_ day: String) -> LocalizedStringResource {
        resource("settings.restore.taken \(day)")
    }

    /// The heading when the file is not a backup at all.
    static let restoreNotBackupHeadline = resource("settings.restore.refused.export.headline")

    /// Which file to look for instead.
    static let restoreNotBackupMessage = resource("settings.restore.refused.export.message")

    /// The heading when the file is from a later version of the app.
    static let restoreFutureHeadline = resource("settings.restore.refused.future.headline")

    /// What to do about that, which is update rather than find another file.
    static let restoreFutureMessage = resource("settings.restore.refused.future.message")

    /// The heading when the bytes are not readable at all.
    static let restoreUnreadableHeadline = resource("settings.restore.refused.unreadable.headline")

    /// What that usually means.
    static let restoreUnreadableMessage = resource("settings.restore.refused.unreadable.message")

    /// The heading when a write failed with rows already written.
    static let restoreErrorHeadline = resource("settings.restore.error.headline")

    /// That the device is part-way, and that running the same file again finishes it.
    static let restoreErrorMessage = resource("settings.restore.error.message")

    /// The command that runs the same file again.
    static let restoreErrorRetry = resource("settings.restore.error.retry")

    /// The restore screen's keys, for the test that proves each one resolves.
    static var allRestoreStrings: [LocalizedStringResource] {
        [
            restoreRow, restoreDetail, restoreTitle,
            restoreWaitingHeadline, restoreWaitingMessage, restoreChoose,
            restoreReading, restoreConfirmTitle, restoreConfirmDetail, restoreConfirmDeleted,
            restoreConfirmAction, restoreConfirmOther,
            restoreDialogTitle, restoreDialogMessage, restoreDialogAction, restoreDialogCancel,
            restoreRestoring, restoreDoneHeadline, restoreDoneDetail,
            restoreTakenOn("6 July 2025"),
            restoreNotBackupHeadline, restoreNotBackupMessage,
            restoreFutureHeadline, restoreFutureMessage,
            restoreUnreadableHeadline, restoreUnreadableMessage,
            restoreErrorHeadline, restoreErrorMessage, restoreErrorRetry,
        ]
    }
}
