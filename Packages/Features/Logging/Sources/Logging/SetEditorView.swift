import DesignSystem
import Localization
import PowerliftingCore
import SwiftUI

/// Which exercise the set editor is open over, and what it opened filled in with.
///
/// **Identified by the entry rather than by the set being drafted**, because that is what makes the
/// sheet re-present when the user closes it and taps another card: two drafts against one exercise
/// are the same sheet, two exercises are two.
struct SetEditorTarget: Identifiable, Equatable {
    /// The exercise to log against.
    let entryID: UUID

    /// The set to copy in, for `FR-1.2.6`'s duplicate — `nil` for a blank one.
    let repeating: SetEntryValues?

    /// The entry's id: see the type's note.
    var id: UUID { entryID }
}

/// `FR-1.2.3`'s add-set form, and `FR-1.2.6`'s duplicate once it has been opened.
///
/// **Presented rather than drawn inside the card, and that is `NFR-1.4` deciding it.** Every logging
/// control has to sit in the lower two-thirds of the screen, reachable by one thumb; a draft row
/// inside the card would sit wherever the user had scrolled that card to, which is as often the top
/// as the bottom. A sheet at the medium detent is the lower half of the screen by construction, and
/// it is the same place for every exercise in the workout. The larger detent is offered as well
/// rather than instead, because at `accessibility3` the four fields no longer fit the medium one and
/// a control that cannot be scrolled to is worse than one that is briefly higher up.
///
/// **Three taps, counted rather than assumed** (`NFR-1.3`): **Repeat set** opens this already filled
/// in, one **+** moves the field being adjusted, **Log set** stores it. Which is why the ± controls
/// exist at all — an adjustment made through the keyboard is a tap to focus, a tap to clear and as
/// many more as the number is long.
///
/// Taking a draft and two closures rather than the store, so the form is picturable without one.
struct SetEditorSheet: View {
    /// What the user has entered so far.
    @State private var draft: SetDraft

    /// Whether anything has been entered, so a form opened blank does not open complaining.
    ///
    /// **Seeded from ``SetDraft/isBlank`` and not from whether the draft resolves.** A duplicate of
    /// a set whose stored rating is out of range arrives here invalid through no keystroke of the
    /// user's; seeded the other way it opened on a disabled command with nothing saying why.
    @State private var hasInput: Bool

    /// Logs the set. The caller is what knows which exercise it belongs to.
    let log: (SetDraft) -> Void

    /// Leaves without logging anything.
    let cancel: () -> Void

    /// Builds the form over a draft.
    ///
    /// - Parameters:
    ///   - draft: What the form opens holding — blank, or `FR-1.2.6`'s copy of the last set.
    ///   - log: Logs the set.
    ///   - cancel: Closes the form.
    init(draft: SetDraft, log: @escaping (SetDraft) -> Void, cancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        _hasInput = State(initialValue: !draft.isBlank)
        self.log = log
        self.cancel = cancel
    }

    /// The four fields, scrolling, with the two commands pinned beneath them.
    ///
    /// **The commands are outside the scroll view, and that is measured rather than assumed.** With
    /// them inside it, **Log set** sat below the fold at the medium detent — `NFR-1.3`'s third tap
    /// cost a scroll first, which is the one thing the three-tap count cannot afford. Pinned, the
    /// command is in the same place at either detent and at every Dynamic Type size, which is also
    /// what `NFR-1.4` asks for: the control the thumb reaches for does not move.
    var body: some View {
        VStack(spacing: Spacing.sm.points) {
            ScrollView {
                SetEditorFields(draft: $draft, hasInput: $hasInput)
                    .padding(Spacing.lg.points)
            }
            SetEditorCommands(
                isLoggable: draft.isLoggable,
                showsRefusal: !draft.isLoggable && hasInput,
                log: { log(draft) },
                cancel: cancel
            )
        }
        .background(ColorToken.background)
    }
}

/// The set editor's four fields (`FR-1.2.3`).
///
/// **A type of its own so a reference can be taken of it**, which is `TR-1.12` rather than
/// decomposition for its own sake: `ImageRenderer` lays a `ScrollView`'s content out and draws none
/// of it, so a snapshot of the sheet is a picture of the divider and the two commands with the whole
/// form missing. Rendered directly, the fields are a picture again — and `NFR-1.10`'s claim that
/// they still fit at `accessibility3` is something the gate can actually check.
///
/// The two fields that decide whether the set logs lead, and the two optional ones follow: at the
/// medium detent the load and the repetitions are what is on screen without scrolling.
struct SetEditorFields: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// Set by anything the user does here, so the commands below know the form has been touched.
    @Binding var hasInput: Bool

    /// Title, then the four rows.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            Text(LoggingStrings.setEditorTitle)
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
            weightField
            repsField
            rpeField
            notesField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The load, its unit, and the ± pair that steps it by `G-3.3`'s display increment.
    private var weightField: some View {
        FieldRow(label: Text(LoggingStrings.setWeightLabel), hint: nil) {
            HStack(spacing: Spacing.sm.points) {
                stepButton(symbolName: "minus", label: LoggingStrings.setWeightDecrease) {
                    draft = draft.adjustingWeight(by: -1)
                }
                numberField(text: $draft.weightText, label: LoggingStrings.setWeightLabel)
                Text(LoggingStrings.setUnitSymbol(for: draft.unit))
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textSecondary)
                stepButton(symbolName: "plus", label: LoggingStrings.setWeightIncrease) {
                    draft = draft.adjustingWeight(by: 1)
                }
            }
        }
    }

    /// The repetitions, and the ± pair that steps them one at a time.
    private var repsField: some View {
        FieldRow(label: Text(LoggingStrings.setRepsLabel), hint: nil) {
            HStack(spacing: Spacing.sm.points) {
                stepButton(symbolName: "minus", label: LoggingStrings.setRepsDecrease) {
                    draft = draft.adjustingReps(by: -1)
                }
                numberField(text: $draft.repsText, label: LoggingStrings.setRepsLabel)
                stepButton(symbolName: "plus", label: LoggingStrings.setRepsIncrease) {
                    draft = draft.adjustingReps(by: 1)
                }
            }
        }
    }

    /// The rating, with no ± pair: it is optional, and a control that filled it in by being tapped
    /// would put a number where the user meant to leave none.
    private var rpeField: some View {
        FieldRow(label: Text(LoggingStrings.setRPELabel), hint: Text(LoggingStrings.setRPEHint)) {
            numberField(text: $draft.rpeText, label: LoggingStrings.setRPELabel)
        }
    }

    /// The per-set note (`FR-1.2.3`).
    private var notesField: some View {
        FieldRow(label: Text(LoggingStrings.setNotesLabel), hint: Text(LoggingStrings.setNotesHint)) {
            TextField(text: $draft.notes) { Text(LoggingStrings.setNotesLabel) }
                .textFieldStyle(.plain)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .padding(.horizontal, Spacing.md.points)
                .background(
                    ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
                )
                .onChange(of: draft.notes) { hasInput = true }
        }
    }

    /// One numeric field, at the logging touch target rather than the standard one (`G-4.3`).
    private func numberField(text: Binding<String>, label: LocalizedStringResource) -> some View {
        TextField(text: text) { Text(label) }
            .textFieldStyle(.plain)
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .decimalKeyboard()
            .accessibilityLabel(Text(label))
            .onChange(of: text.wrappedValue) { hasInput = true }
    }

    /// One of the four ± controls.
    ///
    /// **60pt square, which is `G-4.3`'s logging target and not the 44pt floor** — these are the
    /// controls `NFR-1.3`'s three taps are counted through, operated one-handed with the phone at
    /// arm's length.
    private func stepButton(
        symbolName: String, label: LocalizedStringResource, action: @escaping () -> Void
    ) -> some View {
        Button {
            hasInput = true
            action()
        } label: {
            Image(systemName: symbolName)
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(width: TouchTarget.logging.points, height: TouchTarget.logging.points)
                .background(
                    ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// **Log set**, the way out, and the refusal that explains a disabled command.
///
/// **Pinned outside the scroll view**, which is what keeps `NFR-1.3`'s third tap from costing a
/// scroll first, and its own type for ``SetEditorFields``' reason.
///
/// The confirming command is disabled rather than absent while the draft does not resolve: a button
/// that vanished would move **Cancel** under the thumb that was reaching for it.
struct SetEditorCommands: View {
    /// Whether the draft resolves — whether **Log set** goes.
    let isLoggable: Bool

    /// Whether to say why it does not. Separate from ``isLoggable`` because a form nobody has
    /// filled in yet is not one to complain about.
    let showsRefusal: Bool

    /// Logs the set.
    let log: () -> Void

    /// Leaves without logging anything.
    let cancel: () -> Void

    /// The rule, the refusal where there is one, then the two commands.
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
                    Text(LoggingStrings.setConfirmAction)
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
            }
            .padding(.horizontal, Spacing.lg.points)
        }
        .padding(.bottom, Spacing.lg.points)
        .background(ColorToken.background)
    }
}

/// Why the confirming command is refusing, pinned beside it.
///
/// **Not `ErrorStateView`, and that is the one place this screen departs from T-1.09's components.**
/// A form that has not been filled in is not one of `FR-1.13.1`'s states — nothing failed, nothing
/// is being retried, and the fields and keystrokes are all still there. Rendered as the state
/// component it takes the whole pinned footer: a full-width symbol, a headline and a message,
/// squeezing the fields off a medium sheet and truncating its own copy at `accessibility3`.
/// Measured in the simulator. What this is instead is the same shape as the field hints above it,
/// in the negative colour, with a symbol so the colour is never the only cue (`G-4.5`).
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

/// A labelled row in the set editor — the label, the control, and the one line of guidance a label
/// has no room for.
///
/// A shape of its own so the four fields are laid out by one rule rather than four.
struct FieldRow<Content: View>: View {
    /// What the field is.
    let label: Text

    /// What it accepts, where that is not obvious. Optional.
    let hint: Text?

    /// The control itself.
    @ViewBuilder let content: Content

    /// Label, control, hint.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            label
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            content
            if let hint {
                hint
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
    }
}

extension View {
    /// The decimal keyboard, where the platform has one.
    ///
    /// **A modifier rather than an `#if` at four call sites.** `keyboardType(_:)` does not exist on
    /// macOS, and this module builds for both — the package's `platforms:` clause names each.
    func decimalKeyboard() -> some View {
        #if os(iOS)
            return keyboardType(.decimalPad)
        #else
            return self
        #endif
    }
}
