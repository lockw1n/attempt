import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// What confirming the set editor writes — a set that does not exist yet, or a rewrite of one that
/// does (`FR-1.2.3`, `FR-1.2.7`).
///
/// **The decision is a value rather than a branch buried in the screen**, and that is what makes it
/// answerable without one: which of these two a confirmed form resolves to is the single place
/// adding and editing part company, and a regression there appends a duplicate set where the user
/// asked for a correction.
enum SetEditorWrite: Equatable {
    /// A set logged for the first time, against the exercise it belongs to.
    case add(entryID: UUID, values: SetEntryValues)

    /// A set that already exists, rewritten where it sits.
    case rewrite(setID: UUID, entryID: UUID, values: SetEntryValues)
}

/// `FR-1.2.3`'s add-set form, `FR-1.2.6`'s duplicate once it has been opened, and `FR-1.2.7`'s
/// editor over a set that already exists.
///
/// **One form for both, and the difference is three words and a command.** Adding and editing
/// collect exactly the same six fields, so a second sheet would be the same layout maintained
/// twice — what changes is the title, the confirming command's words, and a deletion offered only
/// where there is something to delete.
///
/// `FR-1.2.4`'s warmup marking is the fifth row, decided as the set is logged rather than corrected
/// afterwards — the card's own badge is what corrects one, and editing is the third way.
///
/// **Presented rather than drawn inside the card, and that is `NFR-1.4` deciding it.** Every logging
/// control has to sit in the lower two-thirds of the screen, reachable by one thumb; a draft row
/// inside the card would sit wherever the user had scrolled that card to, which is as often the top
/// as the bottom. A sheet at the medium detent is the lower half of the screen by construction, and
/// it is the same place for every exercise in the workout. The larger detent is offered as well
/// rather than instead, because at `accessibility3` the fields no longer fit the medium one and
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

    /// Whether the form is editing a logged set rather than adding one (`FR-1.2.7`).
    let isEditing: Bool

    /// What a routine prescribed for the set being logged or edited, or `nil` (`FR-15.3.1`).
    let prescribed: PlannedTargetGroup?

    /// The unit that prescription is shown in (`G-3.1`). Unused where there is none.
    let unit: MassUnit

    /// The modifier terms on offer (`FR-1.2.8`), handed down to the row that picks from them.
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on, handed down to the row that shows it.
    let equipment: PlateCalculatorStore

    /// Logs the set, or saves the edit. The caller is what knows which set or exercise it is.
    let log: (SetDraft) -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// Soft-deletes the set being edited (`FR-1.2.7`). Never called while one is being added.
    let delete: () -> Void

    /// Builds the form over a draft.
    ///
    /// - Parameters:
    ///   - draft: What the form opens holding — blank, `FR-1.2.6`'s copy of the last set, or the
    ///     set being edited.
    ///   - isEditing: Whether that set already exists.
    ///   - prescribed: What a routine planned for it, where one did (`FR-15.3.1`).
    ///   - unit: The unit that prescription is shown in.
    ///   - vocabulary: The modifier terms on offer (`FR-1.2.8`).
    ///   - equipment: The gym `FR-1.4.1`'s loading is worked out on.
    ///   - log: Logs the set, or saves the edit.
    ///   - cancel: Closes the form.
    ///   - delete: Deletes the set being edited. Ignored while one is being added.
    init(
        draft: SetDraft,
        isEditing: Bool = false,
        prescribed: PlannedTargetGroup? = nil,
        unit: MassUnit,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        log: @escaping (SetDraft) -> Void,
        cancel: @escaping () -> Void,
        delete: @escaping () -> Void = {}
    ) {
        _draft = State(initialValue: draft)
        _hasInput = State(initialValue: !draft.isBlank)
        self.isEditing = isEditing
        self.prescribed = prescribed
        self.unit = unit
        self.vocabulary = vocabulary
        self.equipment = equipment
        self.log = log
        self.cancel = cancel
        self.delete = delete
    }

    /// The fields, scrolling, with the two commands pinned beneath them.
    ///
    /// **The commands are outside the scroll view, and that is measured rather than assumed.** With
    /// them inside it, **Log set** sat below the fold at the medium detent — `NFR-1.3`'s third tap
    /// cost a scroll first, which is the one thing the three-tap count cannot afford. Pinned, the
    /// command is in the same place at either detent and at every Dynamic Type size, which is also
    /// what `NFR-1.4` asks for: the control the thumb reaches for does not move.
    var body: some View {
        VStack(spacing: Spacing.sm.points) {
            plannedTarget
            ScrollView {
                SetEditorFields(
                    draft: $draft,
                    hasInput: $hasInput,
                    isEditing: isEditing,
                    vocabulary: vocabulary,
                    equipment: equipment
                )
                .padding(Spacing.lg.points)
            }
            SetEditorCommands(
                isLoggable: draft.isLoggable,
                showsRefusal: !draft.isLoggable && hasInput,
                isEditing: isEditing,
                log: { log(draft) },
                cancel: cancel,
                delete: delete
            )
        }
        .background(ColorToken.background)
    }

    /// `FR-15.3.1`'s target, where a routine planned this set.
    ///
    /// **Above the scroll view rather than in the fields, and pinned for the commands' reason.**
    /// This sheet covers the card the target is drawn on, so without it the one moment the lifter
    /// is actually entering a number is the one moment the plan is not on screen. Inside the
    /// fields it would push the load and the repetitions below the fold at the medium detent,
    /// which is the measurement ``SetEditorFields`` is ordered around; pinned, it costs the form
    /// one line and moves nothing.
    @ViewBuilder private var plannedTarget: some View {
        if let prescribed {
            PlannedTargetLine(target: prescribed, comparison: nil, unit: unit)
                .padding(.horizontal, Spacing.lg.points)
                .padding(.top, Spacing.lg.points)
        }
    }
}

/// The set editor's six fields (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.8`).
///
/// **A type of its own so a reference can be taken of it**, which is `TR-1.12` rather than
/// decomposition for its own sake: `ImageRenderer` lays a `ScrollView`'s content out and draws none
/// of it, so a snapshot of the sheet is a picture of the divider and the two commands with the whole
/// form missing. Rendered directly, the fields are a picture again — and `NFR-1.10`'s claim that
/// they still fit at `accessibility3` is something the gate can actually check.
///
/// The two fields that decide whether the set logs lead, then the kind, then the optional ones: at
/// the medium detent the load and the repetitions are what is on screen without scrolling.
struct SetEditorFields: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// Set by anything the user does here, so the commands below know the form has been touched.
    @Binding var hasInput: Bool

    /// Whether the form is editing a logged set rather than adding one (`FR-1.2.7`) — what decides
    /// the title.
    var isEditing: Bool = false

    /// The modifier terms on offer (`FR-1.2.8`).
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on.
    let equipment: PlateCalculatorStore

    /// Whether `FR-1.4.1`'s calculator is on screen.
    ///
    /// The row's own, for ``isPicking``'s reason.
    @State private var isCalculating = false

    /// Whether `FR-1.2.8`'s picker is on screen.
    ///
    /// The row's own, so it cannot outlive the sheet it was raised from — `SetEditorCommands`'
    /// confirmation's rule.
    @State private var isPicking = false

    /// Title, then the six rows.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            Text(isEditing ? LoggingStrings.setEditorEditTitle : LoggingStrings.setEditorTitle)
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
            weightField
            plateLoadingField
            repsField
            warmupField
            rpeField
            modifiersField
            notesField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Read here rather than in the row below it, so one read answers a weight the user steps
        // through with the ± pair — and so the row does not re-read every time the field empties.
        .task { await equipment.load() }
        .sheet(isPresented: $isPicking) {
            SetModifierPicker(
                applied: $draft.modifiers,
                vocabulary: vocabulary,
                dismiss: { isPicking = false }
            )
        }
    }

    /// `FR-1.4.1`'s per-side loading for the weight this form holds, and the way into the whole
    /// answer.
    ///
    /// **Second, directly under the load it describes**, and drawn only once that load parses — a
    /// row over a blank field would be a control that starts dead on every new set, and this form is
    /// at `NFR-1.10`'s ceiling with the rows it already has. It costs `NFR-1.3`'s three taps
    /// nothing: the two commands are pinned outside the scroll view, so a seventh row moves neither.
    ///
    /// **The sheet is attached here rather than beside the picker's.** Two `.sheet(isPresented:)`
    /// on one view is one presentation with the other silently ignored; each row carries its own.
    @ViewBuilder private var plateLoadingField: some View {
        if let target = draft.weight {
            PlateLoadingRow(
                target: target,
                result: equipment.loading(for: target),
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

    /// `FR-1.2.8`'s modifiers — a summary of what is applied, and the way into the picker.
    ///
    /// **One row that opens a sheet, rather than the nine-plus controls the choice actually is.**
    /// The form is at `NFR-1.10`'s ceiling with the rows it already has; a wrapping grid of chips
    /// would be the tallest thing on it and would grow with the user's own list, which has no
    /// ceiling at all. What the row costs instead is fixed.
    ///
    /// **Fifth rather than last**: a modifier is a fact about how the set was performed, like the
    /// rating above it, where the note is prose about the occasion.
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
            // Rather than on the tap that opens the picker: `hasInput` is what keeps a form nobody
            // has filled in from opening on a refusal, and opening the picker and dismissing it is
            // not filling anything in. Every other field here marks input on the change too.
            .onChange(of: draft.modifiers) { hasInput = true }
        }
    }

    /// What the row says: the applied modifiers as a list in the user's locale, or that there are
    /// none.
    ///
    /// A string rather than a `Text`, because the row announces it as well as drawing it.
    private var summaryValue: String {
        draft.modifiers.isEmpty
            ? String(localized: LoggingStrings.setModifierNone)
            : draft.modifiers.map(\.displayName)
                .formatted(.list(type: .and).locale(draft.locale))
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

    /// Whether the set is a warmup (`FR-1.2.4`).
    ///
    /// **Third rather than last, and that is `NFR-1.4` rather than an ordering preference.** It sits
    /// with the two fields that describe what was lifted, above the two optional ones: a warmup is
    /// decided before the set is logged, where a rating and a note are afterthoughts, and at the
    /// medium detent everything above the fold is what gets touched without scrolling. A ramp is
    /// three or four warmups in a row, so a switch below the fold would be scrolled to on every one
    /// of them.
    ///
    /// **A `Toggle`, because the value is a boolean and that is the only control VoiceOver announces
    /// as one** — but drawn as a button rather than as a switch, and that is measured rather than
    /// stylistic. A switch is UIKit-backed, and inside a sheet held at the `.medium` detent it never
    /// received the tap: the sheet's own drag recogniser claimed it, so the control rendered
    /// perfectly and did nothing until the sheet was dragged to `.large`. Every other control in
    /// this form is a SwiftUI `Button` and none of them has the problem. `.toggleStyle(.button)`
    /// keeps the toggle semantics and drops the UIKit view, which fixes the tap and, incidentally,
    /// is the one thing that lets `TR-1.12`'s harness picture the control at all — a `UISwitch`
    /// rasterises as the renderer's placeholder.
    ///
    /// **Not a `FieldRow`, and that is measured too.** Every other row here is a label above a
    /// control, which for a boolean means the label twice over and two rows' worth of height; built
    /// that way the control sat *below the medium detent's fold*, so `NFR-1.4`'s reachable control
    /// needed a scroll to reach.
    ///
    /// **A symbol as well as the fill** (`G-4.5`): on and off must not differ by colour alone.
    private var warmupField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Toggle(
                isOn: Binding(
                    get: { draft.isWarmup },
                    set: {
                        hasInput = true
                        draft.isWarmup = $0
                    }
                )
            ) {
                HStack(spacing: Spacing.sm.points) {
                    Image(systemName: draft.isWarmup ? "checkmark.circle.fill" : "circle")
                        .accessibilityHidden(true)
                    Text(LoggingStrings.setWarmupLabel)
                        .font(Typography.actionLabel.font)
                    Spacer(minLength: Spacing.sm.points)
                }
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .contentShape(.rect)
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(draft.isWarmup ? ColorToken.brandAccent : ColorToken.textPrimary)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            Text(LoggingStrings.setWarmupHint)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
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
