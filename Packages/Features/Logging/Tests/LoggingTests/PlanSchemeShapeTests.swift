import CoreGraphics
import Testing

@testable import Logging

/// `Q-18.2`'s fallback, as a rule rather than as a picture.
///
/// **The half a reference cannot settle.** A snapshot says what one width produced; this says what
/// the rule is at every width, including the boundary — and it is the reason the decision lives in
/// a plain type rather than in ``PlanSchemeLayout``, whose `Subviews` no test can build
/// (`T-1.96`'s rule for a decision written on a view).
///
/// **The widths are points and not spacing tokens**, which is why the gap is a `let` rather than a
/// literal at each call: `G-7.7`'s rule reads `spacing:` followed by a number, and here the number
/// is an input to arithmetic rather than a measurement anyone will see.
@Suite("The plan row's shape")
struct PlanSchemeShapeTests {
    /// The gap between the two columns, as every case here proposes it.
    private let gap: CGFloat = 8

    /// A scheme that leaves the name more than half the width sits beside it (`FR-18.3.3`).
    @Test func aNarrowSchemeSitsBesideItsLabel() {
        let shape = PlanSchemeShape.choose(width: 300, scheme: 100, spacing: gap)

        #expect(shape == .sideBySide(label: 192, scheme: 100))
    }

    /// The two columns and the gap are the whole width — nothing is left over, and nothing spills.
    @Test func theTwoColumnsAndTheGapAreTheWholeWidth() {
        guard
            case .sideBySide(let label, let scheme) = PlanSchemeShape.choose(
                width: 300, scheme: 100, spacing: gap)
        else {
            Issue.record("expected the side-by-side shape")
            return
        }

        #expect(label + scheme + gap == 300)
    }

    /// A scheme wider than half takes a line of its own — `Planned` must not break as *Planne/d*.
    @Test func aWideSchemeTakesItsOwnLine() {
        #expect(PlanSchemeShape.choose(width: 300, scheme: 200, spacing: gap) == .stacked)
    }

    /// The boundary is *at most* half, not *under* it: exactly half still fits beside its label.
    @Test func exactlyHalfStillFitsBeside() {
        #expect(
            PlanSchemeShape.choose(width: 308, scheme: 150, spacing: gap)
                == .sideBySide(label: 150, scheme: 150))
        #expect(PlanSchemeShape.choose(width: 308, scheme: 151, spacing: gap) == .stacked)
    }

    /// An unspecified proposal is the row's ideal, which is the two columns at their own widths —
    /// never ``PlanSchemeShape/stacked``, which would report an ideal height of two lines.
    @Test func anUnspecifiedWidthReportsTheIdealRow() {
        #expect(
            PlanSchemeShape.choose(width: .infinity, scheme: 120, spacing: gap)
                == .sideBySide(label: 0, scheme: 120))
        #expect(
            PlanSchemeShape.choose(width: 0, scheme: 120, spacing: gap)
                == .sideBySide(label: 0, scheme: 120))
    }

    /// A width narrower than the gap itself leaves the label nothing rather than a negative
    /// proposal, which SwiftUI treats as unspecified and would draw at full width.
    @Test func aWidthNarrowerThanTheGapLeavesNothingRatherThanLessThanNothing() {
        #expect(
            PlanSchemeShape.choose(width: 4, scheme: 0, spacing: gap)
                == .sideBySide(label: 0, scheme: 0))
    }
}
