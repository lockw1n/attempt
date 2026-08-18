import AppNavigation
import DesignSystem
import SwiftUI

/// What every route currently leads to.
///
/// The shell is the deliverable; the destinations are each a later task's (`T-1.10` onwards), so
/// this stands in for all of them and is **deleted as they land** rather than grown into a screen.
/// It does two things a placeholder has to do to be worth having: it pushes a real ``Route`` onto a
/// real stack, so restoration can be exercised end to end, and it gives Home the "Start workout"
/// action (`FR-1.9.4`) so that action exists as a navigation from the first build.
struct PlaceholderScreen: View {
    private let tab: AppTab?
    private let route: Route?
    private let navigation: NavigationState?

    /// A tab's root.
    init(tab: AppTab, navigation: NavigationState) {
        self.tab = tab
        self.route = nil
        self.navigation = navigation
    }

    /// A pushed destination.
    init(route: Route) {
        self.tab = nil
        self.route = route
        self.navigation = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.sm.points) {
                        Text("Not built yet")
                            .font(Typography.cardTitle.font)
                            .foregroundStyle(ColorToken.textPrimary)
                        Text(verbatim: descriptor)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }

                if let tab {
                    if tab == .home, let navigation {
                        Button("Start workout") { navigation.startWorkout() }
                            .buttonStyle(.primaryAction(.fill))
                    }

                    NavigationLink(value: Self.sampleRoute(for: tab)) {
                        Text("Push a route")
                            .font(Typography.actionLabel.font)
                            .foregroundStyle(ColorToken.brandAccent)
                    }
                }
            }
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(navigationTitle)
    }

    private var navigationTitle: LocalizedStringKey {
        if let tab { return tab.title }
        return "Placeholder"
    }

    /// The route in words. `verbatim`, because a case name is diagnostic output rather than copy —
    /// nothing here should reach the string catalogue and then have to be translated before it is
    /// deleted.
    private var descriptor: String {
        if let route { return String(describing: route) }
        if let tab { return "\(tab.rawValue) root" }
        return ""
    }

    /// One pushable route per tab, so every stack can be driven to depth 1 by hand — which is how
    /// the restore is checked in the simulator, and the only reason this mapping exists.
    private static func sampleRoute(for tab: AppTab) -> Route {
        switch tab {
        case .home: .dashboard(.recentPersonalRecords)
        case .train: .exerciseLibrary(.exerciseDetail(exerciseID: sampleID))
        case .history: .history(.session(sessionID: sampleID))
        case .settings: .settings(.about)
        }
    }

    /// A fixed identifier, so a restored stack is visibly the same one rather than a fresh push.
    private static let sampleID = UUID(uuidString: "0F5A1E24-9B7D-4C31-8E62-1A2B3C4D5E6F") ?? UUID()
}

#Preview {
    NavigationStack {
        PlaceholderScreen(tab: .home, navigation: NavigationState())
    }
}
