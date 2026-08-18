import CoreGraphics

/// The spacing scale every layout value in the app comes from (`G-7.7`).
///
/// A closed set rather than a `CGFloat`, because `G-7.7` is enforceable only if the tokens are the
/// only representation a feature module can reach for: a lint rule can ban `.padding(12)`, but
/// nothing can ban a `CGFloat` constant declared in a feature and named `cardPadding`.
///
/// The steps are a 4-point grid, with one sub-grid step (``xxs``) for hairline insets. Ordered
/// smallest to largest, and `Comparable` on that order — `.sm < .lg`.
///
/// **Spacing does not scale with Dynamic Type.** Text grows, the gaps between it do not; a layout
/// whose gutters grew with the body font would lose more line width than it gained legibility.
/// ``Typography`` is the part of the design system that responds to the user's size setting.
public enum Spacing: Sendable, CaseIterable, Comparable {
    /// 2pt — a hairline inset, for separating a glyph from the text it annotates. Nothing larger
    /// than an icon should use it.
    case xxs

    /// 4pt — between a label and the value directly under it, inside one component.
    case xs

    /// 8pt — the default gap between sibling elements of a component (label to numeral).
    case sm

    /// 12pt — between components inside a card, and the card's own inner padding at its tightest.
    case md

    /// 16pt — a card's standard inner padding, and the screen's horizontal margin.
    case lg

    /// 24pt — between cards in a scrolling list.
    case xl

    /// 32pt — between grouped sections of a screen, where the gap itself signals a topic change.
    case xxl

    /// The step's size in points. Always positive; the scale carries no zero, since "no gap" is
    /// the absence of a spacing token rather than a value in the scale.
    public var points: CGFloat {
        switch self {
        case .xxs: 2
        case .xs: 4
        case .sm: 8
        case .md: 12
        case .lg: 16
        case .xl: 24
        case .xxl: 32
        }
    }
}
