import SwiftUI

/// The shell's navigation state: which tab is in front, and what each tab has pushed (`TR-1.1`).
///
/// One object for all four stacks rather than one per tab, because the operations that matter are
/// cross-tab: a route names the tab that owns it (``Route/tab``), so navigating to one is a tab
/// selection *and* a push, and Home's "Start workout" is a tab selection with no push at all.
///
/// `@Observable`, and there is exactly one of it (`TR-1.2` — no view model per view). A feature's
/// own state belongs in that feature's store; what belongs here is position.
@MainActor
@Observable
public final class NavigationState {
    /// The tab in front. Bound to the root `TabView`'s selection.
    public var selectedTab: AppTab

    private var stacks: [AppTab: [Route]]

    /// Restores from `snapshot` — ``NavigationSnapshot/initial`` on a first launch.
    public init(snapshot: NavigationSnapshot = .initial) {
        selectedTab = snapshot.selectedTab
        stacks = snapshot.stacks
    }

    /// What `tab` has pushed above its root.
    public func path(for tab: AppTab) -> [Route] {
        stacks[tab] ?? []
    }

    /// Replaces `tab`'s stack — what a `NavigationStack` writes back through when the user taps
    /// Back. An empty stack is a tab at its root; that it is *stored* as no stack at all is
    /// ``NavigationSnapshot``'s rule, and restating it here would be a second home for it.
    public func setPath(_ path: [Route], for tab: AppTab) {
        stacks[tab] = path
    }

    /// A binding onto `tab`'s stack, for that tab's `NavigationStack(path:)`.
    ///
    /// A method rather than a `@Bindable` key path because the stacks are one dictionary: four
    /// stored properties would be four of everything downstream, including four `navigationDestination`
    /// switches.
    public func binding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.path(for: tab) },
            set: { self.setPath($0, for: tab) }
        )
    }

    /// Pushes `route` onto the stack of the tab that owns it, and brings that tab forward.
    ///
    /// This is the whole of deep linking: an entry point that has a `Route` does not need to know
    /// which tab it lives under, which is what keeps a caller from selecting the wrong one and
    /// pushing anyway.
    public func navigate(to route: Route) {
        selectedTab = route.tab
        stacks[route.tab, default: []].append(route)
    }

    /// Drops `tab` back to its root.
    public func popToRoot(_ tab: AppTab) {
        stacks[tab] = nil
    }

    /// The dashboard's primary action (`FR-1.9.4`): go to Train.
    ///
    /// A **navigation**, deliberately — `D-8` removed the reference's duplication by making Train
    /// the one place a workout is logged, and an inline logging surface presented from Home would
    /// put it straight back. Train's stack is dropped to its root so the action always arrives at
    /// the same place; what that root shows once a session can exist is T-1.20's.
    public func startWorkout() {
        popToRoot(.train)
        selectedTab = .train
    }

    /// The current position, for persisting.
    public var snapshot: NavigationSnapshot {
        NavigationSnapshot(selectedTab: selectedTab, stacks: stacks)
    }
}
