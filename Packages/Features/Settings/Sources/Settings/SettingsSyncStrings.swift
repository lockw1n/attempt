import Foundation

/// The sync screen's copy (`FR-1.12.1`–`FR-1.12.3`, `G-3.4`).
///
/// The same type as the rest of this module's copy in a further file, on the rule the backup and
/// restore files follow: one screen's copy per file, so a key is found where the screen that draws
/// it is, and ``SettingsStrings/all`` stays the module's one list.
extension SettingsStrings {
    /// The screen's own title, and the landing row that opens it.
    static let syncTitle = resource("settings.sync.title")

    /// The heading over the switch. **Not the screen's title repeated**: the switch is device-local
    /// — deliberately not a synced row — and a heading echoing the navigation bar labels nothing.
    static let syncDeviceTitle = resource("settings.sync.device.title")

    /// The landing row's label.
    static let syncRow = resource("settings.sync.row")

    /// What the landing row says the screen is for.
    static let syncRowDetail = resource("settings.sync.row.detail")

    /// The switch itself (`FR-1.12.3`).
    static let syncToggle = resource("settings.sync.toggle")

    /// Whose iCloud the log goes to — the sentence About's privacy paragraph depends on.
    static let syncToggleDetail = resource("settings.sync.toggle.detail")

    /// The heading over the status.
    static let syncStatusTitle = resource("settings.sync.status.title")

    /// Switched off by the lifter.
    static let syncStatusOff = resource("settings.sync.status.off")

    /// On, with nothing in flight.
    static let syncStatusIdle = resource("settings.sync.status.idle")

    /// The account and zone check, which moves no records.
    static let syncStatusSetup = resource("settings.sync.status.setup")

    /// Records arriving.
    static let syncStatusDownload = resource("settings.sync.status.download")

    /// Records leaving.
    static let syncStatusUpload = resource("settings.sync.status.upload")

    /// The last finished attempt did not succeed.
    static let syncStatusFailed = resource("settings.sync.status.failed")

    /// What a failure means for the lifter's data — which is nothing.
    static let syncStatusFailedDetail = resource("settings.sync.status.failed.detail")

    /// Never yet synced, which is not a failure.
    static let syncLastNever = resource("settings.sync.last.never")

    /// `FR-1.12.3`'s promise, written where it is read before the switch rather than after.
    static let syncOffDetail = resource("settings.sync.off.detail")

    /// The switch is on and the running store is not — a restart is owed.
    static let syncRestartOn = resource("settings.sync.restart.on")

    /// The switch is off and the running store is still mirroring.
    static let syncRestartOff = resource("settings.sync.restart.off")

    /// When sync last worked.
    ///
    /// - Parameter formatted: The time, already written in the reader's locale.
    /// - Returns: The sentence.
    static func syncLastSynced(_ formatted: String) -> LocalizedStringResource {
        resource("settings.sync.last \(formatted)")
    }
}

extension SettingsStrings {
    /// Every string this screen draws, for the catalogue check.
    static var allSyncStrings: [LocalizedStringResource] {
        [
            syncTitle, syncDeviceTitle, syncRow, syncRowDetail, syncToggle, syncToggleDetail,
            syncStatusTitle, syncStatusOff, syncStatusIdle, syncStatusSetup,
            syncStatusDownload, syncStatusUpload, syncStatusFailed, syncStatusFailedDetail,
            syncLastNever, syncOffDetail, syncRestartOn, syncRestartOff,
            syncLastSynced("1 January 2026 at 09:12"),
        ]
    }
}
