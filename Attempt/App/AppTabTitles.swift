import AppNavigation
import SwiftUI

extension AppTab {
    /// The tab's user-visible name.
    ///
    /// Here and not on `AppTab` itself: the type is in a package, and a package that named its own
    /// tabs would be resolving copy against its own bundle rather than the app's catalogue
    /// (`G-3.4`) — the same rule `DesignSystem` states for components. The tab bar and each tab's
    /// root title both read this, so a tab's name is written once.
    ///
    /// A key literal is correct *here* and would be a defect in a feature module: `LocalizedStringKey`
    /// resolves against `Bundle.main`, which is this target's own catalogue. A module has to name
    /// its bundle, which is why `no_literal_ui_strings` covers `Packages/` and not this file.
    var title: LocalizedStringKey {
        switch self {
        case .home: "app.tab.home"
        case .train: "app.tab.train"
        case .history: "app.tab.history"
        case .settings: "app.tab.settings"
        }
    }
}
