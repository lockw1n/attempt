import DesignTokens
import SwiftUI

/// The metric pattern: small label, large numeral, small context line (`G-7.5`).
///
/// The numeral is the visual anchor — it is the largest thing in the tile and the only one in the
/// primary text colour, so a glance lands on the number before it lands on what the number is.
///
/// **The tile carries no surface of its own.** `G-7.5` describes the contents of a card, not the
/// card; wrapping is ``Card``'s job, and keeping them apart is what lets three tiles share one card
/// or one tile sit in a row that is not a card at all.
///
/// Reads to VoiceOver as a single sentence — label, then value, then context (`G-4.2`).
public struct MetricTile<Context: View>: View {
    private let label: Text
    private let value: Text
    private let context: Context

    /// Builds a tile with a context line beneath the numeral.
    ///
    /// - Parameters:
    ///   - label: What the number is. Built by the caller, so it is localized in the caller's
    ///     bundle — see ``GroupedSection`` for why no component here takes a `LocalizedStringKey`.
    ///   - value: The number itself, already formatted.
    ///   - context: The line beneath — typically a ``DeltaIndicator``, a date, or a qualifier.
    public init(label: Text, value: Text, @ViewBuilder context: () -> Context) {
        self.label = label
        self.value = value
        self.context = context()
    }

    /// Label, numeral, context — in that order, which is the whole of `G-7.5`'s pattern.
    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            label
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            value
                .font(Typography.metricNumeral.font)
                .foregroundStyle(ColorToken.textPrimary)
                // G-7.5: the numeral is the anchor, and an anchor broken over three lines is not
                // one. A five-digit tonnage at the largest Dynamic Type size is wider than any
                // phone, so the only two outcomes are wrapping and scaling — and a number read
                // across three lines reads as three numbers. It shrinks to half before it wraps;
                // below that the label and the context line beside it are unreadable anyway, so
                // there is nothing a smaller floor would save.
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // And this is what keeps it the anchor once `context` below is fixed. A `Text`
                // carrying `minimumScaleFactor` is the *flexible* participant in the stack's height
                // negotiation, so an inflexible sibling is satisfied at its expense — fixing the
                // context alone shrank a 182.5 kg to smaller than its own label. Both fixed, and
                // neither yields: G-4.1 gets its wrap and G-7.5 keeps its numeral.
                .fixedSize(horizontal: false, vertical: true)
            context
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
                // G-4.1. Without this the line takes its ideal height — one line — and the rest
                // of the phrase is truncated rather than wrapped, which is what `Training max
                // 175.0 kg` did at accessibility3. Here rather than at each call site: one line for
                // every host at once. The numeral above carries the same modifier, and must.
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension MetricTile where Context == EmptyView {
    /// Builds a tile with no context line — a label and a numeral alone.
    ///
    /// - Parameters:
    ///   - label: What the number is.
    ///   - value: The number itself, already formatted.
    public init(label: Text, value: Text) {
        self.init(label: label, value: value) { EmptyView() }
    }
}
