import SwiftUI
import Testing

@testable import DesignTokens

/// WCAG 2.1 relative luminance and contrast ratio, over the palette's own components.
///
/// It lives in the test target rather than the module: `G-4.4` is a property the palette must
/// *have*, not a service the app needs at runtime, and a shipped contrast API would invite a
/// feature to compute a colour instead of naming a token.
extension SRGBColor {
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    func contrastRatio(against other: SRGBColor) -> Double {
        let lhs = relativeLuminance
        let rhs = other.relativeLuminance
        return (max(lhs, rhs) + 0.05) / (min(lhs, rhs) + 0.05)
    }
}

@Suite("Palette contrast")
struct ContrastTests {
    private static let textTokens: [ColorToken] = [
        .textPrimary, .textSecondary, .textTertiary, .brandAccent, .positive, .negative,
    ]
    private static let surfaces: [ColorToken] = [.background, .surface, .surfaceRaised]

    /// `G-4.4`: ≥ 4.5:1 for text, in light and dark. T-1.82 verifies this on real screens; here it
    /// is a property of the palette, checked before a screen exists to fail it. Every text-bearing
    /// token is checked against every surface it can legally sit on — a floor that held only for
    /// the pairing a designer happened to try is not a floor.
    @Test("every text colour clears 4.5:1 on every surface, in both appearances")
    func textContrast() {
        for scheme in [ColorScheme.dark, .light] {
            for text in Self.textTokens {
                for surface in Self.surfaces {
                    let ratio = text.components(in: scheme).contrastRatio(against: surface.components(in: scheme))
                    #expect(ratio >= 4.5, "\(text) on \(surface) in \(scheme) is \(ratio):1")
                }
            }
        }
    }

    @Test("a label on the accent clears 4.5:1 in both appearances")
    func accentLabelContrast() {
        for scheme in [ColorScheme.dark, .light] {
            let ratio = ColorToken.onBrandAccent.components(in: scheme)
                .contrastRatio(against: ColorToken.brandAccent.components(in: scheme))
            #expect(ratio >= 4.5, "label on the accent in \(scheme) is \(ratio):1")
        }
    }

    /// The separator is documented as *not* a text colour. Pinning it below the floor keeps that
    /// claim honest: if someone lightens it into text territory, this fails and they have to decide
    /// whether they meant to add a text token.
    @Test("the separator stays a hairline, well under the text floor")
    func separatorIsNotText() {
        for scheme in [ColorScheme.dark, .light] {
            let ratio = ColorToken.separator.components(in: scheme)
                .contrastRatio(against: ColorToken.surface.components(in: scheme))
            #expect(ratio < 3)
        }
    }
}
