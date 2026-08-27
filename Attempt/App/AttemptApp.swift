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
                // The catalogue, before any screen reads it (TR-0.5.1). Here rather than in the
                // exercise list's own `.task`, because the seed belongs to the app and not to one
                // screen: the picker inside a session reads the same rows.
                .task { await dependencies.importSeedCatalogue() }
                // The stored preferences the recompute pipeline reads (FR-1.7.2). Here rather than
                // in Settings' own `.task`, because the formula is the app's and not that screen's:
                // an exercise's estimate is drawn under it whether or not Settings was ever opened.
                .task { await dependencies.adoptStoredPreferences() }
                // On the snapshot rather than on the tab or a path: one observation covers a tab
                // switch, a push and a back-swipe, and it cannot be the wrong one of the four.
                .onChange(of: navigation.snapshot) { _, snapshot in
                    store.save(snapshot)
                }
        }
    }
}
