// The component layer: the card surface, the grouped section, the metric tile, the primary action
// and the delta indicator (TR-1.4). Everything here is built from the DesignTokens scales next
// door and declares no value of its own.
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
//   No user-visible strings. Every piece of text arrives as a `Text` the caller built, because a
//   LocalizedStringKey resolved inside a package resolves against the package's bundle rather than
//   the app's (G-3.4). This is also what keeps domain knowledge out: a component that named a
//   string would be a component that knew what it was for.

@_exported import DesignTokens
