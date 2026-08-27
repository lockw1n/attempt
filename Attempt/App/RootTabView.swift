import AppNavigation
import Dashboard
import DesignSystem
import ExerciseLibrary
import Foundation
import History
import Logging
import RepositoryInterface
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
        // G-7.1's dark default, from the token rather than from a literal `.dark` — the one place
        // that says so is DesignTokens. FR-1.10.2's user preference (T-1.60) overrides this; it does
        // not replace it.
        .preferredColorScheme(Appearance.defaultColorScheme)
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

    /// What a pushed route shows. Built routes get their screen; the rest still get the placeholder,
    /// which is deleted case by case as the owning tasks land.
    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .exerciseLibrary(.exerciseList):
            // No title here: a pushed screen names itself, and this one does (`FR-1.1.1`). The tab
            // roots are the case where the app target owns the name — see ``AppTab/title``.
            exerciseListRoot
        case .exerciseLibrary(.exerciseDetail(let exerciseID)):
            exerciseDetailRoot(exerciseID)
        case .exerciseLibrary(.exerciseCreate):
            exerciseFormRoot(.create)
        case .exerciseLibrary(.exerciseEdit(let exerciseID)):
            exerciseFormRoot(.edit(exerciseID: exerciseID))
        case .exerciseLibrary(.exercisePicker):
            exercisePickerRoot
        case .training(.activeSession):
            activeSessionRoot
        case .settings(.equipmentProfiles):
            equipmentProfilesRoot
        case .history(.session(let sessionID)):
            pastSessionRoot(sessionID)
        case .history(.calendar):
            calendarRoot
        case .dashboard(.recentPersonalRecords):
            recentRecordsRoot
        default:
            PlaceholderScreen(route: route)
        }
    }

    /// The exercise library's list, or the reason it cannot be shown.
    ///
    /// The same shape as ``settingsRoot``: a screen that reads a store cannot be built when the
    /// store did not open, and the diagnostic is the app's rather than the screen's.
    @ViewBuilder
    private var exerciseListRoot: some View {
        switch dependencies.state {
        case .open(let repositories, _):
            ExerciseListView(repository: repositories.exercises, workouts: repositories.workouts)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// One exercise's detail, or the reason it cannot be shown.
    ///
    /// The screen is handed the identifier the route carried, not a record: resolving it is the
    /// screen's own first read (`G-1.4`).
    @ViewBuilder
    private func exerciseDetailRoot(_ exerciseID: UUID) -> some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseDetailView(
                exerciseID: exerciseID,
                repository: repositories.exercises,
                workouts: repositories.workouts,
                settings: repositories.settings,
                records: stores.records
            )
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The create/edit form, or the reason it cannot be shown.
    ///
    /// - Parameter mode: Which of `FR-1.1.3` and `FR-1.1.4` the route asked for.
    @ViewBuilder
    private func exerciseFormRoot(_ mode: ExerciseFormMode) -> some View {
        switch dependencies.state {
        case .open(let repositories, _):
            ExerciseFormView(mode: mode, repository: repositories.exercises)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// The catalogue as `FR-1.2.2`'s chooser, or the reason it cannot be shown.
    ///
    /// **This is the join between the two feature modules that share the Train tab**, and it is here
    /// because nowhere else may make it: `Logging` and `ExerciseLibrary` do not depend on each other
    /// (`TR-1.3`), so the screen that chooses an exercise and the store that receives one are
    /// composed by the target that already owns both. The library screen takes a closure and knows
    /// nothing about workouts; the store takes an identifier and knows nothing about catalogues.
    @ViewBuilder
    private var exercisePickerRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            ExerciseListView(
                repository: repositories.exercises, workouts: repositories.workouts
            ) { exercise in
                await stores.activeSession.addExercise(id: exercise.id)
            }
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
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
                records: stores.records
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

    /// A tab's root. Three are real screens now; Home is still scaffolding.
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
            PlaceholderScreen(tab: tab, navigation: navigation)
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
            TrainingHomeView(store: stores.activeSession, screenWake: stores.screenWake)
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

    /// The Settings tab's landing screen, or the reason it cannot be shown.
    @ViewBuilder
    private var settingsRoot: some View {
        switch dependencies.state {
        case .open(let repositories, let stores):
            SettingsLandingView(repository: repositories.settings, records: stores.records)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }
}

/// What a tab shows when the store did not open — scaffolding, like ``PlaceholderScreen``, and
/// owned by whichever task takes on the launch failure surface.
///
/// Its copy is `verbatim` for the same reason: a string that is going to be deleted must not be
/// translated first (`G-3.4`).
private struct StoreUnavailableScreen: View {
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
