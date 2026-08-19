import SwiftUI

/// A colour with a value in each appearance (`G-7.1`).
///
/// **Dark is the primary definition and light is the fallback**, which is why `light` defaults to
/// `dark` rather than the other way round: a token added without a light value is still a legal,
/// dark-first token, and a token added without a *dark* value cannot be written at all.
///
/// Conforms to `ShapeStyle`, so a view says `.foregroundStyle(ColorToken.textPrimary)` and the
/// environment picks the appearance. Use ``color(in:)`` only where a concrete `Color` is required —
/// a gradient stop, or an API that has not adopted `ShapeStyle`.
public struct ThemedColor: Sendable, Hashable, ShapeStyle {
    /// The value used in dark appearance.
    public let dark: SRGBColor

    /// The value used in light appearance.
    public let light: SRGBColor

    /// Pairs a dark value with a light one. Omitting `light` keeps the dark value in both, which is
    /// a deliberate, visible compromise rather than a silent one — never a substitute for choosing.
    public init(dark: SRGBColor, light: SRGBColor? = nil) {
        self.dark = dark
        self.light = light ?? dark
    }

    /// The components this colour takes in `scheme`.
    ///
    /// Anything that is not explicitly `.light` resolves to ``dark``. That is the dark-first rule
    /// applied to a scheme this build has never heard of, and it is why there is no `@unknown`
    /// branch here to forget to update.
    public func components(in scheme: ColorScheme) -> SRGBColor {
        scheme == .light ? light : dark
    }

    /// The SwiftUI colour this token takes in `scheme`.
    public func color(in scheme: ColorScheme) -> Color {
        components(in: scheme).color
    }

    /// `ShapeStyle` resolution: reads the appearance out of the environment and hands back the
    /// matching value.
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color(in: environment.colorScheme).resolve(in: environment)
    }
}
