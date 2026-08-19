import Testing

@testable import DesignTokens

/// The three scales T-1.03's components needed and T-1.02 did not have: radius, touch target and
/// interaction opacity. Each is pinned to the requirement that fixes its numbers, not to the
/// numbers a designer happened to pick.
@Suite("Radius, touch target and opacity scales")
struct ScaleTests {
    /// `G-7.1` states 12–16pt and this is the whole of the licence: a token outside that band is a
    /// different visual language, and adding one should have to argue with this test first.
    @Test("every radius is inside G-7.1's 12–16pt band")
    func radiiAreInBand() {
        for radius in CornerRadius.allCases {
            #expect((12...16).contains(radius.points), "\(radius) is \(radius.points)pt")
        }
        #expect(CornerRadius.control.points == 12)
        #expect(CornerRadius.card.points == 16)
    }

    /// Ordered smallest to largest, and no two steps the same size — a scale with a duplicate step
    /// is a scale with a name nobody can choose between.
    @Test("the radius scale is ordered and has no duplicate steps")
    func radiiAreOrdered() {
        let points = CornerRadius.allCases.map(\.points)
        #expect(points == points.sorted())
        #expect(Set(points).count == points.count)
        #expect(CornerRadius.control < CornerRadius.card)
    }

    /// `G-4.3`'s two figures, which are the requirement's own and not a preference.
    @Test("the touch targets are G-4.3's 44 and 60 points")
    func touchTargets() {
        #expect(TouchTarget.standard.points == 44)
        #expect(TouchTarget.logging.points == 60)
        #expect(TouchTarget.standard < TouchTarget.logging)
    }

    /// The scale's shape: two faded states below a named resting value. `opaque` exists so a
    /// conditional choosing an interaction state never has to write the bare literal 1 — the case
    /// that would otherwise be the one magic number left in the component layer.
    @Test("the opacity scale fades from disabled to opaque, and tops out at fully opaque")
    func opacityScale() {
        #expect(Opacity.disabled.value == 0.4)
        #expect(Opacity.pressed.value == 0.75)
        #expect(Opacity.opaque.value == 1)

        let values = Opacity.allCases.map(\.value)
        #expect(values == values.sorted())
        #expect(values.allSatisfy { (0...1).contains($0) })
        #expect(values.max() == 1)
    }
}
