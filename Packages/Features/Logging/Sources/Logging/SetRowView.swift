import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// `FR-1.2.14`'s warmup group, and the control that folds it.
///
/// **Its own fold, beside the card's rather than inside it.** `FR-1.2.13` collapses a finished
/// exercise and `FR-1.2.14` collapses the warmups within one; a card that is open may have either
/// state of this, so the two folds are two pieces of state and two controls.
///
/// **The count is a numeral beside a word**, on `SessionExerciseCard`'s rule: a label next to a
/// number stays a count in every language, where "3 warmups" would need a plural rule per language
/// to say the same thing.
struct WarmupSectionHeader: View {
    /// How many warmups the group holds — the part of it that is legible while it is folded.
    let count: Int

    /// Whether it is open.
    let isExpanded: Bool

    /// Opens or closes it.
    let toggle: () -> Void

    /// Which locale the count is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The heading, as one control across the card's width.
    ///
    /// One VoiceOver element carrying the fold as a **value**, for the card header's reason: there
    /// is no expanded trait, and `.isSelected` means a chosen filter everywhere else in this app.
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.sm.points) {
                Text(LoggingStrings.setWarmupSection)
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                Text(count, format: AppFormat.count(locale: locale))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
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
}

/// One logged set inside an exercise card (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.5`, `FR-1.2.14`).
///
/// **The number, the load, the repetitions and the rating, in that order and on one line.** A set is
/// read at a glance between efforts, so it is a line rather than a card: what a user is checking is
/// what they did last time, not one set in isolation.
///
/// **The multiplication sign is drawn and hidden from VoiceOver** (`G-4.2`). It is punctuation
/// between two numbers rather than a word, and read aloud it is noise; the two numerals either side
/// carry labels of their own instead.
///
/// **A warmup is drawn one step down the type scale and one step back in the colour ramp** — the
/// caption role rather than the numeric one, secondary text rather than primary. Both are
/// `DesignSystem` tokens, so "de-emphasised" is a position in the scale that retunes with it rather
/// than a smaller font written here. The load and the reps stay exactly where they are: a warmup is
/// quieter, not laid out differently, and a column that shifted would cost the card the alignment
/// that makes it scannable.
struct SetRow: View {
    /// The set, and its place in its own sequence (`FR-1.2.14`).
    ///
    /// **Numbered rather than positioned**, which `SetEntry.order` cannot do: that column is
    /// zero-based, counts both kinds together and carries the gaps a soft-deleted set leaves.
    let numbered: NumberedSet

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Marks this set as a warmup or as working (`FR-1.2.4`) — the set, then which it becomes.
    let mark: (SetEntry, Bool) -> Void

    /// Marks this set as completed or failed (`FR-1.2.5`) — the set, then which it becomes.
    let markCompleted: (SetEntry, Bool) -> Void

    /// Opens `FR-1.2.7`'s editor over this set.
    let edit: (SetEntry) -> Void

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// How large the user reads at — what decides whether this row is a line or a stack
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The line: the badge, the set itself, then its outcome.
    ///
    /// **Three VoiceOver elements rather than one, and all three are controls.** Combining the whole
    /// row would bury three buttons inside a static element and take `FR-1.2.4`'s marking,
    /// `FR-1.2.5`'s and `FR-1.2.7`'s editing away from every VoiceOver user; each announces beside
    /// the values it belongs to, so what is read in sequence is "Set 1", "102.5 kg, Reps 5",
    /// "Completed".
    ///
    /// **The three are siblings, and none of them contains another.** `FR-1.2.7` wants a way into
    /// the editor from the row, and the obvious shape — a tap on the whole row, with the two badges
    /// still tappable inside it — is a control nested in a control, where which one receives a tap
    /// depends on ancestry rather than on where the thumb landed. The middle third is its own button
    /// instead: the values are what a user points at to say *this set*, and the two marking controls
    /// keep exactly the targets they had.
    var body: some View {
        layout {
            badge
            values
            outcome
        }
        .frame(minHeight: TouchTarget.standard.points)
    }

    /// A line at ordinary sizes and a stack at `NFR-1.10`'s, which is what keeps the load readable.
    ///
    /// **Measured rather than assumed, and it is the badge that forced it.** `FR-1.2.4`'s marking
    /// control is 44pt wide by `G-4.3`, and at `accessibility3` those 44 points came out of the
    /// load: `102.5 kg` broke across three lines — `10` / `2.5` / `kg` — which is a number the user
    /// has to reassemble mid-workout. Stacked, the badge takes a line of its own and the load gets
    /// the row's full width. The two layouts are one `AnyLayout` rather than two branches of the
    /// body so that the badge and the values keep their identity across the switch, and with them
    /// their accessibility elements and the focus a VoiceOver user is holding.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs.points))
            : AnyLayout(HStackLayout(spacing: Spacing.sm.points))
    }

    /// The load, the repetitions and the rating — one VoiceOver element, because they are one set,
    /// and `FR-1.2.7`'s way into the editor.
    ///
    /// **A button rather than a tap gesture.** A gesture is invisible to VoiceOver and to Switch
    /// Control and announces no hint; a button is reachable by every input (`G-4.2`), which is the
    /// same argument that made the exercise reorder a pair of buttons rather than a drag.
    ///
    /// **The same layout switch as the row itself**, and for the same measured reason: at
    /// `accessibility3` a rating pushed to the trailing edge takes the width `102.5 kg` needs, and
    /// the load breaks mid-number. Stacked, the rating goes underneath and the load stays one word.
    /// Combining is applied over the whole subtree, so the announcement is unchanged either way.
    ///
    /// **The width is claimed with a `frame` rather than a `Spacer`**, which is what lets one
    /// declaration serve both layouts: a spacer that pushes the rating rightwards in a row would
    /// expand *downwards* in a column and put a blank line inside every set.
    private var values: some View {
        Button {
            edit(numbered.record)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                layout {
                    HStack(spacing: Spacing.sm.points) {
                        Text(
                            numbered.record.weight,
                            format: AppFormat.weight(in: unit, locale: locale)
                        )
                        .font(valueFont)
                        .foregroundStyle(valueColour)
                        Image(systemName: "multiply")
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textTertiary)
                            .accessibilityHidden(true)
                        Text(numbered.record.reps, format: AppFormat.count(locale: locale))
                            .font(valueFont)
                            .foregroundStyle(valueColour)
                            .accessibilityLabel(Text(LoggingStrings.setReps(numbered.record.reps)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    rating
                }
                modifiers
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(LoggingStrings.setEditAction))
    }

    /// The set's number, and `FR-1.2.4`'s marking control.
    ///
    /// **The badge is the toggle, rather than a sixth thing on an already-full line.** The number is
    /// the visible consequence of the flag — `W1` or `1` — so the control and what it changes are
    /// the same object, and the row keeps the width the load, the reps and the rating need at
    /// `NFR-1.10`'s ceiling. It is drawn on a raised capsule so it reads as tappable rather than as
    /// a numeral that happens to respond.
    ///
    /// At the standard touch target rather than the logging one: marking a set is a correction made
    /// between efforts, not one of `NFR-1.3`'s counted taps.
    private var badge: some View {
        Button {
            mark(numbered.record, !numbered.isWarmup)
        } label: {
            numberText
                .font(numberFont)
                .foregroundStyle(ColorToken.textTertiary)
                .frame(
                    minWidth: TouchTarget.standard.points, minHeight: TouchTarget.standard.points
                )
                .background(ColorToken.surfaceRaised, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(numberLabel))
        .accessibilityHint(Text(LoggingStrings.setMarkAction(isWarmup: numbered.isWarmup)))
    }

    /// `FR-1.2.5`'s outcome, and the control that changes it.
    ///
    /// **A glyph rather than a word, and it is on every row rather than only the failed ones.** A
    /// control that appeared once a set had failed would be a control with no way to reach the
    /// first failure; a word would cost the load the width `NFR-1.10` has already spent on the
    /// badge. What the glyph buys instead is `G-4.5`: a check and a cross differ in shape, so the
    /// outcome survives a monochrome rendering, which is `DeltaIndicator`'s rule applied to a
    /// two-state fact rather than a three-state one.
    ///
    /// **Both are enclosed, and that is what keeps the cross off the multiplication sign.** A bare
    /// `xmark` is the same shape as the drawn `×` between the load and the reps, two glyphs apart
    /// on the same line, and told apart only by tint — which is the cue `G-4.5` says cannot be the
    /// only one. Enclosing the pair makes the outcome a mark of its own rather than a second
    /// operator, and it reads as a pair with the check.
    ///
    /// **A completed set is drawn quietly and a failed one is not.** Every set logged here is
    /// completed, so a green tick per row would be a colour the reader has to look past on the way
    /// to the one row that is different — `G-7.3` reserves the semantic palette for what it
    /// distinguishes, and the distinguishing case is the failure.
    ///
    /// At the standard touch target rather than the logging one, for the badge's reason: marking a
    /// set failed is a correction between efforts, not one of `NFR-1.3`'s counted taps.
    private var outcome: some View {
        Button {
            markCompleted(numbered.record, !numbered.isCompleted)
        } label: {
            Image(systemName: numbered.isCompleted ? "checkmark.circle" : "xmark.circle")
                .font(Typography.caption.font)
                .foregroundStyle(numbered.isCompleted ? ColorToken.textTertiary : ColorToken.negative)
                .frame(
                    minWidth: TouchTarget.standard.points, minHeight: TouchTarget.standard.points
                )
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LoggingStrings.setOutcome(isCompleted: numbered.isCompleted)))
        .accessibilityHint(
            Text(LoggingStrings.setOutcomeAction(isCompleted: numbered.isCompleted)))
    }

    /// The badge's text — `W1` for a warmup, a bare numeral for a working set.
    ///
    /// **Both numerals go through the same format style** (`G-3.4`). The warmup's is rendered here
    /// and handed to the catalogue as a string rather than interpolated as an integer, so the two
    /// numbers on one row cannot be drawn by two different mechanisms.
    private var numberText: Text {
        let rendered = numbered.number.formatted(AppFormat.count(locale: locale))
        return numbered.isWarmup
            ? Text(LoggingStrings.setWarmupNumber(rendered))
            : Text(numbered.number, format: AppFormat.count(locale: locale))
    }

    /// The same number as VoiceOver reads it (`G-4.2`).
    private var numberLabel: LocalizedStringResource {
        numbered.isWarmup
            ? LoggingStrings.setWarmupPosition(numbered.number)
            : LoggingStrings.setPosition(numbered.number)
    }

    /// The badge's role in the type scale. Warmups sit one step down, with the values beside them.
    private var numberFont: Font {
        numbered.isWarmup ? Typography.caption.font : Typography.numericValue.font
    }

    /// The load and the repetitions' role in the type scale.
    private var valueFont: Font {
        numbered.isWarmup ? Typography.caption.font : Typography.numericValue.font
    }

    /// Their place in the colour ramp.
    ///
    /// **A failed set is red wherever it sits in that ramp** (`G-7.3`, and the requirement's own
    /// words are "failure and missed lifts"), so the outcome outranks the warmup de-emphasis rather
    /// than compounding with it — a failed warmup is a missed lift too.
    ///
    /// `G-4.5`'s rule holds through both cases, and by two different cues: the numbering says
    /// *warmup* in words, and the glyph at the end of the row says *failed* in a shape.
    private var valueColour: ColorToken {
        guard numbered.isCompleted else { return ColorToken.negative }
        return numbered.isWarmup ? ColorToken.textSecondary : ColorToken.textPrimary
    }

    /// `FR-1.2.8`'s modifiers, where the set carries any.
    ///
    /// **On the row rather than only in the editor.** A modifier that could be applied and then not
    /// seen would be a fact about the set that costs a tap to read; the row is what a lifter checks
    /// between efforts. It takes a line of its own only when there is one to draw.
    ///
    /// **Below the values rather than beside them, at every size.** The line is already spending its
    /// width on two 44pt controls and the load — T-1.23 measured a single badge breaking `102.5 kg`
    /// into three lines — so a modifier list on the same line would come out of the number.
    ///
    /// A spelling this build does not recognise is drawn as itself; see ``SetModifier/displayName``.
    @ViewBuilder private var modifiers: some View {
        if !numbered.record.modifiers.isEmpty {
            Text(
                numbered.record.modifiers.map(\.displayName)
                    .formatted(.list(type: .and).locale(locale))
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textTertiary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The rating, where the set carries one.
    @ViewBuilder private var rating: some View {
        if let rpe = numbered.record.rpe {
            Text(
                LoggingStrings.setRPE(
                    rpe.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
                )
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
    }
}
