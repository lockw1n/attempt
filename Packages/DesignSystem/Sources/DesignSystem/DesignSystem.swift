// The component layer: cards, the metric tile, buttons and the surface treatment G-7.1 describes.
//
// Still empty — the components land in T-1.03 (TR-1.4). What is here is the re-export, so a screen
// importing DesignSystem gets the scales too and never has to import both.
//
// The tokens themselves live in the DesignTokens target next door: spacing (G-7.7), the type scale
// (G-7.6) and the colour vocabulary (G-7.1–G-7.4). A feature module needing only those should
// import DesignTokens, which carries no view code.
//
// Nothing in this module may declare a colour, a font size, a text style or a spacing value of its
// own, and that is enforced rather than asked for: the G-7.7 lint rules cover this target's path
// alongside Features/ and the app. The exemption is the DesignTokens target alone, which is where
// the raw values are supposed to be.

@_exported import DesignTokens
