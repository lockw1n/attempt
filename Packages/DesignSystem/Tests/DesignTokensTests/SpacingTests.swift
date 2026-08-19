import CoreGraphics
import Testing

@testable import DesignTokens

@Suite("Spacing scale")
struct SpacingTests {
    /// The scale's actual values, anchored to literals. A test comparing two tokens to each other
    /// would survive the whole scale being multiplied by anything.
    @Test("each step is the point value it claims")
    func stepValues() {
        #expect(Spacing.xxs.points == 2)
        #expect(Spacing.xs.points == 4)
        #expect(Spacing.sm.points == 8)
        #expect(Spacing.md.points == 12)
        #expect(Spacing.lg.points == 16)
        #expect(Spacing.xl.points == 24)
        #expect(Spacing.xxl.points == 32)
        #expect(Spacing.allCases.count == 7)
    }

    @Test("the scale increases strictly, in declaration order")
    func strictlyIncreasing() {
        let points = Spacing.allCases.map(\.points)
        #expect(points == points.sorted())
        #expect(Set(points).count == points.count)
        #expect(zip(points, points.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("no step is zero or negative — an absent gap is an absent token")
    func allPositive() {
        #expect(Spacing.allCases.allSatisfy { $0.points > 0 })
        #expect(Spacing.allCases.isEmpty == false)
    }

    @Test("`Comparable` follows the scale, not the case names")
    func ordering() {
        #expect(Spacing.sm < Spacing.lg)
        #expect(Spacing.allCases.max() == .xxl)
        #expect(Spacing.allCases.min() == .xxs)
    }
}
