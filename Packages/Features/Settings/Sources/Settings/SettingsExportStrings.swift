import Foundation

/// The export screen's copy (`G-3.4`), in the same type as the rest of this module's — a fourth file
/// rather than a fourth enum, so ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The Settings section that holds the way out to the data.
    static let dataSectionTitle = resource("settings.landing.data.title")

    /// The Settings row that opens the screen.
    static let dataExportRow = resource("settings.landing.data.row")

    /// What is behind that row.
    static let dataExportDetail = resource("settings.landing.data.detail")

    /// The screen's own name, which a pushed screen supplies for itself.
    static let exportTitle = resource("settings.export.title")

    /// What an export is, before either format is offered.
    static let exportIntro = resource("settings.export.intro")

    /// The spreadsheet format's name. The format is in the name because the lifter has to hand the
    /// file to something.
    static let exportCSVTitle = resource("settings.export.csv.title")

    /// What is in the CSV, and what it is for.
    static let exportCSVDetail = resource("settings.export.csv.detail")

    /// The lossless format's name.
    static let exportJSONTitle = resource("settings.export.json.title")

    /// What is in the JSON, and what it is for.
    static let exportJSONDetail = resource("settings.export.json.detail")

    /// The command on each format's row.
    static let exportShare = resource("settings.export.share")

    /// Where a shared file can go — `FR-1.11.2`'s two paths, which are one sheet.
    static let exportDestinations = resource("settings.export.destinations")

    /// That a removed set is not in the file (`G-1.3`).
    static let exportExcludesDeleted = resource("settings.export.deleted")

    /// The wait while the whole log is read.
    static let exportPreparing = resource("settings.export.preparing")

    /// The heading when there is no log yet.
    static let exportEmptyHeadline = resource("settings.export.empty.headline")

    /// What would make one.
    static let exportEmptyMessage = resource("settings.export.empty.message")

    /// The heading when the log could not be read or the file could not be written.
    static let exportErrorHeadline = resource("settings.export.error.headline")

    /// What that means, in the user's words rather than the store's.
    static let exportErrorMessage = resource("settings.export.error.message")

    /// How many workouts the file holds.
    ///
    /// - Parameter count: The number of sessions.
    /// - Returns: The phrase, pluralised.
    static func exportWorkoutCount(_ count: Int) -> LocalizedStringResource {
        resource("settings.export.summary.workouts \(count)")
    }

    /// How many sets the file holds.
    ///
    /// - Parameter count: The number of sets.
    /// - Returns: The phrase, pluralised.
    static func exportSetCount(_ count: Int) -> LocalizedStringResource {
        resource("settings.export.summary.sets \(count)")
    }

    /// The export screen's keys, for the test that proves each one resolves.
    static var allExportStrings: [LocalizedStringResource] {
        [
            dataSectionTitle, dataExportRow, dataExportDetail,
            exportTitle, exportIntro,
            exportCSVTitle, exportCSVDetail, exportJSONTitle, exportJSONDetail,
            exportShare, exportDestinations, exportExcludesDeleted, exportPreparing,
            exportEmptyHeadline, exportEmptyMessage, exportErrorHeadline, exportErrorMessage,
            exportWorkoutCount(2), exportSetCount(2),
        ]
    }
}
