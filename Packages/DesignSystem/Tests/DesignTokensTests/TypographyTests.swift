import SwiftUI
import Testing

@testable import DesignTokens

@Suite("Type scale")
struct TypographyTests {
    @Test("every role maps to a distinct entry, so no role is a duplicate wearing a second name")
    func rolesAreDistinct() {
        let styles = Typography.allCases.map(\.style)
        #expect(styles.count == 10)
        #expect(Set(styles).count == styles.count)
    }

    /// `G-7.5`: the numeral is the anchor of the tile, and it is the largest role in the scale.
    @Test("the metric numeral is the largest role, and its label and context are the small ones")
    func metricTileShape() {
        #expect(Typography.metricNumeral.style.textStyle == .largeTitle)
        #expect(Typography.metricNumeral.style.weight == .bold)
        #expect(Typography.metricLabel.style.textStyle == .caption)
        #expect(Typography.metricContext.style.textStyle == .footnote)
    }

    /// Exactly the roles that carry a *number the user reads while it changes* are monospaced.
    /// Asserted as a set rather than one `#expect` per role: a new role added without a decision
    /// about its digits fails this, which is the point.
    @Test("monospaced digits are on the numeric roles and nowhere else")
    func monospacedDigitRoles() {
        let monospaced = Set(Typography.allCases.filter { $0.style.usesMonospacedDigits })
        #expect(monospaced == [.metricNumeral, .numericValue])
    }

    /// The scale is Dynamic Type-aware by construction (`G-7.6`, `G-4.1`) — a `TypeStyle` holds a
    /// `Font.TextStyle` and has nowhere to put a point size. This pins that `font` actually builds
    /// the font from that style, and that `usesMonospacedDigits` reaches the font rather than
    /// sitting in the descriptor unread.
    @Test("`font` is the described system font, and monospacing changes it")
    func fontConstruction() {
        #expect(Typography.body.font == Font.system(.body, design: .default, weight: .regular))
        #expect(Typography.sectionHeading.font == Font.system(.headline, design: .default, weight: .semibold))
        #expect(Typography.numericValue.font != Font.system(.body, design: .default, weight: .semibold))
        #expect(
            Typography.numericValue.font
                == Font.system(.body, design: .default, weight: .semibold).monospacedDigit()
        )
    }

    @Test("no role is silently missing from the scale")
    func scaleIsComplete() {
        #expect(Typography.allCases.count == 10)
        #expect(Typography.allCases.contains(.screenTitle))
    }
}
