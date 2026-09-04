import DesignTokens
import SwiftUI

/// The unfilled companion to the primary action: the same shape, the same extent, on a raised
/// surface instead of the brand accent (`G-7.2`, `FR-16.6.4`).
///
/// **It exists so that "one filled button per screen" is affordable.** `G-7.2` gives the app one
/// accent, and a screen that needs three logging commands next to a **Finish** cannot spend it four
/// times — so the other three are drawn at the same size and the same weight as each other, and the
/// accent says which one ends the workout. Without a style for that, every screen hand-rolls its
/// own rectangle: `Add set` and `Add exercise` each did, at two different surface tokens, on one
/// screen.
///
/// **A raised surface, which is where a control inside a card belongs** (``CardElevation/raised``).
/// A card is ``DesignTokens/ColorToken/surface``, so a button drawn at that token on one is the
/// card's own colour with a label floating on it.
///
/// **Width is a parameter for ``PrimaryActionButtonStyle``'s reason**, and it is that type's
/// parameter: a secondary action is the same control with a different fill, so the two share one
/// width vocabulary rather than owning two spellings of `intrinsic` and `fill`.
///
/// Pressed and disabled fade, as the primary does — the same function decides, so the two cannot
/// drift apart.
public struct SecondaryActionButtonStyle: ButtonStyle {
    let width: PrimaryActionWidth

    /// Creates the style. Prefer `.buttonStyle(.secondaryAction)`.
    ///
    /// - Parameter width: How much of the available width the button claims.
    public init(width: PrimaryActionWidth = .intrinsic) {
        self.width = width
    }

    /// Draws the unfilled action. A private `View` for ``PrimaryActionButtonStyle``'s reason: a
    /// `ButtonStyle` is not a `View`, so an `@Environment` property on it never updates.
    public func makeBody(configuration: Configuration) -> some View {
        SecondaryActionButton(configuration: configuration, width: width)
    }
}

extension ButtonStyle where Self == SecondaryActionButtonStyle {
    /// The app's secondary action at its intrinsic width — `.buttonStyle(.secondaryAction)`.
    public static var secondaryAction: Self { SecondaryActionButtonStyle() }

    /// The app's secondary action at a chosen width — `.buttonStyle(.secondaryAction(.fill))`.
    ///
    /// - Parameter width: How much of the available width the button claims.
    public static func secondaryAction(_ width: PrimaryActionWidth) -> Self {
        SecondaryActionButtonStyle(width: width)
    }
}

private struct SecondaryActionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let width: PrimaryActionWidth

    private var opacity: Opacity {
        PrimaryActionButtonStyle.opacity(isEnabled: isEnabled, isPressed: configuration.isPressed)
    }

    var body: some View {
        configuration.label
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.textPrimary)
            .padding(.horizontal, Spacing.lg.points)
            .padding(.vertical, Spacing.md.points)
            .frame(
                minWidth: TouchTarget.standard.points,
                maxWidth: width.maxWidth,
                minHeight: TouchTarget.standard.points
            )
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .opacity(opacity.value)
    }
}
