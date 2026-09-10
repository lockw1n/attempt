import SwiftUI
import UIKit

/// A SwiftUI view hosted in a real window, on a real `UIWindowScene` (`TR-1.12`).
///
/// **This is the whole reason the bundle is hosted rather than a package suite.** A bare SwiftPM
/// test bundle has no scene, so `UIHostingController` there builds no `UIView` hierarchy and no
/// accessibility tree — measured by T-1.08, which is why two of T-1.09's surviving
/// accessibility-modifier mutations were left to `T-1.82` rather than closed by the snapshot
/// harness. Here the app under test has already launched, so a scene exists and a window put on it
/// lays out, draws, and presents.
///
/// What that buys is the class of defect a snapshot cannot see: a **modifier attached to the screen
/// rather than to one of its parts**. A reference pictures what a subtree renders, and every
/// existing gate agreed with itself when `.sheet(item:)` and `.onChange` were deleted from
/// `ActiveSessionView` — the parts still rendered, so nothing was pictured differently. A
/// presentation is not part of any subtree's picture; it is only observable from a host.
///
/// **It does not walk a route and it does not tap.** Activation here goes through the accessibility
/// element, which is what VoiceOver's double-tap does — not through a synthesised touch, so nothing
/// here is evidence about hit areas, gesture precedence, or a control covered by something drawn
/// over it. That needs a UI test or a finger.
@MainActor
final class HostedScreen {
    /// The controller the view is hosted in — what a presentation is presented *from*.
    let controller: UIViewController

    /// The window it is on. Held so it can be taken down again; a window left key outlives the test.
    private let window: UIWindow

    /// Puts `content` on a window on the app's own scene.
    ///
    /// - Parameter content: The screen under test.
    init(_ content: some View) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        // A hosted bundle always has one, and a fixture that silently fell back to a scene-less
        // window would report exactly the emptiness this type exists to rule out.
        guard let scene else {
            preconditionFailure(
                "no UIWindowScene: this bundle must be hosted by the app, not run standalone")
        }
        let controller = UIHostingController(rootView: content)
        self.controller = controller
        window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    /// Takes the window down.
    ///
    /// **Explicit rather than a `deinit`**, because a `deinit` on a main-actor type cannot touch
    /// main-actor state under Swift 6 — and a window left key changes what the *next* test's
    /// `connectedScenes` lookup returns.
    func dismantle() {
        controller.dismiss(animated: false)
        window.rootViewController = nil
        window.isHidden = true
    }

    /// Lets SwiftUI's pending work run — layout, an `async` `.task`, a presentation.
    ///
    /// **A yield is not enough and neither is one sleep.** A `.task` that awaits a repository, the
    /// layout pass that its result triggers, and the presentation raised from a button inside that
    /// layout are three separate turns of the main run loop, and a fixture that waited once
    /// reported the state before the last of them as if it were the answer.
    ///
    /// - Parameter turns: How many turns to allow. Four is what the screens here need.
    func settle(turns: Int = 4) async {
        for _ in 0..<turns {
            try? await Task.sleep(for: .milliseconds(60))
            window.layoutIfNeeded()
        }
    }

    /// The hosted view hierarchy, for a failure message.
    ///
    /// - Returns: One line per view, indented by depth.
    func describeHierarchy() -> String {
        guard let root = controller.viewIfLoaded else { return "<no view loaded>" }
        var lines: [String] = []
        func walk(_ view: UIView, _ depth: Int) {
            let traits = view.accessibilityTraits.rawValue
            lines.append(
                String(repeating: "  ", count: depth)
                    + "\(type(of: view)) frame=\(view.frame) "
                    + "isElement=\(view.isAccessibilityElement) "
                    + "elements=\(view.accessibilityElements?.count ?? -1) "
                    + "label=\(view.accessibilityLabel ?? "-") traits=\(traits)")
            for subview in view.subviews { walk(subview, depth + 1) }
        }
        walk(root, 0)
        return lines.joined(separator: "\n")
    }

    /// Why a hosted view can publish nothing, and what to do about it.
    ///
    /// **This is a property of the destination, not of the screen.** SwiftUI builds accessibility
    /// elements lazily and only while an accessibility client is active: with none, `_UIHostingView`
    /// lays out at the right size, draws, and answers `accessibilityElements` with an **empty
    /// array** rather than `nil` — so a walk that trusted it reports a screen with no controls on
    /// it, which is indistinguishable from a screen whose controls were deleted. Measured on
    /// 2026-09-10; it is the one thing that stands between a hosted bundle and `T-1.82`'s two
    /// surviving accessibility-modifier mutations.
    static let accessibilityRemedy = """
        the hosted view published no accessibility elements at all. That is the destination, not \
        the screen: SwiftUI builds them only while an accessibility client is active. Run this \
        suite through scripts/app-tests.sh, which sets ApplicationAccessibilityEnabled on the \
        simulator first — a bare `xcodebuild test` does not, and a device needs Accessibility \
        turned on in Settings.
        """

    /// What is presented over the screen, or `nil`.
    var presented: UIViewController? { controller.presentedViewController }

    /// Every accessibility element the hosted view publishes, flattened.
    ///
    /// - Returns: The elements, in the order the tree yields them.
    func accessibilityElements() -> [NSObject] {
        guard let root = controller.viewIfLoaded else { return [] }
        var found: [NSObject] = []
        Self.collect(from: root, into: &found)
        return found
    }

    /// The labels of every element that answers to activation.
    ///
    /// - Returns: The labels, deduplicated in first-seen order.
    func activatableLabels() -> [String] {
        var seen: Set<String> = []
        return accessibilityElements()
            .filter { $0.accessibilityTraits.contains(.button) }
            .compactMap(\.accessibilityLabel)
            .filter { seen.insert($0).inserted }
    }

    /// Activates the first element labelled `label`, the way VoiceOver's double-tap does.
    ///
    /// - Parameter label: The element's accessibility label.
    /// - Returns: Whether an element with that label was found and answered.
    @discardableResult
    func activate(label: String) -> Bool {
        guard
            let element = accessibilityElements().first(where: {
                $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button)
            })
        else { return false }
        return element.accessibilityActivate()
    }

    /// Walks one node of the accessibility tree.
    ///
    /// **`accessibilityElements` wins over `subviews` where a view publishes both**, which is what
    /// SwiftUI's backing views do: the published list is the tree VoiceOver reads, and the subviews
    /// under it are drawing scaffolding whose own labels are not what anyone hears.
    ///
    /// - Parameters:
    ///   - node: The view or element to walk.
    ///   - found: Where to put what is published.
    private static func collect(from node: NSObject, into found: inout [NSObject]) {
        if node.isAccessibilityElement {
            found.append(node)
        }
        if let published = node.accessibilityElements {
            for child in published {
                guard let child = child as? NSObject else { continue }
                collect(from: child, into: &found)
            }
            return
        }
        guard let view = node as? UIView else { return }
        for subview in view.subviews {
            collect(from: subview, into: &found)
        }
    }
}
