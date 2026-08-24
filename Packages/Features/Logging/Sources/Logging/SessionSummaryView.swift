import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

// The workout's own facts and the two ways out of it, split from `ActiveSessionView` for
// `ActiveSessionCommands`' reason: that screen is its states and what it pins open, and these are
// two sections it composes. Both take records and closures rather than the store, so a reference
// can render them without one.

/// The workout's own facts.
///
/// Taking the record rather than the store, for `SessionInProgressSection`'s reason.
struct SessionSummarySection: View {
    /// The workout being logged.
    let session: WorkoutSession

    /// Which locale the day and the time are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The training day, and when the workout was started.
    var body: some View {
        GroupedSection(Text(LoggingStrings.sessionSummarySection)) {
            SessionFactRow(
                label: LoggingStrings.sessionDay,
                value: Text(session.date, format: AppFormat.date(locale: locale))
            )
            if let startedAt = session.startedAt {
                SessionFactRow(
                    label: LoggingStrings.sessionStarted,
                    value: Text(startedAt, format: AppFormat.dateAndTime(locale: locale))
                )
            }
        }
    }
}

/// The two ways a workout ends (`FR-1.2.11`, `FR-1.2.12`).
///
/// Taking closures rather than the store, so both commands are picturable without one behind them.
///
/// **Finish is the primary action and discard is not styled as one.** They are not two options: one
/// keeps the workout and one throws it away, and a pair of matching buttons is how the second gets
/// tapped by accident. `FR-1.2.12`'s confirmation is the other half of that, and it is the caller's.
struct SessionCommandsSection: View {
    /// Whether the last write failed. The workout is unchanged when it did, so both commands still
    /// ask for the same thing and the retry is the same tap.
    let hasFailed: Bool

    /// Ends the workout and keeps it.
    let finish: () -> Void

    /// Asks whether to throw it away.
    let discard: () -> Void

    /// Both commands, and a failed write beneath them.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Button(action: finish) {
                Text(LoggingStrings.sessionFinishAction)
            }
            .buttonStyle(.primaryAction(.fill))

            Button(action: discard) {
                Text(LoggingStrings.sessionDiscardAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.negative)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            }
            .buttonStyle(.plain)

            if hasFailed {
                // The shared error component rather than a local label, and the workout stays on
                // screen beside it — a failed write costs this screen nothing.
                ErrorStateView(message: Text(LoggingStrings.sessionWriteErrorMessage))
            }
        }
    }
}
