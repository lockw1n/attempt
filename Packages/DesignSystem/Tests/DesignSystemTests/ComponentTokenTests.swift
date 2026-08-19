import DesignTokens
import SwiftUI
import Testing

@testable import DesignSystem

/// The component layer declares no values of its own — what it declares is *choices among tokens*,
/// and those are what a test can hold. A view's rendering is T-1.08's snapshot; this is the layer
/// beneath it, where a wrong choice is a wrong constant rather than a wrong pixel.
@Suite("Component token choices")
struct ComponentTokenTests {
    /// `G-7.1`: elevation is a lighter surface. The card levels have to name the two surface tokens
    /// and neither may name the background, which is the screen behind them rather than a card.
    @Test("each card level draws its own surface, and never the backdrop")
    func elevationSurfaces() {
        #expect(CardElevation.base.surface == .surface)
        #expect(CardElevation.raised.surface == .surfaceRaised)

        let surfaces = CardElevation.allCases.map(\.surface)
        #expect(Set(surfaces).count == CardElevation.allCases.count)
        #expect(!surfaces.contains(.background))
    }

    /// The nesting rule the two levels exist for: an inner surface takes the smaller curve. Pinned
    /// as an inequality rather than as two constants, because the relationship is what matters —
    /// retuning the scale inside `G-7.1`'s band must not be able to invert it.
    @Test("a raised surface's radius is strictly smaller than the card it sits in")
    func nestedRadiusIsSmaller() {
        #expect(CardElevation.raised.cornerRadius < CardElevation.base.cornerRadius)
        #expect(CardElevation.base.cornerRadius == .card)
        #expect(CardElevation.raised.cornerRadius == .control)
    }

    /// `G-7.3`: semantic colour means direction, and neutral means neutral. A delta that had no
    /// movement to report drawing itself in the success colour is the exact misuse the requirement
    /// names as "never decorative".
    @Test("the delta tints are the two semantic tokens plus a neutral, and no accent")
    func deltaTints() {
        #expect(DeltaDirection.increase.tint == .positive)
        #expect(DeltaDirection.decrease.tint == .negative)
        #expect(DeltaDirection.unchanged.tint == .textSecondary)
        #expect(!DeltaDirection.allCases.map(\.tint).contains(.brandAccent))
    }

    /// `G-4.5`, as a property rather than as a claim: strip the colour, and the three cases must
    /// still be three cases. The glyph alone does it, which is the cue that survives both
    /// colourblindness and a monochrome rendering.
    @Test("every direction is distinguishable with the colour removed")
    func directionsSurviveWithoutColour() {
        let symbols = DeltaDirection.allCases.map(\.symbolName)
        #expect(Set(symbols).count == DeltaDirection.allCases.count)
        #expect(!symbols.contains(""))

        // The sign is the second, independent cue. It is deliberately empty for `.unchanged` —
        // there is no sign for "did not move" — so it tells the two *signed* cases apart on its own
        // and the glyph carries the third.
        #expect(DeltaDirection.increase.sign != DeltaDirection.decrease.sign)
        #expect(!DeltaDirection.increase.sign.isEmpty)
        #expect(!DeltaDirection.decrease.sign.isEmpty)
        #expect(DeltaDirection.unchanged.sign.isEmpty)
    }

    /// The minus is U+2212 and not a hyphen-minus. A hyphen is narrower than the plus, so a column
    /// of deltas would not align — and the two characters are indistinguishable in a diff, which is
    /// why this is asserted against the scalar rather than against a literal that looks right.
    @Test("the negative sign is the typographic minus, not a hyphen")
    func minusIsNotAHyphen() {
        #expect(DeltaDirection.decrease.sign.unicodeScalars.map(\.value) == [0x2212])
        #expect(DeltaDirection.increase.sign.unicodeScalars.map(\.value) == [0x2B])
    }
}

/// The primary action's width, which is a parameter rather than something a caller can apply from
/// outside — see ``PrimaryActionButtonStyle`` for the simulator run that established that.
@Suite("Primary action width")
struct PrimaryActionWidthTests {
    /// Intrinsic must impose *no* maximum. A very large number would look the same until the button
    /// met a container that offered more, so the absence is the property worth pinning.
    @Test("intrinsic imposes no maximum, fill imposes an unbounded one")
    func widthMapping() {
        #expect(PrimaryActionWidth.intrinsic.maxWidth == nil)
        #expect(PrimaryActionWidth.fill.maxWidth == .infinity)
    }

    /// The default is the conservative one: a style applied without thinking about width does not
    /// silently claim the whole line.
    @Test("the style defaults to intrinsic, and both entry points agree with their names")
    func styleDefaults() {
        #expect(PrimaryActionButtonStyle().width == .intrinsic)
        #expect(PrimaryActionButtonStyle(width: .fill).width == .fill)
        // Written through the `.primaryAction` shorthand a caller actually types — the static
        // members live on a constrained extension, so this is the only way to reach them.
        let shorthand: PrimaryActionButtonStyle = .primaryAction
        let filled: PrimaryActionButtonStyle = .primaryAction(.fill)
        #expect(shorthand.width == .intrinsic)
        #expect(filled.width == .fill)
    }
}

/// The fade the primary action draws at — the only branch in the component layer, and until this
/// suite the only thing in it a mutation could survive: swapping ``Opacity/disabled`` for
/// ``Opacity/pressed`` inside the private body view left all 32 tests green.
@Suite("Primary action interaction state")
struct PrimaryActionOpacityTests {
    /// The three states, each pinned to its own token rather than to a number.
    @Test("resting is opaque, pressed fades, disabled fades further")
    func statesMapToTokens() {
        #expect(PrimaryActionButtonStyle.opacity(isEnabled: true, isPressed: false) == .opaque)
        #expect(PrimaryActionButtonStyle.opacity(isEnabled: true, isPressed: true) == .pressed)
        #expect(PrimaryActionButtonStyle.opacity(isEnabled: false, isPressed: false) == .disabled)
    }

    /// The one case the two inputs disagree about. A disabled control does not brighten because a
    /// finger landed on it, so `isEnabled` has to win — the branch order is the assertion.
    @Test("disabled outranks pressed")
    func disabledOutranksPressed() {
        #expect(PrimaryActionButtonStyle.opacity(isEnabled: false, isPressed: true) == .disabled)
    }

    /// Three states must draw three values, in that order. Two of them equal would make one state
    /// unobservable, which is how a swapped constant hides.
    @Test("the reachable states are three distinct values, descending")
    func statesAreDistinctAndOrdered() {
        let drawn = [
            PrimaryActionButtonStyle.opacity(isEnabled: true, isPressed: false),
            PrimaryActionButtonStyle.opacity(isEnabled: true, isPressed: true),
            PrimaryActionButtonStyle.opacity(isEnabled: false, isPressed: true),
        ].map(\.value)

        #expect(Set(drawn).count == drawn.count)
        #expect(drawn == drawn.sorted(by: >))
        #expect(drawn.first == 1)
    }
}
