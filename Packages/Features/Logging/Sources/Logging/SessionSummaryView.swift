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

/// `FR-1.2.9`'s session note — prose about the workout, not about one set.
///
/// **Under the workout's own facts and above its exercises**, because that is what it is about: the
/// day, how it felt, what to remember. The per-set note (`FR-1.2.3`) stays where it is, on the set
/// editor.
///
/// **The commands appear only once the field is dirty**, on the exercise detail screen's rule: a
/// workout the user is only logging into carries no buttons here, and an unsaved edit is therefore
/// visible as one.
///
/// Taking a binding and closures rather than the store, for ``SessionSummarySection``'s reason.
struct SessionNotesSection: View {
    /// The field, and what it is being compared against.
    @Binding var draft: SessionNoteDraft

    /// Whether the last attempt to store it failed. The typed text stays on screen either way, so
    /// the retry is another tap at the same command.
    let hasFailed: Bool

    /// Stores what the field holds.
    let save: () -> Void

    /// The field, the two commands once there is something to commit, and a failed write beneath.
    ///
    /// **A `TextField(axis: .vertical)` rather than a `TextEditor`**, for the reason the exercise
    /// notes give: an editor brings its own scroll view, and inside this screen's `ScrollView` that
    /// is two scroll views arguing.
    var body: some View {
        GroupedSection(Text(LoggingStrings.sessionNotesSection)) {
            TextField(
                text: $draft.text,
                prompt: Text(LoggingStrings.sessionNotesPrompt),
                axis: .vertical
            ) {
                Text(LoggingStrings.sessionNotesSection)
            }
            .labelsHidden()
            .lineLimit(3...10)
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )

            if draft.hasUnsavedChanges {
                commands
            }

            if hasFailed {
                // **No retry of its own**, unlike the exercise detail screen's otherwise identical
                // notes section: **Save note** is directly above this and is the same command, so a
                // second button would be two ways to ask for one thing a thumb's width apart. It is
                // `SessionCommandsSection`'s rule — the retry is the command the user reached for.
                ErrorStateView(message: Text(LoggingStrings.sessionNotesError))
            }
        }
    }

    /// Save and discard, wrapping where they do not fit on one line at `NFR-1.10`'s ceiling.
    private var commands: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm.points) {
                saveButton
                discardButton
            }
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                saveButton
                discardButton
            }
        }
    }

    /// Commits the field.
    private var saveButton: some View {
        Button(action: save) {
            Text(LoggingStrings.sessionNotesSave)
        }
        .buttonStyle(.primaryAction)
    }

    /// Puts the stored note back.
    private var discardButton: some View {
        Button {
            draft.discard()
        } label: {
            Text(LoggingStrings.sessionNotesDiscard)
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
                .frame(minHeight: TouchTarget.standard.points)
        }
        .buttonStyle(.plain)
    }
}
