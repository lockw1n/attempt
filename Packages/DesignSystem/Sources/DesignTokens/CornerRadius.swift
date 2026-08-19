import CoreGraphics

/// The corner-radius scale (`G-7.1`).
///
/// `G-7.1` states a range — 12 to 16 points — rather than a scale, and this is the scale drawn
/// inside it. Two steps, because two is what the range distinguishes at a one-point-per-step
/// resolution and a third would be a difference no one can see.
///
/// The steps are **nesting depths, not sizes**: ``card`` is the radius of a surface sitting on the
/// background, ``control`` the radius of anything drawn *inside* one. An inner radius smaller than
/// its container's is what keeps the two curves concentric rather than the inner one appearing to
/// bulge; that relationship, not the numbers, is the reason the scale has two entries.
///
/// Ordered smallest to largest, and `Comparable` on that order — `.control < .card`.
public enum CornerRadius: Sendable, CaseIterable, Comparable {
    /// 12pt — a control, chip or row inside a card: the inner curve of a nested pair.
    case control

    /// 16pt — a card or grouped section sitting directly on the background.
    case card

    /// The step's radius in points. Always inside `G-7.1`'s 12…16 band, which a test pins: a value
    /// outside it is a new visual language rather than a new token.
    public var points: CGFloat {
        switch self {
        case .control: 12
        case .card: 16
        }
    }
}
