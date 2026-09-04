import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

// The workout's own facts, the two ways out of it, and the note folded beside them — split from
// `ActiveSessionView` for `ActiveSessionCommands`' reason: that screen is its states and what it
// pins open, and these are three pieces it composes. All three take records, bindings and closures
// rather than the store, so a reference can render them without one.

/// The workout's own facts, on one line under the title (`FR-16.6.1`).
///
/// **A line rather than a card, and the training day is not on it.** The day is in the screen's
/// title now, which is where `FR-16.6.1` puts it; what is left is the start time and — where a
/// routine prescribed anything — how much of it has been performed as prescribed. Two facts do not
/// earn a headed card above the work: the "This workout" section it replaces cost about 134 pt of
/// the first screen, and `NFR-16.3` spends that on a set row instead.
///
/// Taking the record rather than the store, for ``SessionCommandsSection``'s reason.
struct SessionSummaryLine: View {
    /// The workout being logged.
    let session: WorkoutSession

    /// How much of what a routine prescribed was performed as prescribed, or `nil` where nothing
    /// was prescribed at all (`FR-15.3.3`).
    ///
    /// **The absent case draws nothing rather than a reading of zero**, which is `FR-1.13.3`'s rule
    /// applied to a value that is undefined and not merely small: a workout started by hand has no
    /// plan to adhere to, and "0 of 0 sets" would answer a question nobody asked of it.
    let adherence: SessionAdherence?

    /// Which locale the time is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// When it started, and how much of the plan it has met — side by side where both fit.
    ///
    /// **It can render as nothing at all**, and that is the right answer rather than a hole: a
    /// workout with no start time and no plan — a restored one, logged by hand — has no fact here
    /// the title does not already carry.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.lg.points) {
                facts
            }
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                facts
            }
        }
    }

    /// The facts themselves, laid out by whichever of the two stacks fits.
    @ViewBuilder private var facts: some View {
        if let startedAt = session.startedAt {
            // The time alone: the day is in the title directly above it, so a second rendering of
            // the date here would be the same fact twice on one screen.
            fact(
                LoggingStrings.sessionStarted,
                Text(startedAt, format: AppFormat.time(locale: locale))
            )
        }
        if let adherence {
            fact(
                LoggingStrings.sessionAdherence,
                Text(
                    LoggingStrings.sessionAdherenceValue(
                        asPrescribed: adherence.asPrescribed,
                        prescribed: adherence.prescribed
                    ))
            )
        }
    }

    /// One fact: its name, then its value, as one VoiceOver element (`G-4.2`).
    ///
    /// - Parameters:
    ///   - label: What the fact is called.
    ///   - value: This workout's value for it, already formatted for the locale.
    /// - Returns: The pair.
    private func fact(_ label: LocalizedStringResource, _ value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.points) {
            Text(label)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
            value
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .accessibilityElement(children: .combine)
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
/// **Folded, at the foot, beside Finish** (`FR-16.6.1`). It was originally under the workout's own
/// facts and above the exercises, on the argument that a note is about the day rather than about
/// one lift — which is true and no longer decides it: an editor three lines tall between the top of
/// the screen and the first set row is 149 pt spent on something a lifter with chalk on their hands
/// writes once, at the end. Folded here it costs a header, and a note that exists says its first
/// line on that header so it is still readable without opening anything.
///
/// **The one thing the move could have broken, and does not.** The note's failed-write banner was
/// given a diagnostic of its own precisely so it renders beside **Save note** rather than beside
/// **Finish** at the foot of the scroll — and the foot is now where both live. They stay apart:
/// this banner is inside the fold, under the command that produced it, and
/// ``SessionCommandsSection`` draws its own under the two commands that end the workout. Two
/// containers, two sentences, and only one of them is ever open at the moment its command was
/// tapped.
///
/// **The commands appear only once the field is dirty**, on the exercise detail screen's rule: a
/// workout the user is only logging into carries no buttons here, and an unsaved edit is therefore
/// visible as one. An unsaved edit is not lost to **Finish** either — see
/// ``ActiveSessionStore/finish(saving:)``.
///
/// Taking a binding and closures rather than the store, for ``SessionSummaryLine``'s reason.
struct SessionNotesFold: View {
    /// The field, and what it is being compared against.
    @Binding var draft: SessionNoteDraft

    /// Whether the fold is open. The screen's, and stored nowhere: it is not logged data, and a
    /// workout reopened tomorrow should start folded like a fresh one.
    @Binding var isExpanded: Bool

    /// Whether the last attempt to store it failed. The typed text stays on screen either way, so
    /// the retry is another tap at the same command.
    let hasFailed: Bool

    /// Stores what the field holds.
    let save: () -> Void

    /// The header, and — once open — the field, the two commands and a failed write beneath.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                header
                if isExpanded { editor }
            }
        }
    }

    /// The heading, the note's first line where there is one, and the control that unfolds it.
    ///
    /// **The whole header is the disclosure control**, and it carries the fold as a VoiceOver
    /// *value* rather than a trait — both for the exercise card's reasons (`NFR-1.10`, `G-4.2`),
    /// and the same word pair, this being the same screen.
    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: Spacing.sm.points) {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    Text(LoggingStrings.sessionNotesSection)
                        .font(Typography.sectionHeading.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    // Only while folded: open, the field itself is directly beneath and the
                    // header would be quoting a line the user is looking at.
                    if !isExpanded, !draft.firstLine.isEmpty {
                        Text(draft.firstLine)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textSecondary)
                            .lineLimit(1)
                    }
                }
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

    /// The field itself, and what can be done with what is in it.
    @ViewBuilder private var editor: some View {
        SessionNoteEditor(draft: $draft, hasFailed: hasFailed, save: save)
    }
}

/// `FR-1.2.9`'s note field and the two commands that commit it — the part both screens that hold a
/// note draw the same way.
///
/// **Shared because the field is the same field, and its container is not.** The workout in
/// progress folds it at the foot (``SessionNotesFold``); a past session gives it a headed section
/// of its own (``SessionNotesSection``), where nothing is competing for the first screen. What is
/// inside is one thing either way, and two copies of a `3...10`-line `TextField` would be two
/// places to keep a `lineLimit` in step.
///
/// **A `TextField(axis: .vertical)` rather than a `TextEditor`**, for the reason the exercise notes
/// give: an editor brings its own scroll view, and inside either screen's `ScrollView` that is two
/// scroll views arguing.
///
/// **The commands appear only once the field is dirty**, on the exercise detail screen's rule: a
/// workout the user is only logging into carries no buttons here, and an unsaved edit is therefore
/// visible as one.
struct SessionNoteEditor: View {
    /// The field, and what it is being compared against.
    @Binding var draft: SessionNoteDraft

    /// Whether the last attempt to store it failed. The typed text stays on screen either way, so
    /// the retry is another tap at the same command.
    let hasFailed: Bool

    /// Stores what the field holds.
    let save: () -> Void

    /// The field, the two commands once there is something to commit, and a failed write beneath.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            field
            if draft.hasUnsavedChanges {
                commands
            }
            if hasFailed {
                // **No retry of its own**, unlike the exercise detail screen's otherwise identical
                // notes section: **Save note** is directly above this and is the same command, so a
                // second button would be two ways to ask for one thing a thumb's width apart. It is
                // ``SessionCommandsSection``'s rule — the retry is the command the user reached for.
                ErrorStateView(message: Text(LoggingStrings.sessionNotesError))
            }
        }
    }

    /// The field itself.
    private var field: some View {
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

/// `FR-1.2.9`'s note under a heading of its own, for a screen with room for one.
///
/// **The past session's shape, not the workout in progress's.** Nothing competes for the first
/// screen of a session that is over — there is no set to log and no **Finish** to reach — so the
/// note keeps the headed section it has always had, and ``SessionNotesFold`` is the other answer,
/// for the screen where `NFR-16.3` is spending the same space on a set row.
struct SessionNotesSection: View {
    /// The field, and what it is being compared against.
    @Binding var draft: SessionNoteDraft

    /// Whether the last attempt to store it failed.
    let hasFailed: Bool

    /// Stores what the field holds.
    let save: () -> Void

    /// The heading, then the field on a card beneath it.
    var body: some View {
        GroupedSection(Text(LoggingStrings.sessionNotesSection)) {
            SessionNoteEditor(draft: $draft, hasFailed: hasFailed, save: save)
        }
    }
}
