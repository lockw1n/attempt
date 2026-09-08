import DesignSystem
import Localization
import SwiftUI

/// Which training day a workout belongs to — `FR-1.2.1`'s backdating.
///
/// **Hosted by nothing right now.** `FR-17.8.7` took the picker off Train's root with the rest of
/// the session-shaped controls, and `FR-17.9.7` puts it in a day's overflow menu as **Change
/// date** — which is `T-17.11`'s. The view is kept rather than rewritten there.
struct WorkoutDateSection: View {
    /// The day the caller is offering to start on.
    @Binding var day: Date

    /// The picker and the sentence that says what the date is for.
    ///
    /// **Days only, and no future ones.** `FR-1.2.1` is "today, or backdate to any past date": a
    /// time of day would be a second thing to get right for a value that is a day, and a workout
    /// dated next week is a workout nobody has done.
    var body: some View {
        GroupedSection(Text(LoggingStrings.trainDateSection)) {
            DatePicker(
                selection: $day,
                in: ...Date.now,
                displayedComponents: .date
            ) {
                Text(LoggingStrings.trainDatePicker)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            Text(LoggingStrings.trainDateHint)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }
}

/// One fact about a workout: its name, then its value.
///
/// Side by side where both fit and stacked where they do not, and one VoiceOver element rather than
/// two (`G-4.2`, `NFR-1.10`) — the same shape the exercise library's fact row has, kept local
/// because a shared row is a `DesignSystem` component and neither screen has asked for one twice.
struct SessionFactRow: View {
    /// What the fact is called.
    let label: LocalizedStringResource

    /// This workout's value for it, built by the caller — a date renders through `AppFormat`, so it
    /// arrives already formatted for the locale rather than as copy.
    let value: Text

    /// The pair.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                name
                Spacer(minLength: Spacing.sm.points)
                reading
            }
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                name
                reading
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The fact's name.
    private var name: some View {
        Text(label)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
    }

    /// The fact's value.
    private var reading: some View {
        value
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
    }
}
