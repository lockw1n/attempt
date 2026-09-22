import SwiftUI

/// The shell's navigation state: which tab is in front, and what each tab has pushed (`TR-1.1`).
///
/// One object for all four stacks rather than one per tab, because the operations that matter are
/// cross-tab: a route names the tab that owns it (``Route/tab``), so navigating to one is a tab
/// selection *and* a push, and ``showTrain()`` is a tab selection with no push at all.
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

    /// Takes `tab`'s topmost route off the stack.
    ///
    /// **This is how a screen leaves when a `dismiss()` would not reach it** — a screen that is
    /// presenting something of its own is not the topmost thing on the display, and dismissing
    /// from it takes down what it presented rather than itself. Removing its route takes the
    /// screen down and whatever it was presenting with it, in one move. `FR-18.1.4`'s picker is
    /// the case: it saves an exercise in a form it pushed, and the lifter belongs back on the day.
    ///
    /// **A method here rather than a `path(for:)`/`setPath(_:for:)` pair at the call site**, so
    /// the empty-stack answer is decided once. A view that read the path and removed its last
    /// element would be the same decision written where nothing can test it (`T-1.96`).
    ///
    /// - Parameter tab: Whose stack to pop. Usually ``selectedTab``.
    /// - Returns: `false` when that stack was already at its root and nothing was popped, so a
    ///   caller with another way out can take it.
    @discardableResult
    public func pop(_ tab: AppTab) -> Bool {
        guard var path = stacks[tab], !path.isEmpty else { return false }
        path.removeLast()
        stacks[tab] = path
        return true
    }

    /// Selects Train and drops it to its root.
    ///
    /// A **navigation**, deliberately — `D-8` made Train the one place a workout is logged, and an
    /// inline logging surface presented from another tab would put the duplication straight back.
    /// The stack is dropped so the destination is always the week rather than wherever Train was
    /// left.
    ///
    /// **Named for where it goes, not for what the caller offers**, since `FR-1.9.4`'s withdrawal
    /// left it with none that names a workout: Home's first launch (`FR-1.13.2`) and History's
    /// three empty states — the session list's, the calendar's and the week view's
    /// (`FR-17.11.1`). All four offer **Plan your week**, which is what this arrives at
    /// (`FR-17.8.5`) — a caller that named a workout would name something the destination does
    /// not do.
    public func showTrain() {
        popToRoot(.train)
        selectedTab = .train
    }

    /// The current position, for persisting.
    public var snapshot: NavigationSnapshot {
        NavigationSnapshot(selectedTab: selectedTab, stacks: stacks)
    }
}
