import AppNavigation
import Localization
import SwiftUI

/// Leaving a screen whose writes have all already happened (`FR-18.4.1`, `FR-18.4.3`).
///
/// **Done is not a Finish and is never to become one** (`D-17.6`): it calls no store, starts and
/// ends nothing, answers nothing, and asks nothing — not even with rows unanswered. Every answer
/// was written the moment it was given; this button only names the exit the tester could not find
/// (`F-06`).
enum SessionExit {
    /// Takes the screen off the stack it was pushed onto.
    ///
    /// **``AppNavigation/NavigationState/pop(_:)`` rather than `dismiss()`**, for that method's
    /// measured reason: a screen with a sheet of its own up is not the topmost thing on the
    /// display, and dismissing from it would take the sheet down and leave the screen. Removing
    /// the route takes both.
    ///
    /// - Parameter navigation: The shell's position, or `nil` where there is no shell — a preview,
    ///   a snapshot, or a hosted fixture.
    /// - Returns: `false` where nothing was popped, so the caller can fall back to `dismiss()`.
    static func leave(_ navigation: NavigationState?) -> Bool {
        guard let navigation else { return false }
        return navigation.pop(navigation.selectedTab)
    }
}

extension View {
    /// `FR-18.4.1`'s **Done**, in the trailing corner, on a screen that saves as it goes.
    ///
    /// **The label is the host's and has no default**, because this module writes a screen's copy
    /// once per screen rather than once per phrase — see ``LoggingStrings``. The two hosts say the
    /// same word today and are free to diverge.
    ///
    /// - Parameter label: What the button reads.
    /// - Returns: The screen, with Done on it.
    func sessionDone(label: LocalizedStringResource) -> some View {
        modifier(SessionDoneModifier(label: label))
    }
}

/// See `sessionDone(label:)`.
struct SessionDoneModifier: ViewModifier {
    /// What the button reads.
    let label: LocalizedStringResource

    /// The shell's navigation position, which is what Done pops.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// The way out where there is no shell — a preview or a hosted fixture.
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: SessionToolbarSide.trailing.placement) {
                    // Plain text, not a filled accent: the day spends none (`FR-16.6.4`).
                    Button {
                        if !SessionExit.leave(navigation) { dismiss() }
                    } label: {
                        Text(label)
                    }
                }
            }
    }
}
