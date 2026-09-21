import DesignSystem
import DesignTokens
import Localization
import PowerliftingCore
import SwiftUI

/// Everything `FR-17.1.6` says opens above the fold: the heading, **Weight** and **Reps**.
///
/// **Its own type because that requirement is a measurement rather than a picture**, and the
/// measurement has to be taken over the thing the sheet draws rather than over a stack rebuilt in a
/// test (T-16.17). It holds exactly what the requirement names and nothing else — so the assertion
/// in `LogSheetSnapshotTests` is the requirement rather than a proxy for it, and a field added here
/// later has to be argued against the budget rather than silently pushing Reps under the commands.
///
/// **Sets and the plate row are deliberately outside it.** Measured at the default type size: the
/// heading, Weight, its plate row, Reps and Sets came to 447 pt, which with the pinned commands is
/// 648.5 pt — inside the 667 pt of the smallest device the app supports only by the width of the
/// status bar, and over it the moment anything wraps. `FR-17.1.6` asks for Weight and Reps, and the
/// two rows that scroll are the two it does not name.
struct SetEditorHead: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// Which form is drawn.
    let mode: SetEditorMode

    /// The gym `FR-1.4.1`'s loading is worked out on.
    let equipment: PlateCalculatorStore

    /// The group this section names, or `nil` on a sheet that draws one (`FR-18.6.2`).
    ///
    /// Drawn above Weight and marked as a heading, so VoiceOver reads which group it is before the
    /// three fields it governs.
    var sectionTitle: LocalizedStringResource?

    /// Whether this is the section the sheet leads with.
    ///
    /// **It decides three things and they belong together**: the sheet's own heading is drawn
    /// above this section and no other, this is the Weight that takes the keyboard when the sheet
    /// opens (`FR-18.6.1`), and this is the section that reads the gym. A second section that ran
    /// the first would move the heading into the middle of the form; one that ran the second would
    /// take the keyboard off the first; one that ran the third would re-read the same plates once
    /// per planned group.
    ///
    /// **It decides nothing about the selection, and that is the half worth stating.** Every
    /// section's load is prefilled and every section's load can be tapped into, so
    /// ``SetEditorFocus``' three answers — select the whole of it the first time, leave the caret
    /// alone afterwards, let go of the range at every blur — are the same rules here as there.
    /// Gating them on this flag would leave sections after the first holding a range the field
    /// wrote back, across a blur, into a value nothing pins.
    var isFirstSection = true

    /// Whether the load's field holds the keyboard (`FR-18.6.1`).
    ///
    /// **Taken on appearance, so the sheet opens on the number the lifter came to change.** The
    /// flow that reaches this form has already named the exercise — the tester's complaint was that
    /// the load then cost a tap of its own before a digit could be typed.
    ///
    /// **The heading loses the first announcement to this, and that is accepted rather than
    /// unnoticed.** Taking focus moves the accessibility cursor to Weight, and the sheet carries no
    /// navigation title, so the heading below is the only name it has. Moving the cursor back is a
    /// mechanism nothing in this project can measure — VoiceOver does not enable from a `simctl`
    /// preference write and the simulator's own inspector answers *not available* — and an
    /// accessibility mechanism inferred rather than measured is worse than a stated refusal.
    /// `FR-18.6.1` asks for the focus; `G-4.1`'s announcement wants a device with VoiceOver on.
    @FocusState private var isEnteringWeight: Bool

    /// What is selected in the load's field.
    ///
    /// **Its own state because the whole value is selected on open, and only on open.** The field
    /// arrives prefilled from the plan (`FR-17.1.1`), so a caret parked at one end turns the first
    /// digit typed into `575` rather than `5` — worse than no focus at all. Tapping back into the
    /// field later is not an open, and iOS's own caret placement stands.
    ///
    /// **It is held only while the field holds the keyboard, and that is load-bearing rather than
    /// tidy.** The value here is a pair of indices into whatever the field said when they were
    /// taken; both the blur and the ± pair can leave them naming a string that no longer exists.
    @State private var weightSelection: TextSelection?

    /// Whether the load has already been offered to the lifter whole.
    ///
    /// **What separates the open from every later tap**, which the focus state cannot do on its
    /// own: a field regains focus whenever it is tapped, and re-selecting the whole load there
    /// would take the caret away from someone who had aimed it at a digit.
    @State private var hasSelectedOnOpen = false

    /// The heading, the question where there is one, and the fields that decide what is written.
    ///
    /// **One head per section, and ``isFirstSection`` is what says which of them opens focused**
    /// (`FR-18.6.2`, `FR-18.6.1`). Everything else here is the section's own.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if isFirstSection { heading }
            if let sectionTitle { sectionHeading(sectionTitle) }
            weightField
            // A free workout keeps today's order — the plate row directly under the load it
            // describes (`OUT-17.8`). A checklist row moves it below, into the scrolling fields.
            if !mode.isRow {
                SetEditorPlateRow(draft: $draft, equipment: equipment)
            }
            repsField
            if mode.offersSetCount { setsField }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read here rather than in the row below it, so one read answers a weight the user steps
        // through with the ± pair — and so the row does not re-read every time the field empties.
        .task { if isFirstSection { await equipment.load() } }
        .onAppear { if isFirstSection { isEnteringWeight = true } }
        // Not gated on `isFirstSection`: only the *opening* focus is the first section's, and the
        // selection rule is every section's — see that property.
        .onChange(of: isEnteringWeight) { applyTheFocusChange() }
    }

    /// `FR-18.6.1`: the load, once it holds the keyboard, offers what it already says as a whole.
    ///
    /// **Written after the focus arrives rather than beside it, and that is measured.** Set in the
    /// same `onAppear` that takes the focus, the selection is discarded — the field places its own
    /// caret as it becomes first responder, and what it places it over is the end of the value. So
    /// the order is focus, then selection, and this is what the focus arriving calls.
    ///
    /// Both rules it applies are ``SetEditorFocus``'; what is here is the assignment.
    private func applyTheFocusChange() {
        let change = SetEditorFocus.onFocusChange(
            isFocused: isEnteringWeight, hasOpened: hasSelectedOnOpen)
        switch change {
        case .selectAll:
            hasSelectedOnOpen = true
            weightSelection = SetEditorFocus.selectionOnOpen(of: draft.weightText)
        case .clear:
            weightSelection = nil
        case .leave:
            break
        }
    }

    /// Steps the load by `G-3.3`'s display increment, letting go of anything selected in it first.
    ///
    /// **The stepped value is a freshly rendered string, and a range into the old one names
    /// nothing** — `102,5` stepped down is `100`, three characters under a range that named five.
    /// The keyboard does not move when the ± pair is tapped, so no focus change clears it; this is
    /// the one other place the load's text is replaced wholesale, and the plate calculator is not a
    /// third because it reads the load rather than writing it.
    ///
    /// - Parameter steps: How many increments to move — negative is down.
    private func stepWeight(by steps: Int) {
        weightSelection = nil
        draft = draft.adjustingWeight(by: steps)
    }

    /// The group's name, above its fields (`FR-18.6.2`).
    ///
    /// - Parameter title: Which group this section is.
    /// - Returns: The heading.
    private func sectionHeading(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    /// One word, and on a checklist row the question the sheet is asking (`FR-17.1.6`).
    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(mode.heading)
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
            if mode.isRow {
                Text(LoggingStrings.setEditorQuestion)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// The load, its unit, and the ± pair that steps it by `G-3.3`'s display increment.
    private var weightField: some View {
        FieldRow(label: Text(LoggingStrings.setWeightLabel), hint: nil) {
            HStack(spacing: Spacing.sm.points) {
                SetEditorControls.stepButton(
                    symbolName: "minus", label: LoggingStrings.setWeightDecrease
                ) {
                    stepWeight(by: -1)
                }
                SetEditorControls.numberField(
                    text: $draft.weightText,
                    selection: $weightSelection,
                    label: LoggingStrings.setWeightLabel
                )
                .focused($isEnteringWeight)
                Text(LoggingStrings.setUnitSymbol(for: draft.unit))
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textSecondary)
                SetEditorControls.stepButton(
                    symbolName: "plus", label: LoggingStrings.setWeightIncrease
                ) {
                    stepWeight(by: 1)
                }
            }
        }
    }

    /// The repetitions, and the ± pair that steps them one at a time.
    private var repsField: some View {
        FieldRow(label: Text(LoggingStrings.setRepsLabel), hint: nil) {
            HStack(spacing: Spacing.sm.points) {
                SetEditorControls.stepButton(
                    symbolName: "minus", label: LoggingStrings.setRepsDecrease
                ) {
                    draft = draft.adjustingReps(by: -1)
                }
                SetEditorControls.numberField(
                    text: $draft.repsText, label: LoggingStrings.setRepsLabel)
                SetEditorControls.stepButton(
                    symbolName: "plus", label: LoggingStrings.setRepsIncrease
                ) {
                    draft = draft.adjustingReps(by: 1)
                }
            }
        }
    }

    /// How many sets of it (`FR-17.1.1`), floored at one by its ± pair.
    private var setsField: some View {
        FieldRow(label: Text(LoggingStrings.setSetsLabel), hint: nil) {
            HStack(spacing: Spacing.sm.points) {
                SetEditorControls.stepButton(
                    symbolName: "minus", label: LoggingStrings.setSetsDecrease
                ) {
                    draft = draft.adjustingSets(by: -1)
                }
                SetEditorControls.numberField(
                    text: $draft.setsText, label: LoggingStrings.setSetsLabel)
                SetEditorControls.stepButton(
                    symbolName: "plus", label: LoggingStrings.setSetsIncrease
                ) {
                    draft = draft.adjustingSets(by: 1)
                }
            }
        }
    }
}
