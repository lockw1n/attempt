import SwiftUI
import Testing

@testable import DesignTokens

@Suite("Colour tokens")
struct ColorTokenTests {
    private static let surfaces: [ColorToken] = [.background, .surface, .surfaceRaised]

    @Test("every token's components are in range in both appearances, and fully opaque")
    func componentsInRange() {
        for token in ColorToken.allCases {
            for scheme in [ColorScheme.dark, .light] {
                let components = token.components(in: scheme)
                #expect((0...1).contains(components.red))
                #expect((0...1).contains(components.green))
                #expect((0...1).contains(components.blue))
                #expect(components.opacity == 1)
            }
        }
        #expect(ColorToken.allCases.count == 12)
    }

    /// `G-7.4`: a chart uses the brand accent. The token exists so a chart never has to reach for a
    /// palette of its own — it is the same colour, not a similar one.
    @Test("the chart colour is the brand accent, not a second palette")
    func chartColourIsTheAccent() {
        #expect(ColorToken.chartPrimary.themed == ColorToken.brandAccent.themed)
    }

    /// `G-7.2`: one accent. Every other pair of tokens is distinct, so a token cannot quietly
    /// become an alias of another — the chart/accent pair above is the single deliberate exception.
    @Test("no two tokens share a value except the chart colour and the accent")
    func tokensAreDistinct() {
        var seen: [ThemedColor: [ColorToken]] = [:]
        for token in ColorToken.allCases {
            seen[token.themed, default: []].append(token)
        }
        let shared = seen.values.filter { $0.count > 1 }.map { Set($0) }
        #expect(shared == [[.brandAccent, .chartPrimary]])
    }

    /// `G-7.1`: background → card → raised card. Elevation is a lighter surface in both
    /// appearances, which is why the light palette's background is not white.
    @Test("elevation moves away from the backdrop in the same direction in both appearances")
    func elevationOrdering() {
        for scheme in [ColorScheme.dark, .light] {
            let luminances = Self.surfaces.map { $0.components(in: scheme).relativeLuminance }
            #expect(zip(luminances, luminances.dropFirst()).allSatisfy { $0 < $1 })
        }
    }

    /// Dark-first (`G-7.1`), expressed in the initialiser: a token written with a dark value alone
    /// is legal and keeps that value in light. The reverse cannot be written at all.
    @Test("a themed colour declared with only a dark value keeps it in light")
    func darkIsTheFallback() {
        let darkOnly = ThemedColor(dark: SRGBColor(hex: 0x123456))
        #expect(darkOnly.light == darkOnly.dark)
        #expect(darkOnly.components(in: .light) == SRGBColor(hex: 0x123456))
        #expect(Appearance.defaultColorScheme == .dark)
    }

    @Test("the two appearances actually differ for every token")
    func appearancesDiffer() {
        for token in ColorToken.allCases {
            #expect(token.components(in: .dark) != token.components(in: .light))
        }
    }

    /// The `ShapeStyle` wiring: resolution reads the appearance out of the environment rather than
    /// always handing back the dark value.
    @Test("resolving in the environment picks the appearance's own value")
    func resolutionFollowsTheEnvironment() {
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        var light = EnvironmentValues()
        light.colorScheme = .light

        for token in ColorToken.allCases {
            #expect(token.resolve(in: dark) == token.themed.dark.color.resolve(in: dark))
            #expect(token.resolve(in: light) == token.themed.light.color.resolve(in: light))
            #expect(token.resolve(in: dark) != token.resolve(in: light))
        }
    }

    @Test("a hex literal maps to the components a designer would read off it")
    func hexDecoding() {
        let white = SRGBColor(hex: 0xFFFFFF)
        #expect(white.red == 1 && white.green == 1 && white.blue == 1)

        let orange = SRGBColor(hex: 0xFF7A1A)
        #expect(orange.red == 1)
        #expect(abs(orange.green - 122.0 / 255) < 0.0001)
        #expect(abs(orange.blue - 26.0 / 255) < 0.0001)
        #expect(SRGBColor(hex: 0x000000).red == 0)
        #expect(SRGBColor(hex: 0xFF0000, opacity: 0.5).opacity == 0.5)
    }

    /// Both initialisers default to opaque. Anchored to the literal rather than left to the palette
    /// to demonstrate: every palette entry goes through ``SRGBColor/init(hex:opacity:)``, so the
    /// memberwise initialiser's own default was reachable from no test and could be changed to
    /// anything without a failure.
    @Test("a colour written without an opacity is opaque, whichever initialiser wrote it")
    func opacityDefaultsToOpaque() {
        #expect(SRGBColor(red: 0.5, green: 0.5, blue: 0.5).opacity == 1)
        #expect(SRGBColor(hex: 0x808080).opacity == 1)
    }
}
