import AppNavigation
import SwiftUI

/// Composition root (`TR-0.1`).
///
/// This target owns the entry point and dependency wiring, nothing else. Domain logic lives in
/// `PowerliftingCore`, storage in `Persistence`, presentation tokens in `DesignSystem`, the
/// navigation model in `AppNavigation` — all under `Packages/`.
///
/// The wiring it does is the store (``AppDependencies``) and `TR-1.1`'s restoration loop: read the
/// stored position before the first frame, and write it back whenever it changes. Both halves of the
/// loop belong here rather than in `RootTabView`, because a view that persisted its own navigation
/// would persist it once per place it was used.
@main
struct AttemptApp: App {
    @State private var navigation: NavigationState
    private let store: any NavigationStateStore
    private let dependencies = AppDependencies()

    init() {
        let store = UserDefaultsNavigationStateStore()
        self.store = store
        _navigation = State(initialValue: NavigationState(snapshot: store.load() ?? .initial))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(navigation: navigation, dependencies: dependencies)
                // On the snapshot rather than on the tab or a path: one observation covers a tab
                // switch, a push and a back-swipe, and it cannot be the wrong one of the four.
                .onChange(of: navigation.snapshot) { _, snapshot in
                    store.save(snapshot)
                }
        }
    }
}
