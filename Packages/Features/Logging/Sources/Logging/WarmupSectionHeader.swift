import DesignSystem
import DesignTokens
import Localization
import SwiftUI

// A file of its own rather than the top of `SetRowView.swift`, which had reached SwiftLint's file
// ceiling — `SetEditorTarget`'s rule. Same surface: this is the heading over a card's ramp, and
// what is under it is that file's.

/// `FR-1.2.14`'s warmup group, and the control that folds it.
///
/// **Its own fold, beside the card's rather than inside it.** `FR-1.2.13` collapses a finished
/// exercise and `FR-1.2.14` collapses the warmups within one; a card that is open may have either
/// state of this, so the two folds are two pieces of state and two controls.
///
/// **The count is a numeral beside a word**, on `SessionExerciseCard`'s rule: a label next to a
/// number stays a count in every language, where "3 warmups" would need a plural rule per language
/// to say the same thing.
struct WarmupSectionHeader: View {
    /// How many warmups the group holds — the part of it that is legible while it is folded.
    let count: Int

    /// Whether it is open.
    let isExpanded: Bool

    /// Opens or closes it.
    let toggle: () -> Void

    /// Which locale the count is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The heading, as one control across the card's width.
    ///
    /// One VoiceOver element carrying the fold as a **value**, for the card header's reason: there
    /// is no expanded trait, and `.isSelected` means a chosen filter everywhere else in this app.
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.sm.points) {
                Text(LoggingStrings.setWarmupSection)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                Text(count, format: AppFormat.count(locale: locale))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            Text(
                isExpanded
                    ? LoggingStrings.sessionExerciseExpanded
                    : LoggingStrings.sessionExerciseCollapsed
            )
        )
    }
}
