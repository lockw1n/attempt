import AppNavigation
import SwiftUI

extension AppTab {
    /// The tab's user-visible name.
    ///
    /// Here and not on `AppTab` itself: the type is in a package, and a package that named its own
    /// tabs would be resolving copy against its own bundle rather than the app's catalogue
    /// (`G-3.4`) — the same rule `DesignSystem` states for components. The tab bar and each tab's
    /// root title both read this, so a tab's name is written once.
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .train: "Train"
        case .history: "History"
        case .settings: "Settings"
        }
    }
}
