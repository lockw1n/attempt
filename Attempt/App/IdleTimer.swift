import SwiftUI
import UIKit

extension View {
    /// Holds the screen awake while `isEnabled` (`NFR-1.9`).
    ///
    /// **The mechanism, not the policy.** Whether the screen should be awake is a workout in
    /// progress and a preference, and both of those are `Logging`'s; what is here is the one UIKit
    /// call that acts on the answer. It lives in the app target because a feature module reaches no
    /// Apple framework beyond SwiftUI, and because the idle timer is the application's — one flag,
    /// not one per screen.
    ///
    /// - Parameter isEnabled: Whether to hold the timer off.
    /// - Returns: The view, with the timer following `isEnabled`.
    func keepScreenAwake(_ isEnabled: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(isEnabled: isEnabled))
    }
}

/// Applies ``SwiftUI/View/keepScreenAwake(_:)``.
///
/// Three hooks rather than one, because the flag is global state and this view is not the only thing
/// that could have set it: `onAppear` claims it, `onChange` follows the answer, and `onDisappear`
/// gives it back. The last is what stops a screen that went away with the timer off from keeping the
/// device awake for the rest of the launch.
private struct KeepScreenAwakeModifier: ViewModifier {
    /// Whether the timer is held off.
    let isEnabled: Bool

    /// The content, with the timer bound to ``isEnabled``.
    func body(content: Content) -> some View {
        content
            .onAppear { apply(isEnabled) }
            .onChange(of: isEnabled) { _, enabled in apply(enabled) }
            .onDisappear { apply(false) }
    }

    /// Sets the flag.
    private func apply(_ isEnabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = isEnabled
    }
}
