import AppNavigation
import Testing

@testable import Logging

/// What **Done** does, where it can be tested (`FR-18.4.1`, `FR-18.4.3`).
///
/// **The decision is in a plain type for `T-1.96`'s reason, arriving from the other side.** Written
/// as three lines inside the toolbar's `Button`, "pop the tab in front, and fall back to `dismiss`
/// where there is no shell" would be reachable from no test at all: `AttemptTests` does not link
/// `AppNavigation`, so no hosted fixture there can put a real shell above the screen, and a
/// snapshot does not contain a toolbar. The hosted suite proves the button is on the screen and
/// answers; this proves what answering does.
@MainActor
@Suite("Leaving a screen that saves as it goes (FR-18.4.1)")
struct SessionExitTests {
    /// The ordinary case: the screen was pushed, and Done takes it off.
    @Test("Done pops the screen the tab in front has on top")
    func popsTheTopmostRoute() {
        let navigation = NavigationState()
        navigation.navigate(to: .training(.day(runID: .init(), week: 2, dayIndex: 0)))

        #expect(SessionExit.leave(navigation))

        #expect(
            navigation.path(for: .train).isEmpty,
            "Done said it popped and the day is still on the stack: \(navigation.path(for: .train))")
    }

    /// It pops **the tab in front**, not the tab the screen's module happens to live in.
    ///
    /// `PastSessionView` is a `Logging` screen answering a History route (`TR-1.3`), so a Done that
    /// named a tab rather than reading one would take the wrong screen down from exactly there.
    @Test("Done pops the tab in front, not the one its screen's module belongs to")
    func popsTheTabInFront() {
        let navigation = NavigationState()
        navigation.navigate(to: .training(.activeSession))
        navigation.navigate(to: .history(.session(sessionID: .init())))

        #expect(SessionExit.leave(navigation))

        #expect(navigation.path(for: .history).isEmpty)
        #expect(
            navigation.path(for: .train) == [.training(.activeSession)],
            "Done reached into another tab: Train holds \(navigation.path(for: .train))")
    }

    /// The two ways there is nothing to pop, which is what the fallback to `dismiss` is for.
    ///
    /// **No shell at all is the case a preview and a hosted fixture are both in**, and a stack
    /// already at its root is the case a screen drawn as a tab's root would be in.
    @Test("Done says so when there is nothing to pop")
    func saysSoWhenNothingWasPopped() {
        #expect(SessionExit.leave(nil) == false)

        let navigation = NavigationState()
        #expect(SessionExit.leave(navigation) == false)
    }

    /// One screen per tap, which is the difference between Done and Back-to-the-root.
    ///
    /// A day is reached from the week, and the week is itself a push on some routes: a Done that
    /// emptied the stack would take the lifter somewhere they were never coming from.
    @Test("Done takes one screen off, not the whole stack")
    func popsOneScreenOnly() {
        let navigation = NavigationState()
        navigation.navigate(to: .training(.activeSession))
        navigation.navigate(to: .training(.day(runID: .init(), week: 2, dayIndex: 0)))

        #expect(SessionExit.leave(navigation))

        #expect(
            navigation.path(for: .train) == [.training(.activeSession)],
            "Done emptied the stack: Train holds \(navigation.path(for: .train))")
    }
}
