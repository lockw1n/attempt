import DesignSystem
import Localization
import SwiftUI

/// The set editor's pinned footer: the confirming command, the way out, `FR-1.2.7`'s deletion, and
/// the refusal that explains a disabled command.
///
/// **Pinned outside the scroll view**, which is what keeps `NFR-1.3`'s third tap from costing a
/// scroll first, and its own type for ``SetEditorFields``' reason.
///
/// The confirming command is disabled rather than absent while the draft does not resolve: a button
/// that vanished would move **Cancel** under the thumb that was reaching for it.
struct SetEditorCommands: View {
    /// Whether the draft resolves — whether the confirming command goes.
    let isLoggable: Bool

    /// Whether to say why it does not. Separate from ``isLoggable`` because a form nobody has
    /// filled in yet is not one to complain about.
    let showsRefusal: Bool

    /// Whether the form is editing a logged set rather than adding one (`FR-1.2.7`) — what decides
    /// the confirming command's words and whether the deletion is offered.
    let isEditing: Bool

    /// Logs the set, or saves the edit.
    let log: () -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// Soft-deletes the set being edited (`FR-1.2.7`, `G-1.3`). Never called while adding one.
    let delete: () -> Void

    /// Whether the deletion's confirmation is on screen.
    ///
    /// Held here rather than on the screen presenting the sheet, unlike `FR-1.2.12`'s: this dialogue
    /// belongs to a control in this footer and must not outlive the sheet it was raised from.
    @State private var isConfirmingDelete = false

    /// The rule, the refusal where there is one, then the commands.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            // A rule above the pinned commands, because the fields scroll behind them: without it
            // the last field on screen reads as clipped rather than as scrolled.
            Divider().overlay(ColorToken.separator)
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                if showsRefusal {
                    FieldRefusal(message: Text(LoggingStrings.setInvalidMessage))
                }
                Button(action: log) {
                    Text(
                        isEditing
                            ? LoggingStrings.setSaveAction
                            : LoggingStrings.setConfirmAction
                    )
                }
                .buttonStyle(.primaryAction(.fill))
                .disabled(!isLoggable)

                Button(action: cancel) {
                    Text(LoggingStrings.setCancelAction)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                }
                .buttonStyle(.plain)

                if isEditing {
                    deleteCommand
                }
            }
            .padding(.horizontal, Spacing.lg.points)
        }
        .padding(.bottom, Spacing.lg.points)
        .background(ColorToken.background)
        .confirmationDialog(
            Text(LoggingStrings.setDeleteConfirmTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: delete) {
                Text(LoggingStrings.setDeleteConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.setDeleteConfirmCancel)
            }
        } message: {
            Text(LoggingStrings.setDeleteConfirmMessage)
        }
    }

    /// `FR-1.2.7`'s deletion, last and behind a confirmation.
    ///
    /// **Last, with the way out between it and the confirming command.** The two commands a thumb
    /// reaches for are one destructive tap apart otherwise, and this is a sheet operated one-handed
    /// mid-workout — `NFR-1.4` puts every control in that thumb's reach, which cuts both ways.
    ///
    /// **Confirmed, though no requirement asks.** The deletion is soft (`G-1.3`) and nothing in
    /// Phase 1 can undo one: the row survives in the store and no screen will ever show it again.
    /// A mis-tap would silently cost a logged set, which is the direction `G-1.6` cares about.
    ///
    /// **A glyph as well as the colour** (`G-4.5`): destructive must not be carried by the tint
    /// alone.
    private var deleteCommand: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text(LoggingStrings.setDeleteAction)
            }
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.negative)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// Why the confirming command is refusing, pinned beside it.
///
/// **Not `ErrorStateView`, and that is the one place this screen departs from the shared state
/// components.** A form that has not been filled in is not one of `FR-1.13.1`'s states — nothing
/// failed, nothing is being retried, and the fields and keystrokes are all still there. Rendered as
/// the state component it takes the whole pinned footer: a full-width symbol, a headline and a
/// message, squeezing the fields off a medium sheet and truncating its own copy at
/// `accessibility3`. Measured in the simulator. What this is instead is the same shape as the field
/// hints above it, in the negative colour, with a symbol so the colour is never the only cue
/// (`G-4.5`).
///
/// **Pinned with the command rather than under the field that is wrong**, and that is measured too:
/// inside the scroll view it left the disabled button on screen with its explanation scrolled away
/// — at `accessibility3`, where the fields no longer fit, that is the normal case rather than the
/// edge one.
struct FieldRefusal: View {
    /// What the form wants, in the user's words — never a diagnostic (`G-3.4`).
    let message: Text

    /// The symbol, then the sentence, as one VoiceOver element.
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs.points) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Typography.caption.font)
                .accessibilityHidden(true)
            message
                .font(Typography.caption.font)
                // Wraps rather than truncates: inside a pinned footer a `Text` is given the height
                // it asks for only if it says so, and at `accessibility3` one line holds four
                // words.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(ColorToken.negative)
        .accessibilityElement(children: .combine)
    }
}
