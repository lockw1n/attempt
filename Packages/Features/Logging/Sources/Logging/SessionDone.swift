import AppNavigation
import Localization
import SwiftUI

/// Leaving a screen whose writes have all already happened (`FR-18.4.1`, `FR-18.4.3`).
///
/// **Done is not a Finish and is never to become one** (`D-17.6`): it calls no store, starts and
/// ends nothing, answers nothing, and asks nothing — not even with rows unanswered. Every answer
/// was written the moment it was given; this button only names the exit the tester could not find
/// (`F-06`).
///
/// **The glyph is a checkmark and that does not make it a confirmation** (`FR-18.4.7`). A ✓ over a
/// list of circles is a stronger *confirm* than the word was, which is exactly the temptation: the
/// rule above is unchanged, and nothing here may grow a write.
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
    /// `FR-18.4.1`'s exit, in the trailing corner, on a screen that saves as it goes.
    ///
    /// **The label is the host's and has no default**, because this module writes a screen's copy
    /// once per screen rather than once per phrase — see ``LoggingStrings``. The two hosts say the
    /// same word today and are free to diverge.
    ///
    /// **A checkmark, and the role and the glyph are two separate halves of it** (`FR-18.4.7`).
    /// `ButtonRole.confirm` is what makes it the platform's confirm action — on iOS 26.5 that is
    /// the prominent accent capsule this draws in. It is *not* what makes it a checkmark:
    /// measured twice on 26.5, in `.primaryAction` on a pushed screen, both `Button(role:)` with
    /// a `Text` label and the plain-title initializer drew the **word** in that capsule. So the
    /// glyph is named here. The label is still the word, which is what VoiceOver reads and what
    /// every hosted test finds the exit by (`G-4.2`).
    ///
    /// **Attach this *before* `sessionOverflow(contents:changeDate:commands:)`**, on a host that
    /// has both, and that is the opposite of how it reads. Measured on iOS 26.5: a placement's
    /// items are drawn in the order their modifiers were applied **from the outside in**, so the
    /// modifier written *second* contributes the *leftmost* item. `FR-18.4.8` wants the `⋯` left
    /// of the exit, so the menu's modifier goes last — and the spacer this one contributes then
    /// falls between the two rather than outside them. Both hosts are gated on the resulting
    /// frames (`AttemptTests.DoneButtonTests`, `AttemptTests.PastSessionMenuTests`); nothing
    /// about the order is readable from either call site.
    ///
    /// - Parameter label: What the button is named, and what it reads where the platform draws a
    ///   word.
    /// - Returns: The screen, with its exit on it.
    func sessionDone(label: LocalizedStringResource) -> some View {
        modifier(SessionDoneModifier(label: label))
    }
}

/// See `sessionDone(label:)`.
struct SessionDoneModifier: ViewModifier {
    /// What the button is named.
    let label: LocalizedStringResource

    /// The shell's navigation position, which is what the exit pops.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// The way out where there is no shell — a preview or a hosted fixture.
    @Environment(\.dismiss) private var dismiss

    /// `G-4.3`'s 44 pt floor, imposed on the glyph's **width** because the glyph does not reach
    /// it on its own.
    ///
    /// Measured on iOS 26.5, pushed: the bare checkmark laid the item out **28 pt** wide, where
    /// the word it replaced was 64 — the narrower label is what spent it. With this the item is
    /// 48 pt, the capsule's own padding carrying it past the floor.
    ///
    /// **The height is the bar's and this does not reach it.** Every SwiftUI item on this bar
    /// lays out 36 pt tall — the `⋯` beside it as well, since before the exit was a glyph — and
    /// a `minHeight` here is silently ignored, so there is no `minHeight` here to read as
    /// working. Only Back, which is UIKit's, is 44 × 44. `G-4.3`'s square is therefore not
    /// reachable from a toolbar item, and what is held below is the width alone.
    private static let touchTarget: CGFloat = 44

    func body(content: Content) -> some View {
        content
            .toolbar {
                // `FR-18.4.8`'s "two controls, not one", declared rather than relied on. iOS 26
                // fuses adjacent items into one glass group per toolbar *builder*, and the `⋯`
                // comes from another modifier — so measured on 26.5 this changes neither frame
                // nor the 20 pt between them, and removing it changed nothing on screen either.
                // Kept as the intent `Q-AJ` chose and as the guard for the day the two items land
                // in one builder; nothing gates it, so do not read it as what holds the gap.
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    // The system's confirm action (`FR-18.4.7`): a capsule tinted with the app's
                    // accent — the screen's own accent and not a second one (`FR-16.6.4`) — and
                    // the checkmark it holds. It confirms nothing: see ``SessionExit``.
                    Button(role: .confirm) {
                        if !SessionExit.leave(navigation) { dismiss() }
                    } label: {
                        // An `Image` with the word hung on it, and **not** a `Label` under
                        // `.labelStyle(.iconOnly)`, which is the spelling that reads better and
                        // was measured worse: on iOS 26.5 the icon-only label backs this item
                        // with a `_UIButtonBarButton` whose `accessibilityActivate()` returns
                        // **false** — VoiceOver's own gesture — while this one backs it with an
                        // `AccessibilityNode` that answers. Either way the name is the word
                        // (`FR-18.4.7`, `G-4.2`); only one of them can be pressed without sight.
                        Image(systemName: "checkmark")
                            .frame(minWidth: Self.touchTarget)
                            .accessibilityLabel(Text(label))
                    }
                }
            }
    }
}
