import DesignTokens
import SwiftUI

/// The filled primary action: the single brand accent, on a control-radius surface (`G-7.2`).
///
/// One per screen, or none. `G-7.2` gives the app one accent, so a screen with two filled buttons
/// has two primary actions and no primary action.
///
/// **Width is a parameter, not something the caller can add from outside.** A `ButtonStyle` sizes
/// its own background to the label, so `.buttonStyle(.primaryAction).frame(maxWidth: .infinity)`
/// widens the button's *slot* and leaves the filled shape hugging the text, centred in it — the
/// first thing this style was run against in the simulator, and it looked exactly like a bug in the
/// caller. The width has to be chosen inside the style, so it is: `.primaryAction` for intrinsic,
/// `.primaryAction(.fill)` for a full-width call to action. Both keep `G-4.3`'s minimum extent.
///
/// Pressed and disabled are drawn by fading (``DesignTokens/Opacity``) rather than by a second pair of colours —
/// see that type for why. A disabled control is therefore below `G-4.4`'s contrast floor and must
/// never be the only thing telling the user why an action is unavailable.
public struct PrimaryActionButtonStyle: ButtonStyle {
    let width: PrimaryActionWidth

    /// Creates the style. Prefer `.buttonStyle(.primaryAction)`.
    ///
    /// - Parameter width: How much of the available width the button claims.
    public init(width: PrimaryActionWidth = .intrinsic) {
        self.width = width
    }

    /// The fade this control draws at, from the two interaction inputs (``DesignTokens/Opacity``).
    ///
    /// A `static func` rather than a computed property on the private body view, because that view
    /// is unreachable from a test: swapping ``DesignTokens/Opacity/disabled`` for
    /// ``DesignTokens/Opacity/pressed`` inside it once survived the entire suite. Disabled outranks
    /// pressed — a control the user cannot operate does not brighten because a finger landed on it.
    static func opacity(isEnabled: Bool, isPressed: Bool) -> Opacity {
        guard isEnabled else { return .disabled }
        return isPressed ? .pressed : .opaque
    }

    /// Draws the filled action. The body is a private `View` rather than modifiers applied here,
    /// so it can read the enabled state out of the environment.
    public func makeBody(configuration: Configuration) -> some View {
        // The enabled state has to be read inside a View: a ButtonStyle is not one, so an
        // @Environment property declared on the style itself never updates.
        PrimaryActionButton(configuration: configuration, width: width)
    }
}

/// How much of the available width a primary action claims.
public nonisolated enum PrimaryActionWidth: Sendable, CaseIterable {
    /// As wide as its label needs, and no wider — a button in a row of controls.
    case intrinsic

    /// The full width offered by the container — a call to action at the foot of a screen.
    case fill

    /// The `maxWidth` this choice imposes. `nil` leaves the frame's own sizing alone, which is what
    /// makes ``intrinsic`` genuinely intrinsic rather than a very large number.
    var maxWidth: CGFloat? {
        switch self {
        case .intrinsic: nil
        case .fill: .infinity
        }
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    /// The app's primary action style at its intrinsic width — `.buttonStyle(.primaryAction)`.
    public static var primaryAction: Self { PrimaryActionButtonStyle() }

    /// The app's primary action style at a chosen width — `.buttonStyle(.primaryAction(.fill))`.
    ///
    /// - Parameter width: How much of the available width the button claims.
    public static func primaryAction(_ width: PrimaryActionWidth) -> Self {
        PrimaryActionButtonStyle(width: width)
    }
}

private struct PrimaryActionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let width: PrimaryActionWidth

    private var opacity: Opacity {
        PrimaryActionButtonStyle.opacity(isEnabled: isEnabled, isPressed: configuration.isPressed)
    }

    var body: some View {
        configuration.label
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.onBrandAccent)
            .padding(.horizontal, Spacing.lg.points)
            .padding(.vertical, Spacing.md.points)
            .frame(
                minWidth: TouchTarget.standard.points,
                maxWidth: width.maxWidth,
                minHeight: TouchTarget.standard.points
            )
            .background(ColorToken.brandAccent, in: .rect(cornerRadius: CornerRadius.control.points))
            .opacity(opacity.value)
    }
}
