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

    /// Chooses for a whole row, whatever number of labelled lines it holds (`FR-18.3.2`).
    ///
    /// **One shape for every line of the row, decided by the widest of them.** An answered row is
    /// *Planned* over *Did*, and the requirement is that the two "take the same size and
    /// alignment" — so a row whose plan renders narrow (`12 × 3`, `FR-15.2.2`'s open load) and
    /// whose performance renders wide (`24 kg × 12 × 3`) must not put one label beside its numbers
    /// and the other above them. Deciding per line is what produced exactly that.
    ///
    /// - Parameters:
    ///   - width: What the row has to lay out in — see the other overload.
    ///   - schemes: Each line's own ideal width, in any order.
    ///   - spacing: What separates label from column in the side-by-side shape.
    /// - Returns: The shape the whole row takes.
    static func choose(width: CGFloat, schemes: [CGFloat], spacing: CGFloat) -> PlanSchemeShape {
        choose(width: width, scheme: schemes.max() ?? 0, spacing: spacing)
    }

    /// Chooses between them for one measured column.
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

/// A row's labelled scheme lines, laid out as one table (`FR-18.3.2`, `FR-18.3.3`).
///
/// **Subviews come in pairs**, a label then its ``PlanSchemeLines``, and the whole row takes one
/// shape read across every pair — which is why both pairs of an answered row belong to *one* of
/// these rather than to a stack of two. A trailing odd subview is laid out by nobody rather than
/// paired with the wrong thing; the contract is held by ``PlanSchemeRows``' callers.
struct PlanSchemeLayout: Layout {
    /// What separates a label from the column beside it.
    let columnSpacing: CGFloat

    /// What separates a label from the column under it.
    let lineSpacing: CGFloat

    /// What separates one labelled pair from the next.
    let pairSpacing: CGFloat

    /// Which edge is the leading one (`G-3.2`). A custom layout is handed physical bounds, so
    /// unlike the `.trailing` alignments inside ``PlanSchemeLines`` it does not mirror by itself.
    let layoutDirection: LayoutDirection

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) -> CGSize {
        let labels = Array(labelIndices(subviews))
        guard !labels.isEmpty else { return .zero }
        let width = proposal.width ?? .infinity
        var height = pairSpacing * CGFloat(labels.count - 1)
        let shape = PlanSchemeShape.choose(
            width: width, schemes: schemeWidths(subviews), spacing: columnSpacing)
        switch shape {
        case .sideBySide(let labelWidth, let schemeWidth):
            // An unspecified proposal asks what the row would *like*, and a label measured at the
            // zero width that branch reports would answer with its minimum instead — for a long
            // exercise name, one word per line.
            let labelProposal: ProposedViewSize =
                width.isFinite ? .init(width: labelWidth, height: nil) : .unspecified
            var ideal: CGFloat = 0
            for index in labels {
                let label = subviews[index].sizeThatFits(labelProposal)
                let lines = subviews[index + 1].sizeThatFits(.init(width: schemeWidth, height: nil))
                height += max(label.height, lines.height)
                ideal = max(ideal, label.width + columnSpacing + lines.width)
            }
            return CGSize(width: width.isFinite ? width : ideal, height: height)
        case .stacked:
            for index in labels {
                let label = subviews[index].sizeThatFits(.init(width: width, height: nil))
                let lines = subviews[index + 1].sizeThatFits(.init(width: width, height: nil))
                height += label.height + lineSpacing + lines.height
            }
            return CGSize(width: width, height: height)
        }
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
    ) {
        let labels = Array(labelIndices(subviews))
        guard !labels.isEmpty else { return }
        var y = bounds.minY
        let shape = PlanSchemeShape.choose(
            width: bounds.width, schemes: schemeWidths(subviews), spacing: columnSpacing)
        switch shape {
        case .sideBySide(let labelWidth, let schemeWidth):
            for index in labels {
                let label = subviews[index].sizeThatFits(.init(width: labelWidth, height: nil))
                let lines = subviews[index + 1].sizeThatFits(.init(width: schemeWidth, height: nil))
                place(subviews[index], in: bounds, y: y, width: labelWidth, leading: true)
                place(subviews[index + 1], in: bounds, y: y, width: schemeWidth, leading: false)
                y += max(label.height, lines.height) + pairSpacing
            }
        case .stacked:
            for index in labels {
                let label = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                let lines = subviews[index + 1].sizeThatFits(.init(width: bounds.width, height: nil))
                place(subviews[index], in: bounds, y: y, width: bounds.width, leading: true)
                y += label.height + lineSpacing
                place(subviews[index + 1], in: bounds, y: y, width: bounds.width, leading: false)
                y += lines.height + pairSpacing
            }
        }
    }

    /// The index of each label, which is the first of a pair.
    ///
    /// - Parameter subviews: What the layout was handed.
    /// - Returns: Every index that has a scheme column after it.
    private func labelIndices(_ subviews: Subviews) -> StrideTo<Int> {
        stride(from: 0, to: max(subviews.count - 1, 0), by: 2)
    }

    /// Each pair's scheme column at its own ideal width.
    ///
    /// - Parameter subviews: What the layout was handed.
    /// - Returns: One width per pair, in order.
    private func schemeWidths(_ subviews: Subviews) -> [CGFloat] {
        labelIndices(subviews).map { subviews[$0 + 1].sizeThatFits(.unspecified).width }
    }

    /// Places one subview against the leading or the trailing edge, whichever those are here.
    ///
    /// - Parameters:
    ///   - subview: What to place.
    ///   - bounds: The row's own rectangle.
    ///   - y: Its top.
    ///   - width: What to propose it.
    ///   - leading: Whether it sits on the leading edge rather than the trailing one.
    private func place(
        _ subview: LayoutSubview, in bounds: CGRect, y: CGFloat, width: CGFloat, leading: Bool
    ) {
        let mirrored = layoutDirection == .rightToLeft
        let x = leading == mirrored ? bounds.maxX : bounds.minX
        let anchor: UnitPoint = leading == mirrored ? .topTrailing : .topLeading
        subview.place(
            at: CGPoint(x: x, y: y), anchor: anchor, proposal: .init(width: width, height: nil))
    }
}

/// One or more plan lines that share a shape — the table `F-07` asked for (`FR-18.3.2`).
///
/// **The content is pairs**, each a label followed by its ``PlanSchemeLines``. A row that draws
/// *Planned* and *Did* passes both pairs here, because deciding their shape separately is what
/// lets one sit beside its numbers while the other sits above them.
struct PlanSchemeRows<Content: View>: View {
    /// The pairs.
    let content: Content

    /// Which edge is the leading one, for ``PlanSchemeLayout/layoutDirection``.
    @Environment(\.layoutDirection) private var layoutDirection

    /// Builds the table.
    ///
    /// - Parameter content: The pairs — a label, then its scheme lines, per row.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        PlanSchemeLayout(
            columnSpacing: Spacing.sm.points,
            lineSpacing: Spacing.xxs.points,
            pairSpacing: Spacing.xxs.points,
            layoutDirection: layoutDirection
        ) {
            content
        }
    }
}

/// A plan row: what it is called, and what it prescribes (`FR-18.3.3`).
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
        PlanSchemeRows {
            label
            PlanSchemeLines(schemes: schemes)
        }
    }
}
