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
///
/// **Its own copy is `verbatim`** — scaffolding must not reach the string catalogue and be
/// translated before it is deleted (`G-3.4`). The exceptions are the two strings that outlive this
/// file: the tab titles, which come from ``AppTab/title``, and "Start workout".
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
                        Text(verbatim: "Not built yet")
                            .font(Typography.cardTitle.font)
                            .foregroundStyle(ColorToken.textPrimary)
                        Text(verbatim: descriptor)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }

                if let tab {
                    if tab == .home, let navigation {
                        Button("app.home.start-workout") { navigation.startWorkout() }
                            .buttonStyle(.primaryAction(.fill))
                    }

                    NavigationLink(value: Self.sampleRoute(for: tab)) {
                        Text(verbatim: "Push a route")
                            .font(Typography.actionLabel.font)
                            .foregroundStyle(ColorToken.brandAccent)
                    }
                }
            }
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(title)
    }

    /// A `Text` rather than a `LocalizedStringKey`, so a tab's real title and a pushed screen's
    /// scaffolding label can be the two different kinds of string they are.
    private var title: Text {
        if let tab { return Text(tab.title) }
        return Text(verbatim: "Placeholder")
    }

    /// The route in words — diagnostic output rather than copy.
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
        // Train's is the real screen, not a sample: the exercise library is built (T-1.10) and its
        // root — the session surface — is not, so this placeholder is currently the only way to
        // reach it. T-1.20 replaces this whole screen with that surface and puts the library behind
        // an entry point of its own.
        case .train: .exerciseLibrary(.exerciseList)
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
