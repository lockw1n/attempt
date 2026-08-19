// The component layer: the card surface, the grouped section, the metric tile, the primary action,
// the delta indicator and the five state placeholders (TR-1.4, FR-1.13.1, FR-1.13.3). Everything
// here is built from the DesignTokens scales next door and declares no value of its own.
//
// The re-export is so a screen importing DesignSystem gets the scales too and never has to import
// both. A feature module needing only the scales — a store, a formatter, a preview fixture — should
// import DesignTokens, which carries no view code.
//
// TWO RULES THIS MODULE HOLDS ITSELF TO, both of which a component would be the natural place to
// break:
//
//   No raw values. No colour, font size, text style, spacing, radius or opacity is declared here;
//   they all come from a token. Enforced rather than asked for — the G-7.7 lint rules cover this
//   target's path alongside Features/ and the app. What they do NOT reach is any test target: all
//   six are scoped to Sources/DesignSystem, so DesignTokens, DesignTokensTests and this module's
//   own tests are outside them.
//
//   No copy the caller could have written. Screen-specific text arrives as a `Text` the caller
//   built — never as a `LocalizedStringKey` parameter, which would resolve against this package's
//   bundle rather than the app's (G-3.4) — and that is also what keeps domain knowledge out: a
//   component that named a screen's string would be a component that knew what it was for.
//
//   The exception, and the ONLY one, is copy that is identical on every screen it appears on:
//   "Try again", the offline explanation, the spinner's VoiceOver label. Those are affordances of
//   the app rather than of any screen, and the alternative is the same sentence in twelve feature
//   catalogues. They live in this module's own catalogue, reached through DesignSystemStrings and
//   bound to Bundle.module. The test in DesignSystemStringsTests is what keeps the two lists in
//   step; the line between the two kinds is drawn in DesignSystemStrings' own doc.

@_exported import DesignTokens
