import AppNavigation
import DesignSystem
import ExerciseLibrary
import Foundation
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
        case .open(let repositories):
            ExerciseListView(repository: repositories.exercises)
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
        case .open(let repositories):
            ExerciseDetailView(exerciseID: exerciseID, repository: repositories.exercises)
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
        case .open(let repositories):
            ExerciseFormView(mode: mode, repository: repositories.exercises)
        case .failed(let diagnostic):
            StoreUnavailableScreen(diagnostic: diagnostic)
        }
    }

    /// A tab's root. Settings is the first real screen; the other three are still scaffolding.
    ///
    /// The title is applied here rather than inside the feature package, for the reason
    /// ``AppTab/title`` gives: the catalogue is this target's (`G-3.4`).
    @ViewBuilder
    private func root(for tab: AppTab) -> some View {
        switch tab {
        case .settings:
            settingsRoot
                .navigationTitle(tab.title)
        case .home, .train, .history:
            PlaceholderScreen(tab: tab, navigation: navigation)
        }
    }

    /// The Settings tab's landing screen, or the reason it cannot be shown.
    @ViewBuilder
    private var settingsRoot: some View {
        switch dependencies.state {
        case .open(let repositories):
            SettingsLandingView(repository: repositories.settings)
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
