import SwiftUI

/// The colour vocabulary (`G-7.1`, `G-7.2`, `G-7.3`, `G-7.4`). Every colour the app draws is one of
/// these, named for what it is for rather than what it looks like.
///
/// The palette is **dark-first**: the dark value of each token is the designed one and the light
/// value is its counterpart, chosen to hold the same contrast (see ``ThemedColor``).
///
/// Three rules the names encode, and a reviewer should hold this type to:
///
/// - **One accent.** ``brandAccent`` is the only non-semantic colour in the set (`G-7.2`). A second
///   decorative hue does not belong here; it belongs in the argument about why it is needed.
/// - **Semantic colour is reserved** (`G-7.3`). ``positive`` and ``negative`` mean a delta's
///   direction, or a set made and a set missed. They are never a stylistic choice, and `G-4.5`
///   requires a non-colour cue beside them anyway.
/// - **Elevation is a surface, not a shadow.** ``background`` → ``surface`` → ``surfaceRaised`` is
///   the near-black to card-to-raised-card progression `G-7.1` describes.
///
/// Conforms to `ShapeStyle`: `.foregroundStyle(ColorToken.textSecondary)`.
public enum ColorToken: Sendable, CaseIterable, ShapeStyle {
    /// The near-black behind everything (`G-7.1`). Nothing else may be a screen's backdrop.
    case background

    /// A card or grouped section sitting on ``background``.
    case surface

    /// A surface raised above ``surface`` — a control inside a card, a selected row.
    case surfaceRaised

    /// Hairline rules between rows and sections. Not a text colour: it is well below `G-4.4`'s
    /// contrast floor, deliberately, because a separator that reads as strongly as text is noise.
    case separator

    /// Primary text and the metric numeral itself.
    case textPrimary

    /// Supporting text: labels, context lines, and anything subordinate to a numeral.
    case textSecondary

    /// The faintest text still meant to be read — placeholders, disabled labels, timestamps.
    case textTertiary

    /// The single brand accent, orange (`G-7.2`): primary actions, active state, data emphasis.
    case brandAccent

    /// Text and glyphs drawn *on top of* ``brandAccent`` — the label of a filled primary button.
    /// Its value flips with the appearance because the accent's lightness does.
    case onBrandAccent

    /// A positive delta, a completed set, a new personal record (`G-7.3`).
    case positive

    /// A failed or missed lift, and a destructive action's confirmation (`G-7.3`).
    case negative

    /// The colour a chart's data takes (`G-7.4`) — the brand accent under a name a chart can use,
    /// so no separate chart palette is ever introduced. Reserved and wired to nothing: `OUT-1.2`
    /// puts charts outside Phase 1.
    case chartPrimary

    /// The token's value in each appearance.
    public var themed: ThemedColor {
        switch self {
        case .background: ThemedColor(dark: SRGBColor(hex: 0x0B0B0D), light: SRGBColor(hex: 0xEFEFF3))
        case .surface: ThemedColor(dark: SRGBColor(hex: 0x17171A), light: SRGBColor(hex: 0xF9F9FB))
        case .surfaceRaised: ThemedColor(dark: SRGBColor(hex: 0x212126), light: SRGBColor(hex: 0xFFFFFF))
        case .separator: ThemedColor(dark: SRGBColor(hex: 0x2E2E35), light: SRGBColor(hex: 0xD7D7DE))
        case .textPrimary: ThemedColor(dark: SRGBColor(hex: 0xF2F2F5), light: SRGBColor(hex: 0x131316))
        case .textSecondary: ThemedColor(dark: SRGBColor(hex: 0xA6A6B0), light: SRGBColor(hex: 0x55555E))
        case .textTertiary: ThemedColor(dark: SRGBColor(hex: 0x8C8C96), light: SRGBColor(hex: 0x6B6B74))
        case .brandAccent: ThemedColor(dark: SRGBColor(hex: 0xFF7A1A), light: SRGBColor(hex: 0xB04400))
        case .onBrandAccent: ThemedColor(dark: SRGBColor(hex: 0x0B0B0D), light: SRGBColor(hex: 0xFFFFFF))
        case .positive: ThemedColor(dark: SRGBColor(hex: 0x32D74B), light: SRGBColor(hex: 0x1B7130))
        case .negative: ThemedColor(dark: SRGBColor(hex: 0xFF453A), light: SRGBColor(hex: 0xB80F19))
        case .chartPrimary: ColorToken.brandAccent.themed
        }
    }

    /// The token's components in `scheme`.
    public func components(in scheme: ColorScheme) -> SRGBColor {
        themed.components(in: scheme)
    }

    /// The token as a SwiftUI colour in `scheme`. Prefer using the token as a `ShapeStyle`, which
    /// takes the appearance from the environment instead of being told it.
    public func color(in scheme: ColorScheme) -> Color {
        themed.color(in: scheme)
    }

    /// `ShapeStyle` resolution, delegated to ``themed``.
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        themed.resolve(in: environment)
    }
}
