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
/// **The touch target is a parameter, and this style is where `G-4.3`'s second figure lives.** The
/// requirement asks 44pt of every control and 60pt of a *logging* one, and after `FR-16.6.4` every
/// command on the session card is drawn here — so a style that floored at 44 would put the whole of
/// `NFR-1.3`'s three taps under the smaller number. It defaults to ``DesignTokens/TouchTarget/standard``
/// because most callers are not logging controls; a caller inside the workout passes
/// ``DesignTokens/TouchTarget/logging``.
///
/// Pressed and disabled fade, as the primary does — the same function decides, so the two cannot
/// drift apart.
public struct SecondaryActionButtonStyle: ButtonStyle {
    let width: PrimaryActionWidth
    let touch: TouchTarget

    /// Creates the style. Prefer `.buttonStyle(.secondaryAction)`.
    ///
    /// - Parameters:
    ///   - width: How much of the available width the button claims.
    ///   - touch: The extent it is guaranteed at least (`G-4.3`).
    public init(width: PrimaryActionWidth = .intrinsic, touch: TouchTarget = .standard) {
        self.width = width
        self.touch = touch
    }

    /// Draws the unfilled action. A private `View` for ``PrimaryActionButtonStyle``'s reason: a
    /// `ButtonStyle` is not a `View`, so an `@Environment` property on it never updates.
    public func makeBody(configuration: Configuration) -> some View {
        SecondaryActionButton(configuration: configuration, width: width, touch: touch)
    }
}

extension ButtonStyle where Self == SecondaryActionButtonStyle {
    /// The app's secondary action at its intrinsic width — `.buttonStyle(.secondaryAction)`.
    public static var secondaryAction: Self { SecondaryActionButtonStyle() }

    /// The app's secondary action at a chosen width — `.buttonStyle(.secondaryAction(.fill))`.
    ///
    /// - Parameters:
    ///   - width: How much of the available width the button claims.
    ///   - touch: The extent it is guaranteed at least (`G-4.3`). A command inside a workout passes
    ///     ``DesignTokens/TouchTarget/logging``.
    /// - Returns: The style.
    public static func secondaryAction(
        _ width: PrimaryActionWidth, touch: TouchTarget = .standard
    ) -> Self {
        SecondaryActionButtonStyle(width: width, touch: touch)
    }
}

private struct SecondaryActionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ButtonStyleConfiguration
    let width: PrimaryActionWidth
    let touch: TouchTarget

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
                minWidth: touch.points,
                maxWidth: width.maxWidth,
                minHeight: touch.points
            )
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .opacity(opacity.value)
    }
}
