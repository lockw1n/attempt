import Foundation
import Testing

@testable import AppNavigation

/// What the shell does, as opposed to what it stores: selecting a tab, pushing onto the right one,
/// and the one behaviour `D-8` bought — "Start workout" being a navigation and not a screen.
@Suite("Navigation state")
@MainActor
struct NavigationStateTests {
    /// The first launch. Pinned to literals rather than to `.initial`'s own fields, so a change to
    /// the initial position has to be made twice on purpose.
    @Test("a fresh state opens Home with nothing pushed")
    func freshState() {
        let state = NavigationState()
        #expect(state.selectedTab == .home)
        #expect(state.path(for: .home).isEmpty)
        #expect(state.snapshot.stacks.isEmpty)
    }

    /// Deep linking, in one call: the caller supplies a route and does not choose a tab.
    @Test("navigating to a route selects the owning tab and pushes there", arguments: RouteTests.all)
    func navigateSelectsOwningTab(route: Route) {
        let state = NavigationState()
        state.navigate(to: route)

        #expect(state.selectedTab == route.tab)
        #expect(state.path(for: route.tab) == [route])
        for other in AppTab.allCases where other != route.tab {
            #expect(state.path(for: other).isEmpty)
        }
    }

    /// Depth accumulates on the owning tab, and a push from a different tab does not disturb it.
    @Test("pushes stack up, and each tab keeps its own")
    func stacksAreIndependent() {
        let state = NavigationState()
        state.navigate(to: .exerciseLibrary(.exerciseDetail(exerciseID: UUID())))
        state.navigate(to: .training(.activeSession))
        state.navigate(to: .settings(.about))

        #expect(state.path(for: .train).count == 2)
        #expect(state.path(for: .settings).count == 1)
        #expect(state.selectedTab == .settings)
    }

    /// `FR-1.9.4` under `D-8`: the dashboard's primary action goes to Train, at Train's root — not
    /// onto whatever Train was left showing, and not into a logging surface presented from Home.
    @Test("start workout switches to Train and lands on its root")
    func startWorkoutNavigates() {
        let state = NavigationState()
        state.navigate(to: .exerciseLibrary(.exerciseDetail(exerciseID: UUID())))
        state.selectedTab = .home

        state.startWorkout()

        #expect(state.selectedTab == .train)
        #expect(state.path(for: .train).isEmpty)
    }

    /// The snapshot has to describe the *current* position, not the one the state was built with —
    /// it is read after every navigation.
    @Test("the snapshot follows the state, and restoring it reproduces tab and depth")
    func snapshotRoundTripsThroughState() {
        let state = NavigationState()
        state.navigate(to: .history(.session(sessionID: UUID())))
        state.navigate(to: .exerciseLibrary(.exerciseDetail(exerciseID: UUID())))

        let restored = NavigationState(snapshot: state.snapshot)
        #expect(restored.selectedTab == .train)
        #expect(restored.path(for: .train).count == 1)
        #expect(restored.path(for: .history).count == 1)
        #expect(restored.path(for: .home).isEmpty)
    }

    /// The binding is what a `NavigationStack` writes back through when the user taps Back, so its
    /// setter is the only way a stack ever shrinks.
    @Test("the tab's binding reads and writes that tab's stack")
    func bindingReadsAndWrites() {
        let state = NavigationState()
        let binding = state.binding(for: .history)
        let route = Route.history(.session(sessionID: UUID()))

        binding.wrappedValue = [route]
        #expect(state.path(for: .history) == [route])
        #expect(state.path(for: .train).isEmpty)

        binding.wrappedValue = []
        #expect(state.path(for: .history).isEmpty)
        #expect(state.snapshot.stacks[.history] == nil)
    }

    /// Popping is a discard, not a decrement: it drops the stack rather than one entry.
    @Test("popping to root clears that tab alone")
    func popToRoot() {
        let state = NavigationState()
        state.navigate(to: .training(.activeSession))
        state.navigate(to: .settings(.about))

        state.popToRoot(.train)

        #expect(state.path(for: .train).isEmpty)
        #expect(state.path(for: .settings).count == 1)
    }
}
