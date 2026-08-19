import SwiftUI

/// An sRGB colour, held as components so a palette entry can be asserted on in a test.
///
/// The design system's colours are declared here rather than in an asset catalogue precisely so
/// they are ordinary values: a catalogue colour can only be inspected by rendering it, which makes
/// `G-4.4`'s contrast floor unprovable without a screen. Nothing else about a catalogue was needed —
/// the light/dark pairing lives in ``ThemedColor``.
public struct SRGBColor: Sendable, Hashable {
    /// Red, as a fraction of full intensity in `0...1`.
    public let red: Double

    /// Green, as a fraction of full intensity in `0...1`.
    public let green: Double

    /// Blue, as a fraction of full intensity in `0...1`.
    public let blue: Double

    /// Opacity in `0...1`, where 0 is fully transparent.
    public let opacity: Double

    /// Builds a colour from components, each a fraction in `0...1`. Values outside that range are
    /// not rejected — SwiftUI clamps on render — but no palette entry declares one.
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    /// Builds a colour from a `0xRRGGBB` literal, which is how the palette is written and how a
    /// design reference states a colour. The high byte is ignored.
    ///
    /// - Parameters:
    ///   - hex: The colour as `0xRRGGBB`, each channel a byte in `0...255`.
    ///   - opacity: Opacity in `0...1`.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// The SwiftUI colour. Always built in the sRGB space, never the extended or display-P3 one:
    /// the palette's numbers are sRGB and reinterpreting them elsewhere would shift every hue.
    public var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}
