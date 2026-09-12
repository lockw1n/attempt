import Logging

/// Whether the idle timer is held off right now (`NFR-1.9`).
///
/// **A type of its own for one expression, because that expression is the defect.** `NFR-1.9` has
/// two halves and each is tested where it lives — ``Logging/ScreenWakePreference`` owns the toggle,
/// ``Logging/ActiveSessionStore`` owns whether a workout is in progress — and *which reading of the
/// store the shell passes to the preference* belongs to neither. That is what `T-1.84` measured
/// wrong on a phone: a planned day that has ended keeps its row held so the checklist can draw it,
/// so ``Logging/ActiveSessionStore/isActive`` stays `true` long after the lifter stopped lifting,
/// and the screen never dimmed on any tab until the app was backgrounded.
///
/// Left on ``RootTabView`` it was reachable from no test at all: the view needs `AppNavigation`,
/// which the app's test bundle does not link, and adding that link is an Xcode project change.
/// Here the production expression is the tested one, and `AttemptTests/ScreenWakePolicyTests` is
/// what fails when the word goes back.
enum ScreenWakePolicy {
    /// Whether the screen should be held awake for `state`.
    ///
    /// A store that did not open keeps no workout, so it never holds the timer off.
    ///
    /// - Parameter state: What ``AppDependencies`` currently holds.
    /// - Returns: `true` while a workout is in progress and the preference is on.
    static func keepsScreenAwake(in state: AppDependencies.State) -> Bool {
        guard case .open(_, let stores) = state else { return false }
        return stores.screenWake.keepsScreenAwake(duringSession: stores.activeSession.isInProgress)
    }
}
