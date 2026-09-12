import DesignSystem
import SwiftUI
import Testing
import UIKit

@testable import Attempt

/// What VoiceOver reads, asserted from a hosted view (`G-4.2`, `T-1.82`).
///
/// **These are T-1.08's two surviving mutations, and this is the first bundle that can hold them.**
/// T-1.09 left three accessibility-modifier mutations alive; the snapshot harness could not close
/// two of them because `ImageRenderer` draws a bitmap in a bundle with no `UIWindowScene`, so no
/// accessibility tree exists to walk. Those two are `.accessibilityHidden(true)` on the state
/// scaffold's glyph and `.accessibilityElement(children: .combine)` on its headline and message —
/// both questions about what is *published*, which is exactly what a bitmap cannot answer and a
/// hosted view can.
///
/// **Run through `scripts/app-tests.sh`, never a bare `xcodebuild test`.** Every claim here reads
/// the accessibility tree, and SwiftUI builds that tree only while an accessibility client is
/// active — so without one a scaffold with every part intact publishes an empty array and reads
/// exactly like one whose parts were deleted. Each test `#require`s a non-empty tree *separately*
/// from its own claim, so a destination fault is never reported as the component's.
///
/// **No fixture here sets its own size.** `HostedScreen` puts the view on a window on the app's own
/// scene, so it already lays out at the device's size — and an explicit `.frame(width:height:)`
/// would be a `no_magic_spacing` violation anyway. That rule reaches this directory **only because
/// the checkout is itself named `Attempt`**: its `included:` pattern is `Attempt/.*\.swift`, which
/// `AttemptTests/…` does not match relatively and the absolute path does. A clone into a
/// differently-named directory would lint this file by a different set of rules.
@MainActor
@Suite("Accessibility audit")
struct AccessibilityAuditTests {
    /// The scaffold reads as **one** element, which is both mutations in a single number.
    ///
    /// Un-hiding the glyph publishes a second element; dropping `.combine` publishes the headline
    /// and the message separately, which is also a second element. One is the only count that
    /// survives both modifiers being present, and neither being present produces it.
    @Test("an empty state publishes exactly one element, glyph excluded")
    func emptyStateIsOneElement() async throws {
        let screen = HostedScreen(
            EmptyStateView(
                symbolName: "tray",
                headline: Text(verbatim: "Nothing logged"),
                message: Text(verbatim: "Your workouts will appear here.")
            )
        )
        defer { screen.dismantle() }
        await screen.settle()

        let elements = screen.accessibilityElements()
        try #require(!elements.isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        #expect(
            elements.count == 1,
            """
            expected one combined element, got \(elements.count): \
            \(elements.map { $0.accessibilityLabel ?? "-" }). More than one means either the glyph \
            is no longer .accessibilityHidden(true) or the headline and message are no longer \
            .accessibilityElement(children: .combine) — T-1.09's two surviving mutations.
            """)
    }

    /// The combined element says both sentences, which is the half of the count `.combine` owns.
    ///
    /// Separate from the count deliberately: a count of one with only the headline in it would be a
    /// scaffold that combined by *dropping* the message, and the number alone cannot tell the two
    /// apart.
    @Test("the combined element carries the headline and the message, in that order")
    func combinedElementCarriesBothSentences() async throws {
        let screen = HostedScreen(
            EmptyStateView(
                symbolName: "tray",
                headline: Text(verbatim: "Nothing logged"),
                message: Text(verbatim: "Your workouts will appear here.")
            )
        )
        defer { screen.dismantle() }
        await screen.settle()

        let elements = screen.accessibilityElements()
        try #require(!elements.isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        let spoken = elements.compactMap(\.accessibilityLabel).joined(separator: " ")
        #expect(spoken.contains("Nothing logged"), "the headline is not spoken: \(spoken)")
        #expect(
            spoken.contains("Your workouts will appear here."),
            "the message is not spoken: \(spoken)")
    }

    /// The glyph is decoration, and decoration that announces itself is noise (`G-4.5`'s sibling).
    ///
    /// Asserted as "nothing published carries the image trait" rather than "no element is labelled
    /// `tray`", because SwiftUI derives a symbol's label from the symbol name only sometimes — a
    /// test keyed to the label would pass on a build where the glyph published an *unlabelled*
    /// element, which is still a stop VoiceOver has to move through.
    @Test("the state glyph publishes nothing at all")
    func stateGlyphIsNotPublished() async throws {
        let screen = HostedScreen(
            EmptyStateView(
                symbolName: "tray",
                headline: Text(verbatim: "Nothing logged"),
                message: Text(verbatim: "Your workouts will appear here.")
            )
        )
        defer { screen.dismantle() }
        await screen.settle()

        let elements = screen.accessibilityElements()
        try #require(!elements.isEmpty, Comment(rawValue: HostedScreen.accessibilityRemedy))

        let images = elements.filter { $0.accessibilityTraits.contains(.image) }
        #expect(
            images.isEmpty,
            "the glyph is published (\(images.count) image element(s)) — .accessibilityHidden(true) is gone")
    }

    /// `FR-17.5.2`'s open question, answered as a measurement rather than left as a reason.
    ///
    /// That row says no test asserts `@FocusState` because "the app target has no test target".
    /// Half of that expired with `T-1.94`; whether a *hosted* view can be asked what holds focus was
    /// never measured. It can: `@FocusState` drives UIKit first-responder status, and a hosted view
    /// is in a real window with a real responder chain, so the field that SwiftUI focused is the
    /// view that answers `isFirstResponder`.
    ///
    /// **A window that is not key has no first responder**, which is why `HostedScreen` calls
    /// `makeKeyAndVisible` and why this would report "nothing focused" from a bundle that did not.
    @Test("a hosted view can be asked what holds keyboard focus")
    func hostedViewAnswersFocus() async throws {
        let screen = HostedScreen(FocusProbe())
        defer { screen.dismantle() }
        await screen.settle(turns: 6)

        let responder = Self.firstResponder(under: try #require(screen.controller.viewIfLoaded))
        #expect(
            responder is UITextField,
            """
            nothing under the hosted view is first responder, so @FocusState is not observable \
            here and T-17.06's evidence stays simulator-only. Found: \
            \(responder.map { String(describing: type(of: $0)) } ?? "nothing")
            """)
    }

    /// The first view in `root`'s subtree that holds first-responder status.
    ///
    /// - Parameter root: Where to start.
    /// - Returns: The responder, or `nil` where nothing under `root` holds focus.
    private static func firstResponder(under root: UIView) -> UIView? {
        if root.isFirstResponder { return root }
        for subview in root.subviews {
            if let found = firstResponder(under: subview) { return found }
        }
        return nil
    }
}

/// A field that asks for focus as soon as it appears — the smallest thing that exercises
/// `@FocusState` end to end.
private struct FocusProbe: View {
    /// Whether the field below holds focus.
    @FocusState private var focused: Bool

    /// Some text for it to hold.
    @State private var text = ""

    /// The field, focused on appear.
    var body: some View {
        TextField(text: $text) { Text(verbatim: "Probe") }
            .focused($focused)
            .onAppear { focused = true }
    }
}
