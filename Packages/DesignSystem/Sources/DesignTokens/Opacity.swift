import CoreGraphics

/// The opacity scale for interaction state (`G-7.7`).
///
/// Pressed and disabled are the two states the palette does *not* express: adding a token colour
/// for each would double the colour vocabulary to say something that is the same statement about
/// every colour. Fading is that statement, and this is the scale it comes from.
///
/// **Disabled is not an accessibility affordance.** A faded control fails `G-4.4`'s contrast floor
/// by construction, which is why nothing disabled may be the only carrier of information — the
/// same rule `G-4.5` states for colour.
public enum Opacity: Sendable, CaseIterable, Comparable {
    /// 0.4 — a control the user cannot currently operate.
    case disabled

    /// 0.75 — a control under the user's finger, for the duration of the press.
    case pressed

    /// 1.0 — the resting state, named so a conditional never has to write the bare literal.
    case opaque

    /// The multiplier applied to the drawn colour, in `0...1`.
    public var value: Double {
        switch self {
        case .disabled: 0.4
        case .pressed: 0.75
        case .opaque: 1
        }
    }
}
