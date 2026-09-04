import AppNavigation
import Dashboard
import DesignSystem
import Logging
import RepositoryInterface
import Settings
import SwiftUI

// The Settings tab's own destinations, in a file of their own.
//
// SPLIT FOR SIZE RATHER THAN FOR STRUCTURE, and the size is real: this tab now answers five routes
// and three of them assemble a screen out of two or four repositories, which took `RootTabView`
// past the file and type-body limits the lint rules hold every other file to. The split follows the
// line `settingsDestination(_:)` was already drawn along in T-1.50 — one tab's share of the
// destination table — so nothing here is a new idea about where the boundary is.
//
// INTERNAL RATHER THAN PRIVATE, which is the one thing the split costs. Swift's `private` is
// file-scoped, so a member the switch in RootTabView.swift still calls cannot keep it. What is
// reachable from another file in this target is deliberately only the two the shell asks for:
// `settingsRoot` for the tab, and `settingsDestination(_:)` for everything pushed from it.
extension RootTabView {
    /// What a pushed Settings route shows.
    ///
    /// Split out of ``destination(for:)`` rather than listed there with the rest: that switch is one
    /// case per screen in the app and this tab's share of it is what took it past the complexity the
    /// lint rules allow.
    @ViewBuilder
    func settingsDestination(_ route: SettingsRoute) -> some View {
        switch route {
        case .equipmentProfiles:
            equipmentProfilesRoot
        case .bodyweight:
            bodyweightRoot
        case .healthAccess:
            healthAccessRoot
        case .about:
            AboutView()
        case .dataExport:
            dataExportRoot
        case .backup:
            backupRoot
        case .restore:
            restoreRoot
        case .recentRecords:
            recentRecordsSettingsRoot
        case .sync:
            // NO STORE SWITCH HERE, unlike every other case in this function. The switch and the
            // status are facts about the container and the preference rather than rows in it, so a
            // store that did not open takes nothing away from this screen — and is arguably when a
            // lifter most wants to know whether their log ever reached iCloud.
            SyncSettingsView(control: dependencies.sync)
        }
    }

    /// `FR-16.3`: what the recent-PR feed reports on, or the reason it cannot be shown.
    ///
    /// **A `Dashboard` screen answering a Settings route**, which is the gyms' join in the other
    /// direction: the screen configures `FR-1.6.5`'s feed and reuses that module's picker row, and
    /// `TR-1.3` keeps the two feature modules from importing each other. It is handed the same
    /// recompute actor the feed subscribes to, which is what carries a change made here back to the
    /// dashboard without it being revisited (`TR-1.5`).
    @ViewBuilder
    private var recentRecordsSettingsRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            RecentRecordsSettingsView(
                settings: repositories.settings,
                catalogue: repositories.exercises,
                records: stores.records)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.11.1`/`FR-1.11.2`: the training log as files, or the reason it cannot be read.
    ///
    /// The same shape as ``settingsRoot``, and four repositories rather than one: an export is the
    /// whole log, so it reads through every protocol the log lives behind (`TR-0.1.2`).
    @ViewBuilder
    private var dataExportRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            DataExportView(
                exercises: repositories.exercises,
                workouts: repositories.workouts,
                bodyweight: repositories.bodyweight,
                settings: repositories.settings)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.11.3`: the whole store as one file, or the reason it cannot be read.
    ///
    /// Seven repositories — the export's four, plus the gyms, the routines and the training maxes:
    /// a backup is the configuration as well as the log, and `TR-0.1.2` hands each protocol down on
    /// its own.
    @ViewBuilder
    private var backupRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            BackupView(
                exercises: repositories.exercises,
                trainingMaxes: repositories.trainingMaxes,
                workouts: repositories.workouts,
                bodyweight: repositories.bodyweight,
                equipment: repositories.equipment,
                routines: repositories.routines,
                settings: repositories.settings)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.11.4`: a backup file read back onto this device, or the reason it cannot be.
    ///
    /// Eight, and the eighth is the recompute actor: the backup file carries no cached personal
    /// record (`TR-0.3.9`, `G-1.4`), so the rows a restore writes have to be walked again before any
    /// badge or estimated max on another tab is true.
    @ViewBuilder
    private var restoreRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            RestoreView(
                exercises: repositories.exercises,
                trainingMaxes: repositories.trainingMaxes,
                workouts: repositories.workouts,
                bodyweight: repositories.bodyweight,
                equipment: repositories.equipment,
                routines: repositories.routines,
                settings: repositories.settings,
                records: stores.records)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.10.4`: what Health access the app has.
    ///
    /// **It needs no store**, which is why there is no `dependencies.state` switch here: the screen
    /// reports on HealthKit alone, and a store that failed to open says nothing about whether Health
    /// was authorized. Constructing the source prompts for nothing — `TR-1.9` still owes the prompt
    /// to the import, and this screen reads the request's status without raising it.
    private var healthAccessRoot: some View {
        HealthAccessView(health: HealthBodyweightSource())
    }
    /// The gyms (`FR-1.10.3`), or the reason they cannot be shown.
    ///
    /// **A `Logging` screen answering a Settings route**, which is the exercise picker's join in its
    /// other direction: `FR-1.10.3` and `FR-1.4.2` are one screen described from two tabs, `TR-1.3`
    /// keeps `Settings` and `Logging` from depending on each other, so this target — which already
    /// owns both — is where the two meet. It is handed the same store the calculator loads against,
    /// so a gym switched here is the gym the next loading uses.
    @ViewBuilder
    private var equipmentProfilesRoot: some View {
        switch dependencies.state {
        case .open(_, let stores):
            EquipmentProfilesView(store: stores.equipment)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The bodyweight log (`FR-1.8.1`, `FR-1.8.3`), or the reason it cannot be shown.
    ///
    /// Two repositories, because a reading is two facts from two tables: the log itself, and the
    /// settings row that decides which unit it reads in.
    @ViewBuilder
    private var bodyweightRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            BodyweightLogView(
                repository: repositories.bodyweight,
                settings: repositories.settings,
                // FR-1.8.2. Constructing it prompts for nothing — the screen's own command is what
                // asks, which is TR-1.9's "on first use, not at launch".
                health: HealthBodyweightSource())
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The Settings tab's landing screen, or the reason it cannot be shown.
    @ViewBuilder
    var settingsRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            SettingsLandingView(
                repository: repositories.settings,
                records: stores.records,
                // FR-1.10.4's row is drawn only where there is a Health to talk about, which is
                // the one thing the landing asks of the source. Constructing it prompts for
                // nothing — TR-1.9's prompt is still the import's.
                health: HealthBodyweightSource(),
                // NFR-1.9 and FR-1.10.2 are held by objects the Settings module cannot import, so
                // the composition root is what carries a landed write to them.
                preferencesDidChange: { settings in
                    stores.display.adopt(settings)
                    stores.screenWake.adopt(settings.keepScreenAwake)
                })
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }
}
