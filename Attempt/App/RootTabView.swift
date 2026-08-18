import AppNavigation
import DesignSystem
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
                    PlaceholderScreen(route: route)
                }
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
