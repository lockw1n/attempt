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
            context
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
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
