import DesignTokens
import SwiftUI

/// How far a surface sits above the one behind it (`G-7.1`).
///
/// **Elevation is a lighter surface, never a shadow.** The palette encodes the whole progression —
/// background → ``ColorToken/surface`` → ``ColorToken/surfaceRaised`` — so a card and a control
/// inside it are told apart by their own colour rather than by a drop shadow that would have to
/// change with the appearance.
///
/// Each level also carries its own radius, and the pairing is the point: an inner surface takes the
/// smaller curve so the two stay concentric (see ``CornerRadius``).
public nonisolated enum CardElevation: Sendable, CaseIterable {
    /// A card or grouped section resting directly on the screen's background.
    case base

    /// A surface drawn inside another — a control within a card, a selected row.
    case raised

    /// The surface colour this level draws.
    public var surface: ColorToken {
        switch self {
        case .base: .surface
        case .raised: .surfaceRaised
        }
    }

    /// The corner radius this level takes. Smaller as the nesting gets deeper.
    public var cornerRadius: CornerRadius {
        switch self {
        case .base: .card
        case .raised: .control
        }
    }
}

/// A padded, rounded surface — the container every grouped block of content sits in (`G-7.1`).
///
/// **The card imposes no layout on its content.** It is padding, a surface colour and a corner
/// radius, and nothing else; a caller that wants its children stacked writes the stack. That is
/// what keeps `Card` composable with the tile, the button and whatever a feature screen invents,
/// rather than becoming the union of everything anyone ever wanted inside one.
///
/// It does claim the full available width, because a row of cards with ragged right edges is not a
/// layout any screen in this app wants.
public struct Card<Content: View>: View {
    private let elevation: CardElevation
    private let content: Content

    /// Wraps `content` in a surface at `elevation`.
    ///
    /// - Parameters:
    ///   - elevation: Which surface to draw. Defaults to ``CardElevation/base``, the card on the
    ///     background; pass ``CardElevation/raised`` only when this card is inside another.
    ///   - content: The card's content, laid out by the caller.
    public init(elevation: CardElevation = .base, @ViewBuilder content: () -> Content) {
        self.elevation = elevation
        self.content = content()
    }

    /// The surface itself: the caller's content, the card's inset, then this elevation's fill
    /// and curve.
    public var body: some View {
        content
            .padding(Spacing.lg.points)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(elevation.surface, in: .rect(cornerRadius: elevation.cornerRadius.points))
    }
}
