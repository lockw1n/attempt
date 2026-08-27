import DesignSystem
import SwiftUI

/// A labelled row in the set editor — the label, the control, and the one line of guidance a label
/// has no room for.
///
/// A shape of its own so every field is laid out by one rule rather than one rule each.
struct FieldRow<Content: View>: View {
    /// What the field is.
    let label: Text

    /// What it accepts, where that is not obvious. Optional.
    let hint: Text?

    /// The control itself.
    @ViewBuilder let content: Content

    /// Label, control, hint.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            label
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            content
            if let hint {
                hint
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
    }
}
