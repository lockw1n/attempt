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
    ///
    /// **Both lines take `fixedSize` vertically (`G-4.1`), and the pair is deliberate.** Without it a
    /// detail whose ideal single line is a little wider than the row truncates instead of wrapping —
    /// measured on `settings.landing.sync.detail`, which lost four words at the default size while
    /// wrapping cleanly at `accessibility3`, so no accessibility pass could have found it. Giving the
    /// modifier to one line alone makes the other the flexible participant and moves the truncation
    /// rather than ending it.
    var body: some View {
        NavigationLink(value: route) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(label)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
