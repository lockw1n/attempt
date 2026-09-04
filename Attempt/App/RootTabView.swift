import AppNavigation
import Dashboard
import DesignSystem
import ExerciseLibrary
import Foundation
import History
import Localization
import Logging
import PowerliftingCore
import RepositoryInterface
import Routines
import Settings
import SwiftUI

/// The four-tab root (`TR-1.1`, `D-8`): Home, Train, History, Settings, each with its own
/// `NavigationStack` bound to that tab's slice of ``NavigationState``.
///
/// **It lives in the app target rather than in `AppNavigation`, and the reason is the labels.** A
/// tab title is a user-visible string (`G-3.4`) and the app's catalogue is here; the package next
/// door holds the routing model precisely so it can hold no copy. Which tabs there are, and in what
/// order, is still `AppTab.allCases` — this view enumerates it rather than restating it.
struct RootTabView: View {
    @Bindable var navigation: NavigationState

    /// The store the tabs read through. See ``AppDependencies``.
    let dependencies: AppDependencies

    var body: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbolName, value: tab) {
                    stack(for: tab)
                }
            }
        }
        // The navigation position, for the feature screens whose entry point is a closure rather
        // than a `NavigationLink` — a state component's action, say. A screen that has a `Route`
        // does not need to know which tab it lives under (see `NavigationState.navigate(to:)`).
        .environment(navigation)
        .tint(ColorToken.brandAccent)
        // FR-1.10.2's stored theme, or G-7.1's dark until the row has been read — the store holds
        // both cases and the difference between them, so this view states neither.
        .preferredColorScheme(appearance)
        // G-3.3's step, ambient for locale's reason — see Localization's own note. Set once here
        // rather than by each screen that draws a load.
        .environment(\.displayPrecision, weightPrecision)
        // NFR-1.9. Applied over the whole shell rather than on the session screen, because the
        // workout does not stop being in progress when the user walks to the exercise library or
        // the plate calculator — the screen has to stay awake there too. What decides it is
        // Logging's; what does it is UIKit's, and this target is the only one that may say so.
        .keepScreenAwake(keepsScreenAwake)
    }

    /// One tab's stack. Every tab shares the same destination table, which is what one `Route` enum
    /// buys: a screen reachable from two tabs is one case and one `navigationDestination`.
    private func stack(for tab: AppTab) -> some View {
        NavigationStack(path: navigation.binding(for: tab)) {
            root(for: tab)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
    }

    /// What a pushed route shows.
    ///
    /// **Exhaustive as of `T-1.50`, which is why there is no `default` here any more**: every route
    /// but `settings.about` now has a screen, and a `default` covering one case is a compiler
    /// warning — and this target treats warnings as errors (`G-6.4`). Losing it is the better half
    /// of the trade anyway: a route case added from here on fails to compile until something answers
    /// it, where the catch-all silently gave it a placeholder.
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .exerciseLibrary(let route):
            exerciseLibraryDestination(route)
        case .routines(let route):
            routinesDestination(route)
        case .training(.activeSession):
            activeSessionRoot
        case .settings(let route):
            settingsDestination(route)
        case .history(.session(let sessionID)):
            pastSessionRoot(sessionID)
        case .history(.calendar):
            calendarRoot
        case .dashboard(.recentPersonalRecords):
            recentRecordsRoot
        case .dashboard(.estimatedMaxExercises):
            tiledExerciseSelectionRoot
        }
    }

    /// What a pushed routines route shows (`FR-15.2`).
    @ViewBuilder
    private func routinesDestination(_ route: RoutinesRoute) -> some View {
        switch route {
        case .routineList:
            routineListRoot
        case .routineCreate:
            routineEditorRoot(.create)
        case .routineEdit(let routineID):
            routineEditorRoot(.edit(routineID: routineID))
        }
    }

    /// The routines the lifter has authored (`FR-15.2.1`), or the reason they cannot be shown.
    ///
    /// **The fifth of this file's cross-module joins, and the second that hands over a command**
    /// (`FR-15.2.3`). Starting a workout is `Logging`'s to write and `TR-1.3` keeps `Routines` from
    /// importing it, so the screen takes a closure and this target — which owns both — supplies the
    /// store's own method. ``ActiveSessionStore/resume()`` runs first for
    /// ``dashboardRoot``'s reason: the store may never have looked, and starting without it would
    /// start a second workout on top of one already open.
    /// The store answers both a refusal and a failed write with `false` and the screen says
    /// different things about them, so the discrimination is made here — the one place with both.
    @ViewBuilder
    private var routineListRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            RoutineListView(repository: repositories.routines) { routineID in
                await stores.activeSession.resume()
                let started = await stores.activeSession.start(
                    on: .now, fromRoutineID: routineID, in: repositories.routines)
                // A refusal leaves the workout it would not replace held; a failed write does not.
                if started { return .started }
                return stores.activeSession.isActive ? .workoutInProgress : .writeFailed
            }
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The routine editor (`FR-15.2.1`, `FR-15.2.2`), or the reason it cannot be shown.
    ///
    /// **The store is the app's rather than the screen's**, unlike every other form here — see
    /// ``Routines/RoutineEditorState`` for why, and ``routineExercisePickerRoot`` for the other end
    /// of the same wire.
    ///
    /// - Parameter mode: Which of the two routine routes asked for it.
    @ViewBuilder
    private func routineEditorRoot(_ mode: RoutineEditorMode) -> some View {
        switch dependencies.state {
        case .open(_, let stores):
            RoutineEditorView(mode: mode, store: stores.routineEditor)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// One past session (`FR-1.2.7`, `FR-1.2.9`), or the reason it cannot be shown.
    ///
    /// **A `Logging` screen answering a History route**, which is the third of these joins and the
    /// same shape as the other two: everything a past session draws — the set row, the set editor,
    /// the note field — is `Logging`'s, `TR-1.3` keeps `History` and `Logging` from depending on
    /// each other, so this target composes them. It is handed the same modifier list and the same
    /// gym the workout in progress uses, so a set corrected here is corrected against what a set
    /// logged live is.
    ///
    /// The screen is handed the identifier the route carried, not a record: resolving it is the
    /// screen's own first read (`G-1.4`).
    @ViewBuilder
    private func pastSessionRoot(_ sessionID: UUID) -> some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            PastSessionView(
                sessionID: sessionID,
                workouts: repositories.workouts,
                catalogue: repositories.exercises,
                settings: repositories.settings,
                vocabulary: stores.modifiers,
                equipment: stores.equipment,
                records: stores.records,
                routines: repositories.routines
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.6.5`'s global feed of recent personal records, or the reason it cannot be shown.
    ///
    /// **Home's first real screen, and it is the one pushed from the tab rather than the tab root**
    /// — the dashboard behind it is `T-1.55`/`T-1.56`'s. Three dependencies, because a feed entry is
    /// three facts from three places: the cached record, the exercise the record names, and the unit
    /// its load reads in.
    @ViewBuilder
    private var recentRecordsRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            RecentRecordsView(
                records: stores.records,
                catalogue: repositories.exercises,
                settings: repositories.settings
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// `FR-1.9.1`'s picker: which exercises the dashboard tiles, or the reason it cannot be shown.
    @ViewBuilder
    private var tiledExerciseSelectionRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            TiledExerciseSelectionView(
                catalogue: repositories.exercises, settings: repositories.settings)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// Home's root — the dashboard (`FR-1.9`) — or the reason it cannot be shown.
    ///
    /// **The fourth of this file's cross-module joins, and the only one that hands over a command
    /// rather than a screen.** `FR-1.9.2`'s repeat starts a workout, which is `Logging`'s to write
    /// and `TR-1.3` keeps `Dashboard` from importing; so the dashboard takes a closure and this
    /// target — which owns both — supplies the store's own method. ``ActiveSessionStore/resume()``
    /// runs first because the store may never have looked: repeating without it would start a second
    /// workout on top of one already open.
    @ViewBuilder
    private var dashboardRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            DashboardView(
                records: stores.records,
                catalogue: repositories.exercises,
                workouts: repositories.workouts,
                settings: repositories.settings,
                repeatSession: { sessionID in
                    await stores.activeSession.resume()
                    return await stores.activeSession.start(on: .now, repeating: sessionID)
                }
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// A tab's root. All four are real screens now.
    ///
    /// The title is applied here rather than inside the feature package, for the reason
    /// ``AppTab/title`` gives: the catalogue is this target's (`G-3.4`).
    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .train:
            trainRoot
                .navigationTitle(tab.title)
        case .history:
            historyRoot
                .navigationTitle(tab.title)
        case .settings:
            settingsRoot
                .navigationTitle(tab.title)
        case .home:
            dashboardRoot
                .navigationTitle(tab.title)
        }
    }

    /// History's root — every session logged (`FR-1.5.1`) — or the reason it cannot be shown.
    ///
    /// Three repositories, because a summary line is three facts from three tables: the sessions and
    /// their sets, the catalogue the entries name, and the settings row that decides what unit the
    /// tonnage reads in. The screen joins them; `G-2.5` forbids the schema doing it.
    @ViewBuilder
    private var historyRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            SessionListView(
                workouts: repositories.workouts,
                exercises: repositories.exercises,
                settings: repositories.settings
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The month grid of training days (`FR-1.5.3`), or the reason it cannot be shown.
    ///
    /// The same three repositories as ``historyRoot``, and for the same reason: selecting a day
    /// draws that day's sessions as the list's own summary cards, which are three facts from three
    /// tables.
    @ViewBuilder
    private var calendarRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            CalendarView(
                workouts: repositories.workouts,
                exercises: repositories.exercises,
                settings: repositories.settings
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// Train's root — the session surface (`FR-1.2.1`) — or the reason it cannot be shown.
    @ViewBuilder
    private var trainRoot: some View {
        switch dependencies.state {
        case .open(_, let stores):
            TrainingHomeView(store: stores.activeSession)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The workout in progress, or the reason it cannot be shown.
    ///
    /// The route carries no identifier: which workout this is, is the store's (see
    /// ``Logging/ActiveSessionView``).
    @ViewBuilder
    private var activeSessionRoot: some View {
        switch dependencies.state {
        case .open(_, let stores):
            ActiveSessionView(
                store: stores.activeSession,
                vocabulary: stores.modifiers,
                equipment: stores.equipment
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// Whether the idle timer is held off right now (`NFR-1.9`) — a workout in progress, and the
    /// preference left on. A store that did not open keeps no workout, so it never holds it off.
    private var keepsScreenAwake: Bool {
        guard case .open(_, let stores) = dependencies.state else { return false }
        return stores.screenWake.keepsScreenAwake(duringSession: stores.activeSession.isActive)
    }

    /// The scheme every tab is drawn in (`FR-1.10.2`). A store that did not open has no stored
    /// theme to honour, so it gets `G-7.1`'s default — the same answer an unread row gets.
    private var appearance: ColorScheme? {
        guard case .open(_, let stores) = dependencies.state else {
            return Appearance.defaultColorScheme
        }
        return stores.display.colorScheme
    }

    /// The step every displayed load reads to (`G-3.3`), or `nil` for the unit's own.
    private var weightPrecision: DisplayPrecision? {
        guard case .open(_, let stores) = dependencies.state else { return nil }
        return stores.display.weightPrecision
    }
}

/// What a tab shows when the store did not open — the last of the shell's scaffolding, and owned
/// by whichever task takes on the launch failure surface.
///
/// Its copy is `verbatim` for the same reason: a string that is going to be deleted must not be
/// translated first (`G-3.4`).
///
/// **Internal rather than file-private**, because the Settings tab's destinations moved to a file
/// of their own and every one of them can fail this way. See `RootTabSettingsDestinations.swift`.
struct StoreUnavailableScreen: View {
    /// The error's description.
    let diagnostic: String

    /// A card naming the failure, and the diagnostic beneath it.
    var body: some View {
        ScrollView {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    Text(verbatim: "Storage unavailable")
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(verbatim: diagnostic)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
    }
}

#Preview {
    RootTabView(navigation: NavigationState(), dependencies: .preview)
}
