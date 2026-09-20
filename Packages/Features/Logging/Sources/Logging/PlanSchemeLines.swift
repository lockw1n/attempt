import DesignTokens
import SwiftUI

/// The planned or performed scheme, one line per group (`FR-18.3.1`).
///
/// **The one place the scheme's style lives.** Three screens draw it — the day's checklist, the
/// week's card and the past day that shares the first's row — and `F-07` was that it was the least
/// prominent text on the row it is the point of. Body size, the primary colour and monospaced
/// digits, so the numbers read at the rack and form a column down the screen.
///
/// **It takes rendered strings rather than targets**, which is what keeps it a style and not a
/// second renderer: ``WeekPlanTargets`` is where a group becomes `110 kg × 4 × 4`, and a component
/// that re-derived it would be the second place the format lives.
///
/// **It wraps rather than truncates and never scales** (`NFR-18.2`). At `accessibility3` on a
/// 320 pt width a scheme is wider than the screen, so the choice is between a wrap and a clip;
/// `minimumScaleFactor` is ruled out by the requirement and by `T-1.96`'s pairing trap, where a
/// scalable line is the one that pays for an inflexible sibling.
struct PlanSchemeLines: View {
    /// The groups, in order, each already rendered — `110 kg × 4 × 4`, or `12 × 3` where the plan
    /// named no load (`FR-15.2.2`). Empty draws nothing, which is `FR-1.2.2`'s added row.
    let schemes: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: Spacing.xxs.points) {
            // By position rather than by value: two identical groups are two lines, and a plan is
            // free to prescribe the same scheme twice.
            ForEach(Array(schemes.enumerated()), id: \.offset) { _, scheme in
                Text(verbatim: scheme)
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Which of the two shapes a labelled plan row takes, and at what widths (`Q-18.2`, `FR-18.3.3`).
///
/// **A plain type rather than a computed property on the layout**, which is `T-1.96`'s rule: the
/// decision is the thing worth a test, and `Layout.Subviews` cannot be built in one. What the
/// layout does is measure; what this does is choose.
nonisolated enum PlanSchemeShape: Equatable {
    /// The label on the leading edge and the scheme beside it, each with the width it gets.
    case sideBySide(label: CGFloat, scheme: CGFloat)

    /// The label on its own line and the scheme under it, right-aligned to the same edge.
    case stacked

    /// Chooses between them.
    ///
    /// **The test is on the *scheme* column, not on the name.** `Q-18.2` put the fallback at
    /// *"where the name column would drop under half the card's width"* — which is the same
    /// sentence read from the other side, and the only side a layout can measure before it has
    /// laid the name out. A scheme needing more than half leaves the name less than half, so the
    /// two go on separate lines and each gets the whole width.
    ///
    /// **Measured rather than read off the type size.** `SetRowView` switches at
    /// `dynamicTypeSize.isAccessibilitySize`, which is the right instrument there — the load's
    /// width is roughly the same on every row. Here it is not: a two-group log at the default size
    /// inside a checklist row already needs more than half, and `Planned` broke as *Planne/d* when
    /// the switch was the type size. The accessibility sizes still fall to ``stacked``; they are
    /// now a consequence rather than the rule.
    ///
    /// - Parameters:
    ///   - width: What the row has to lay out in. A non-positive or non-finite width is the
    ///     unspecified proposal, which takes the side-by-side shape — that is the size the row
    ///     reports as its ideal.
    ///   - scheme: The scheme column's own ideal width.
    ///   - spacing: What separates the two in the side-by-side shape.
    /// - Returns: The shape, and in the side-by-side case the two widths.
    static func choose(width: CGFloat, scheme: CGFloat, spacing: CGFloat) -> PlanSchemeShape {
        guard width.isFinite, width > 0 else { return .sideBySide(label: 0, scheme: scheme) }
        let available = max(width - spacing, 0)
        guard scheme <= available / 2 else { return .stacked }
        return .sideBySide(label: available - scheme, scheme: scheme)
    }
}

/// A label on the leading edge and ``PlanSchemeLines`` on the trailing one — the table `F-07` asked
/// for (`FR-18.3.2`, `FR-18.3.3`).
///
/// **Exactly two subviews**, in order: the label, then the scheme column. It is `internal` and has
/// one caller shape, so the contract is held by ``PlanSchemeRow`` rather than by a runtime check.
struct PlanSchemeLayout: Layout {
    /// What separates the label from the column beside it.
    let columnSpacing: CGFloat

    /// What separates the label from the column under it.
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let scheme = subviews[1].sizeThatFits(.unspecified).width
        switch PlanSchemeShape.choose(width: width, scheme: scheme, spacing: columnSpacing) {
        case .sideBySide(let labelWidth, let schemeWidth):
            let label = subviews[0].sizeThatFits(.init(width: labelWidth, height: nil))
            let lines = subviews[1].sizeThatFits(.init(width: schemeWidth, height: nil))
            return CGSize(
                width: width.isFinite ? width : label.width + columnSpacing + lines.width,
                height: max(label.height, lines.height))
        case .stacked:
            let label = subviews[0].sizeThatFits(.init(width: width, height: nil))
            let lines = subviews[1].sizeThatFits(.init(width: width, height: nil))
            return CGSize(width: width, height: label.height + lineSpacing + lines.height)
        }
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let scheme = subviews[1].sizeThatFits(.unspecified).width
        let shape = PlanSchemeShape.choose(
            width: bounds.width, scheme: scheme, spacing: columnSpacing)
        switch shape {
        case .sideBySide(let labelWidth, let schemeWidth):
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: .init(width: labelWidth, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.minY),
                anchor: .topTrailing,
                proposal: .init(width: schemeWidth, height: nil))
        case .stacked:
            let label = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: .init(width: bounds.width, height: nil))
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.minY + label.height + lineSpacing),
                anchor: .topTrailing,
                proposal: .init(width: bounds.width, height: nil))
        }
    }
}

/// A plan row: what it is called, and what it prescribes (`FR-18.3.2`, `FR-18.3.3`).
struct PlanSchemeRow<Label: View>: View {
    /// The groups, rendered — see ``PlanSchemeLines/schemes``.
    let schemes: [String]

    /// What names them: a lift on the week's card, *Planned* or *Did* on a day's answered row.
    let label: Label

    /// Builds the row.
    ///
    /// - Parameters:
    ///   - schemes: The groups, rendered.
    ///   - label: What names them.
    init(schemes: [String], @ViewBuilder label: () -> Label) {
        self.schemes = schemes
        self.label = label()
    }

    var body: some View {
        PlanSchemeLayout(
            columnSpacing: Spacing.sm.points, lineSpacing: Spacing.xxs.points
        ) {
            label
            PlanSchemeLines(schemes: schemes)
        }
    }
}
