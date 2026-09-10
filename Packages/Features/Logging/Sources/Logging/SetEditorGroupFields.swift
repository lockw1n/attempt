import DesignSystem
import DesignTokens
import Localization
import PowerliftingCore
import SwiftUI

/// What the plan asked for and what the form says, side by side with the difference called out
/// (`FR-17.9.4`).
///
/// **Two lines rather than one, and both are values.** The pair is read while a number is being
/// typed, so *Planned* has to stay put while *Actual* moves under it; drawn as one line the two
/// would reflow against each other on every keystroke.
///
/// **Silent where nothing planned the row.** An exercise the lifter added has no target
/// (`FR-1.2.2`), and a pair with an empty half would report the absence as a deviation.
struct PlannedActualPair: View {
    /// What the routine prescribed, in order.
    let plan: [WeekPlanTarget]

    /// What the form says.
    let draft: SetDraft

    /// Which locale the numbers read in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    var body: some View {
        if !plan.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                line(LoggingStrings.setPlannedLabel, value: plannedText)
                line(LoggingStrings.setActualLabel, value: actualText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One half of the pair.
    ///
    /// - Parameters:
    ///   - label: Which half.
    ///   - value: What it says.
    /// - Returns: The line.
    private func line(_ label: LocalizedStringResource, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
            Text(label)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textTertiary)
            Text(verbatim: value)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The prescription, rendered.
    private var plannedText: String {
        WeekPlanTargets.rendered(
            plan, unit: draft.unit, precision: displayPrecision, locale: locale)
    }

    /// What the form says, with the difference appended where there is one.
    private var actualText: String {
        PlannedActual.actual(
            of: draft, against: plan, precision: displayPrecision, locale: locale)
            ?? PlannedActual.unresolved
    }
}

/// The Actual line's whole rule (`FR-17.9.4`).
///
/// **Off the view, because it is three decisions and a `body` cannot fail a test** — what the line
/// says while the form does not resolve, which group the form is measured against, and whether the
/// difference is stated at all.
enum PlannedActual {
    /// What the line reads while the form does not resolve to a group.
    ///
    /// An em dash rather than copy: it is the same character in every language this app ships, and
    /// a blank value reads as a line that failed to draw rather than one with nothing to say yet.
    static let unresolved = "—"

    /// The form's own group, rendered, with the deviation appended where the plan supports one.
    ///
    /// **The deviation is dropped rather than guessed where the plan holds more than one group.**
    /// A prescription of `100 × 5 × 3` then `90 × 8 × 2` has no single difference to state — see
    /// ``PlannedGroupComparison``  — and a sentence measured against the first half would report a
    /// deviation the lifter did not make.
    ///
    /// - Parameters:
    ///   - draft: The form.
    ///   - plan: What was prescribed, in order.
    ///   - precision: `G-3.3`'s step.
    ///   - locale: Which locale the numbers read in.
    /// - Returns: `30 kg × 8 × 3 · −2 reps`, or `nil` where the form does not resolve.
    static func actual(
        of draft: SetDraft,
        against plan: [WeekPlanTarget],
        precision: DisplayPrecision?,
        locale: Locale
    ) -> String? {
        guard let group = draft.resolvedGroup else { return nil }
        let performed = WeekPlanTarget(
            id: UUID(), weight: group.values.weight, reps: group.values.reps, sets: group.sets)
        let rendered = WeekPlanTargets.rendered(
            [performed], unit: draft.unit, precision: precision, locale: locale)
        guard let comparison = PlannedGroupComparison(planned: plan, performed: performed) else {
            return rendered
        }
        let deviation = PlannedDeviation.sentence(
            comparison, unit: draft.unit, precision: precision, locale: locale)
        return String(
            localized: LoggingStrings.setDeviationLine(
                performed: rendered, deviation: deviation))
    }
}

/// **Per-set details** — the fold that holds warm-ups, RPE, notes, modifiers and per-set reps
/// (`FR-17.9.4`).
///
/// **Collapsed, because it is the exception.** The form above it says what happened on almost every
/// exercise; what this exists for is `80 × 8, 8, 6` — a run the lifter still thinks of as one
/// answer, which a Weight / Reps / Sets form cannot say.
///
/// **A different *load* is not offered.** A different load is a different group; log it as a second
/// answer through `+ Add exercise` or a second **Log**.
struct SetDetailsFold: View {
    /// What the user has entered so far.
    @Binding var draft: SetDraft

    /// The modifier terms on offer (`FR-1.2.8`).
    let vocabulary: SetModifierVocabulary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            disclosure
            if !draft.details.isEmpty {
                ForEach(draft.details.indices, id: \.self) { index in
                    SetDetailRow(
                        position: index + 1,
                        detail: $draft.details[index],
                        vocabulary: vocabulary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The row that opens and closes it.
    ///
    /// **Opening prefills every entry from the form and closing discards them**, which is what
    /// makes the fold an override rather than a second form: a lifter who opens it, changes the
    /// last set's reps and closes it again has said they did not mean to.
    private var disclosure: some View {
        Button {
            draft = draft.details.isEmpty ? draft.openingDetails() : draft.closingDetails()
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Text(LoggingStrings.setDetailsLabel)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: draft.details.isEmpty ? "chevron.down" : "chevron.up")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(LoggingStrings.setDetailsLabel))
        .accessibilityValue(
            Text(
                draft.details.isEmpty
                    ? LoggingStrings.sessionExerciseCollapsed
                    : LoggingStrings.sessionExerciseExpanded))
    }
}

/// One set inside the fold (`FR-17.9.4`).
///
/// **Reps, rating, kind, modifiers and note — every field the form has except the load**, which is
/// the group's. Ordered as the form is: what decides the set first, what describes it after.
struct SetDetailRow: View {
    /// Which set of the group this is, counting from one.
    let position: Int

    /// What it carries.
    @Binding var detail: SetDetailDraft

    /// The modifier terms on offer (`FR-1.2.8`).
    let vocabulary: SetModifierVocabulary

    /// Whether this row's picker is on screen. Its own, so it cannot outlive the sheet.
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(LoggingStrings.setPosition(position))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textTertiary)
            HStack(spacing: Spacing.sm.points) {
                SetEditorControls.stepButton(
                    symbolName: "minus", label: LoggingStrings.setRepsDecrease
                ) {
                    detail = detail.adjustingReps(by: -1)
                }
                SetEditorControls.numberField(
                    text: $detail.repsText, label: LoggingStrings.setRepsLabel)
                SetEditorControls.stepButton(
                    symbolName: "plus", label: LoggingStrings.setRepsIncrease
                ) {
                    detail = detail.adjustingReps(by: 1)
                }
                SetEditorControls.numberField(
                    text: $detail.rpeText, label: LoggingStrings.setRPELabel)
            }
            WarmupToggle(isWarmup: $detail.isWarmup, label: LoggingStrings.setWarmupLabel)
            modifiers
            SetEditorControls.textField(
                text: $detail.notes, label: LoggingStrings.setNotesLabel)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isPicking) {
            SetModifierPicker(
                applied: $detail.modifiers,
                vocabulary: vocabulary,
                dismiss: { isPicking = false }
            )
        }
    }

    /// This set's modifiers, and the way into the picker.
    private var modifiers: some View {
        Button {
            isPicking = true
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Text(verbatim: SetModifierSummary.rendered(detail.modifiers, locale: detail.locale))
                    .font(Typography.body.font)
                    .foregroundStyle(
                        detail.modifiers.isEmpty ? ColorToken.textTertiary : ColorToken.textPrimary
                    )
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityValue(
            Text(verbatim: SetModifierSummary.rendered(detail.modifiers, locale: detail.locale)))
    }
}

extension SetDetailDraft {
    /// This entry with its repetitions moved by `steps`, floored at zero.
    ///
    /// Zero is a value here rather than an absence — `FR-1.2.5`'s failed set records zero reps.
    ///
    /// - Parameter steps: How many repetitions to move — negative is down.
    /// - Returns: The adjusted entry.
    func adjustingReps(by steps: Int) -> SetDetailDraft {
        var adjusted = self
        adjusted.repsText = LocalizedNumberField.render(
            Double(max(0, (reps ?? 0) + steps)), locale: locale)
        return adjusted
    }
}
