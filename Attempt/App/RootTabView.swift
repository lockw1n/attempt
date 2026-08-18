import AppNavigation
import DesignSystem
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
            PlaceholderScreen(tab: tab, navigation: navigation)
                .navigationDestination(for: Route.self) { route in
                    PlaceholderScreen(route: route)
                }
        }
    }
}

#Preview {
    RootTabView(navigation: NavigationState())
}
