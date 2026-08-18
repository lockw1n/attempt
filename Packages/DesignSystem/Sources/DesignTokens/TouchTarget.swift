import CoreGraphics

/// The minimum tappable extent of a control (`G-4.3`).
///
/// A token rather than a literal for the same reason spacing is one: `G-7.7`'s lint rules ban a
/// numeric `minHeight:`, so 44 cannot be written at a call site even if someone wanted to. The
/// scale is the only place the two figures exist.
///
/// **This is a floor, not a size.** A control whose content is already taller keeps its own height;
/// the token guarantees that one whose content is smaller still reaches the target.
public enum TouchTarget: Sendable, CaseIterable, Comparable {
    /// 44pt — the platform minimum, and the floor for every control in the app (`G-4.3`).
    case standard

    /// 60pt — the floor for a logging control, which is operated one-handed mid-set with the
    /// phone at arm's length (`G-4.3`). Not a preference: the number is the requirement's.
    case logging

    /// The target's extent in points, applied to both dimensions.
    public var points: CGFloat {
        switch self {
        case .standard: 44
        case .logging: 60
        }
    }
}
