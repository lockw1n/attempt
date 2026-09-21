import DesignSystem
import DesignTokens
import Localization
import PowerliftingCore
import SwiftUI

/// A free workout's set form (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.8`, `OUT-17.8`).
///
/// **A checklist row's form is ``SetEditorRowFields``, which was this type's other branch.** That
/// one draws a section per planned group (`FR-18.6.2`); this one collects one set and grows no
/// sections (`OUT-18.9`). Split rather than widened, which is what makes `OUT-18.6`'s "the free
/// workout is untouched" a property of the type rather than a claim about a diff.
///
/// **A type of its own so a reference can be taken of it**, which is `TR-1.12` rather than
/// decomposition for its own sake: `ImageRenderer` lays a `ScrollView`'s content out and draws none
/// of it, so a snapshot of the sheet is a picture of the divider and the commands with the whole
/// form missing. Rendered directly, the fields are a picture again.
///
/// **The head is a type of its own for a second reason** — ``SetEditorHead`` is what `FR-17.1.6`'s
/// budget is measured over, and a claim about where Weight and Reps fall has to be measured on the
/// thing the sheet actually draws.
struct SetEditorFields: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// Which form is drawn.
    var mode: SetEditorMode = .set(isEditing: false)

    /// The modifier terms on offer (`FR-1.2.8`).
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on.
    let equipment: PlateCalculatorStore

    /// Whether `FR-1.2.8`'s picker is on screen.
    ///
    /// The row's own, so it cannot outlive the sheet it was raised from — `SetEditorCommands`'
    /// confirmation's rule.
    @State private var isPicking = false

    /// The head, then whatever the mode adds under it.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            SetEditorHead(draft: $draft, mode: mode, equipment: equipment)
            warmupField
            rpeField
            modifiersField
            notesField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isPicking) {
            SetModifierPicker(
                applied: $draft.modifiers,
                vocabulary: vocabulary,
                dismiss: { isPicking = false }
            )
        }
    }

    /// `FR-1.2.8`'s modifiers — a summary of what is applied, and the way into the picker.
    ///
    /// **One row that opens a sheet, rather than the nine-plus controls the choice actually is.**
    /// The form is at `NFR-1.10`'s ceiling with the rows it already has; a wrapping grid of chips
    /// would be the tallest thing on it and would grow with the user's own list, which has no
    /// ceiling at all.
    ///
    /// The summary is a list in the user's locale (`G-3.4`) — the separator between two modifiers is
    /// not a comma in every language.
    private var modifiersField: some View {
        FieldRow(
            label: Text(LoggingStrings.setModifierLabel),
            hint: Text(LoggingStrings.setModifierHint)
        ) {
            Button {
                isPicking = true
            } label: {
                HStack(spacing: Spacing.sm.points) {
                    summary
                    Spacer(minLength: Spacing.sm.points)
                    Image(systemName: "chevron.right")
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .padding(.horizontal, Spacing.md.points)
                .background(
                    ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(LoggingStrings.setModifierLabel))
            // The summary as a *value* and not as the label (`G-4.2`): combining the children builds
            // one from them, and the label below replaces it — so what is applied, which this row is
            // the only place on the form to see, would be announced nowhere.
            .accessibilityValue(Text(verbatim: summaryValue))
        }
    }

    /// What the row says: the applied modifiers as a list in the user's locale, or that there are
    /// none.
    ///
    /// A string rather than a `Text`, because the row announces it as well as drawing it.
    private var summaryValue: String {
        SetModifierSummary.rendered(draft.modifiers, locale: draft.locale)
    }

    /// The summary, drawn — quiet where there is nothing applied.
    @ViewBuilder private var summary: some View {
        if draft.modifiers.isEmpty {
            Text(LoggingStrings.setModifierNone)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textTertiary)
        } else {
            Text(verbatim: summaryValue)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Whether the set is a warmup (`FR-1.2.4`).
    ///
    /// **A `Toggle`, because the value is a boolean and that is the only control VoiceOver announces
    /// as one** — but drawn as a button rather than as a switch, and that is measured rather than
    /// stylistic. A switch is UIKit-backed, and inside a sheet held at the `.medium` detent it never
    /// received the tap: the sheet's own drag recogniser claimed it. `.toggleStyle(.button)` keeps
    /// the toggle semantics and drops the UIKit view, which fixes the tap and, incidentally, is the
    /// one thing that lets `TR-1.12`'s harness picture the control at all.
    ///
    /// **Not a `FieldRow`, and that is measured too.** Every other row here is a label above a
    /// control, which for a boolean means the label twice over and two rows' worth of height.
    ///
    /// **A symbol as well as the fill** (`G-4.5`): on and off must not differ by colour alone.
    private var warmupField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            WarmupToggle(isWarmup: $draft.isWarmup, label: LoggingStrings.setWarmupLabel)
            Text(LoggingStrings.setWarmupHint)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
        }
    }

    /// The rating, with no ± pair: it is optional, and a control that filled it in by being tapped
    /// would put a number where the user meant to leave none.
    private var rpeField: some View {
        FieldRow(label: Text(LoggingStrings.setRPELabel), hint: Text(LoggingStrings.setRPEHint)) {
            SetEditorControls.numberField(
                text: $draft.rpeText, label: LoggingStrings.setRPELabel)
        }
    }

    /// The per-set note (`FR-1.2.3`).
    private var notesField: some View {
        FieldRow(label: Text(LoggingStrings.setNotesLabel), hint: Text(LoggingStrings.setNotesHint)) {
            SetEditorControls.textField(text: $draft.notes, label: LoggingStrings.setNotesLabel)
        }
    }
}

/// `FR-1.4.1`'s per-side loading for the weight the form holds, and the way into the whole answer.
///
/// **Drawn only once that load parses** — a row over a blank field would be a control that starts
/// dead on every new set.
///
/// **Where it sits is the sheet's mode, and that was measured** (`FR-17.1.6`). On a free workout it
/// stays directly under the load it describes, which is where its argument put it: that form opens
/// blank, so the row appears as the lifter types and pushes nothing off a screen they were reading.
/// On a checklist row the form opens **prefilled from the plan**, so the row is there on every
/// single open and its 85 pt land between Weight and Reps — the two fields `FR-17.1.6` says must
/// open together. The load it describes is then three rows up and still on screen, which is the
/// whole of what "directly under" was buying.
///
/// **Its own type so it can be drawn from either place**, and so the calculator's presentation
/// travels with it: two `.sheet(isPresented:)` on one view is one presentation with the other
/// silently ignored, so each row carries its own.
struct SetEditorPlateRow: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// The gym the loading is worked out on.
    let equipment: PlateCalculatorStore

    /// Whether `FR-1.4.1`'s calculator is on screen. The row's own, so it cannot outlive the sheet.
    @State private var isCalculating = false

    @ViewBuilder var body: some View {
        if let target = draft.weight {
            PlateLoadingRow(
                target: target,
                result: equipment.loading(for: target),
                // The same resolver the calculator's own screen reads (`FR-16.6.5`): the row and the
                // sheet it opens must not disagree about whether there is a gym.
                state: PlateEquipmentState.current(
                    hasLoaded: equipment.hasLoaded,
                    hasEquipment: equipment.equipment != nil,
                    failure: equipment.failure
                ),
                unit: draft.unit,
                open: { isCalculating = true }
            )
            .sheet(isPresented: $isCalculating) {
                PlateCalculatorSheet(
                    target: target,
                    store: equipment,
                    unit: draft.unit,
                    dismiss: { isCalculating = false }
                )
            }
        }
    }
}

/// The controls the sheet's fields are built from, in one place.
///
/// **Shared rather than duplicated, because the per-set fold multiplies them** (`FR-17.9.4`): a
/// second `numberField` written beside the detail rows is a second place `G-4.3`'s logging touch
/// target and `decimalKeyboard()` can drift from this one.
enum SetEditorControls {
    /// One numeric field, at the logging touch target rather than the standard one (`G-4.3`).
    ///
    /// **The selection binding is here rather than on a second field type** (`FR-18.6.1`): only the
    /// load is opened with its contents selected, and a numeric field declared twice is a second
    /// place `decimalKeyboard()` and the logging touch target can drift apart — which is the reason
    /// this enum exists at all. A caller with no selection of its own passes none, and the field
    /// then manages its own, exactly as the initializer without one does.
    ///
    /// - Parameters:
    ///   - text: What it edits.
    ///   - selection: Where the caret or the selected range sits. Omitted, the field decides.
    ///   - label: What it is called, drawn as the placeholder and announced.
    /// - Returns: The field.
    static func numberField(
        text: Binding<String>,
        selection: Binding<TextSelection?> = .constant(nil),
        label: LocalizedStringResource
    ) -> some View {
        TextField(text: text, selection: selection) { Text(label) }
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
    }

    /// One prose field.
    ///
    /// - Parameters:
    ///   - text: What it edits.
    ///   - label: What it is called.
    /// - Returns: The field.
    static func textField(text: Binding<String>, label: LocalizedStringResource) -> some View {
        TextField(text: text) { Text(label) }
            .textFieldStyle(.plain)
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .padding(.horizontal, Spacing.md.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
    }

    /// One of the ± controls.
    ///
    /// **60pt square, which is `G-4.3`'s logging target and not the 44pt floor** — these are the
    /// controls `NFR-1.3`'s three taps are counted through, operated one-handed with the phone at
    /// arm's length.
    ///
    /// - Parameters:
    ///   - symbolName: The glyph.
    ///   - label: What it is announced as — never the drawn form (T-16.01).
    ///   - action: What it does.
    /// - Returns: The control.
    static func stepButton(
        symbolName: String, label: LocalizedStringResource, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
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

/// `FR-1.2.4`'s marking, drawn the one way that survives both the medium detent and the renderer.
///
/// Shared for ``SetEditorControls``' reason: the per-set fold draws one of these per set.
struct WarmupToggle: View {
    /// Whether the set is a warmup.
    @Binding var isWarmup: Bool

    /// What it is called.
    let label: LocalizedStringResource

    var body: some View {
        Toggle(isOn: $isWarmup) {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: isWarmup ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(label)
                    .font(Typography.actionLabel.font)
                Spacer(minLength: Spacing.sm.points)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .contentShape(.rect)
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(isWarmup ? ColorToken.brandAccent : ColorToken.textPrimary)
        .background(ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points))
    }
}

/// The applied modifiers, as the lifter reads them (`FR-1.2.8`, `G-3.4`).
///
/// Off the view so the fold's rows and the form's own row cannot disagree about the separator.
enum SetModifierSummary {
    /// The list, or the word for none.
    ///
    /// - Parameters:
    ///   - modifiers: What is applied.
    ///   - locale: Whose list separator is used.
    /// - Returns: The summary.
    static func rendered(_ modifiers: [SetModifier], locale: Locale) -> String {
        modifiers.isEmpty
            ? String(localized: LoggingStrings.setModifierNone)
            : modifiers.map(\.displayName).formatted(.list(type: .and).locale(locale))
    }
}
