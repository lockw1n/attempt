import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// `FR-1.2.10`'s "last time" strip: what this exercise looked like the last time it was trained,
/// inside the card it is being logged into.
///
/// **Inside the card and above the sets, which is the requirement's "without navigation" read at
/// the moment it matters.** The number a lifter wants before the first working set is what they did
/// last week; a strip below the commands would be a thing to scroll to after the set had already
/// been logged.
///
/// **The state placeholder is per card here, where the empty set list beneath it is a sentence.**
/// That is not an inconsistency: zero sets is a *count*, and the card can say so in four words,
/// where "no previous session" is `FR-1.13.3`'s own case — something derived from history that the
/// history cannot support — and rendering it as a blank strip is exactly the broken-looking area
/// the requirement exists to prevent.
struct PreviousPerformanceStrip: View {
    /// Which of the three states this card is in.
    let state: PreviousPerformanceState

    /// The unit the previous session's loads are shown in (`G-3.1`) — the current preference, not
    /// whatever was set the day they were logged: storage is grams either way (`G-1.1`), and two
    /// units down one card would be unreadable.
    let unit: MassUnit

    /// Which locale the loads, the counts and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The strip, the placeholder, or nothing at all.
    var body: some View {
        switch state {
        case .unknown:
            // **Nothing, and it is the only honest rendering.** Before the read answers, both other
            // states assert something: the strip claims a comparison and the placeholder claims
            // there is none to make. The read is local (`G-2.3`), so what this costs is a frame.
            EmptyView()
        case .noneYet:
            InsufficientDataView(
                headline: Text(LoggingStrings.sessionPreviousEmptyHeadline),
                message: Text(LoggingStrings.sessionPreviousEmptyMessage)
            )
        case .performed(let performance):
            performed(performance)
        }
    }

    /// The last session's work: when it was, and what was done.
    ///
    /// One VoiceOver element, because it is one fact (`G-4.2`). The multiplication sign inside each
    /// set is a character rather than the drawn glyph the set rows use, so it is announced as the
    /// word rather than hidden.
    ///
    /// - Parameter performance: The previous session's performance.
    /// - Returns: The strip.
    private func performed(_ performance: PreviousPerformance) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            HStack(spacing: Spacing.sm.points) {
                Text(LoggingStrings.sessionPreviousHeading)
                Text(performance.date, format: AppFormat.date(locale: locale))
            }
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            Text(verbatim: summary(of: performance))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm.points)
        .background(
            ColorToken.surfaceRaised,
            in: .rect(cornerRadius: CornerRadius.control.points)
        )
        .accessibilityElement(children: .combine)
    }

    /// The previous session's working sets as one line.
    ///
    /// **A list in the user's locale rather than a joined string**, on the modifiers row's rule: the
    /// separator between two items is not a comma in every language. The **narrow** width is what
    /// makes it a sequence rather than a conjunction — three sets are three sets, not two sets *and*
    /// a third.
    ///
    /// - Parameter performance: The previous session's performance.
    /// - Returns: The line.
    private func summary(of performance: PreviousPerformance) -> String {
        performance.workingSets
            .map {
                String(
                    localized: LoggingStrings.sessionPreviousSet(
                        weight: AppFormat.weight(
                            WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale
                        ).format($0.weight),
                        reps: $0.reps.formatted(AppFormat.count(locale: locale))
                    ))
            }
            .formatted(.list(type: .and, width: .narrow).locale(locale))
    }
}
