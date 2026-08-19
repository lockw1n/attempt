// The other direction: a feature written against the design tokens must produce NO violation.
//
// A fixture proving a rule fires says nothing about whether the rule can be satisfied. A regex
// tightened until it catches everything catches the tokens too, and the failure looks like a
// correctly working gate — every screen violating a rule nobody can pass. verify-lint-rules.sh
// checks this file against all four G-7.7 rules as a negative.
//
// Keep it in the shape a real screen has: spacing, type and colour all reached through tokens,
// each of them the construct the matching rule is hunting for when it carries a number instead.
import DesignTokens
import SwiftUI

struct TokenUsageFixture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text("Estimated max")
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Text("142.5")
                .font(Typography.metricNumeral.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text("+2.5 since March")
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.positive)
        }
        .padding(Spacing.lg.points)
        // The widened frame rule must still pass a token-valued dimension, and `.infinity` beside
        // it: both live in the argument list the rule now scans in full.
        .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
        // A token-valued radius has to pass, in both the shape that names a type and the shorthand
        // that does not — the radius rule scans the label, so both are the same match to it.
        .background(ColorToken.surface, in: .rect(cornerRadius: CornerRadius.card.points))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.control.points))
        // The four-corner form has to be satisfiable too, not merely failable: the rule matches a
        // digit after the label, so a token-valued corner passes where a literal one does not.
        .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
            topLeading: CornerRadius.card.points, bottomLeading: CornerRadius.control.points,
            bottomTrailing: CornerRadius.control.points, topTrailing: CornerRadius.card.points)))
        // Interaction state comes from the Opacity scale, which is the whole of that rule.
        .opacity(Opacity.pressed.value)
    }
}
