import AppNavigation
import DesignSystem
import SwiftUI

/// One row that opens another screen: what is behind it, and one line on what is there.
///
/// A `NavigationLink` over a `Route` rather than a closure — the destination is composed by the app
/// target (`TR-1.3`), and the route is what lets a screen name another without importing it.
///
/// Shared out of ``SettingsLandingView`` once a second screen needed the same row, so the two cannot
/// drift into two shapes of the same link.
struct SettingsLinkRow: View {
    /// Where the row goes.
    let route: Route

    /// What is behind it.
    let label: LocalizedStringResource

    /// One line on what is there.
    let detail: LocalizedStringResource

    /// The label, the detail under it, and the chevron.
    var body: some View {
        NavigationLink(value: route) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(label)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(detail)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
