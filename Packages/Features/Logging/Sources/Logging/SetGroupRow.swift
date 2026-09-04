import DerivedValues
import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// A run of identical sets on one line — `100,0 kg × 6 × 4` (`FR-16.1.1`, `FR-16.1.3`).
///
/// **A group of one is a row, not a group of one.** A single set is drawn by ``SetRow`` exactly as
/// it always was: it has nothing to collapse, and a disclosure control over one set would be a tap
/// that reveals what is already on screen.
///
/// **Everything the collapsed line draws is shared by every member**, which is what
/// ``DerivedValues/SetGrouping/Grain/displayed`` guarantees: the load, the reps, the rating, the
/// modifiers, the outcome. The two things that are *not* compared — `FR-1.6.3`'s record badge and
/// `FR-15.3.1`'s planned target — are the two this view has to be careful with, and each is handled
/// where it is drawn.
///
/// **The second multiplication sign is punctuation like the first** (`G-4.2`, ``SetRow``'s rule):
/// drawn, hidden from VoiceOver, and the numeral after it carries its own label — so the group reads
/// aloud as "100 kilograms, 6 reps, 4 sets".
struct SetGroupRow: View {
    /// The group, its members and their numbers.
    let group: NumberedSetGroup

    /// The unit the loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether the group is open on its rows (`FR-16.1.3`).
    let isExpanded: Bool

    /// Opens or closes it.
    let toggle: () -> Void

    /// Marks one member as a warmup or as working (`FR-1.2.4`), or `nil` where the surface does not
    /// offer it — see ``SetRow/mark``. The collapsed line never offers it: changing the kind of four
    /// sets on one tap is a write nobody asked for, and the rows underneath already carry it.
    let mark: ((SetEntry, Bool) -> Void)?

    /// Marks one member completed or failed (`FR-1.2.5`), likewise.
    let markCompleted: ((SetEntry, Bool) -> Void)?

    /// Opens `FR-1.2.7`'s editor over one member.
    let edit: (SetEntry) -> Void

    /// The schemes one member holds the record at (`FR-1.6.3`, `FR-16.2.4`), or none.
    var recordSchemes: (UUID) -> [RecordScheme] = { _ in [] }

    /// What a routine planned for one member (`FR-15.3.1`), or `nil`.
    var target: (UUID) -> PlannedTargetGroup? = { _ in nil }

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// How large the user reads at (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The line, and the rows beneath it while it is open.
    var body: some View {
        if group.isSingle {
            row(for: group.first)
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                summary
                // Indented, so the rows read as this group's members rather than as sets the
                // card gained. Each is the ordinary row, controls and all — which is the whole of
                // `FR-16.1.3`: nothing a set carries is more than one tap away. Which rows those
                // are is ``NumberedSetGroup/memberRows(isExpanded:)``, so the claim is a value a
                // test can hold rather than a branch inside a view body.
                ForEach(group.memberRows(isExpanded: isExpanded)) { member in
                    row(for: member)
                        .padding(.leading, Spacing.md.points)
                }
            }
        }
    }

    /// The collapsed line: the range, the group itself, then its outcome.
    ///
    /// ``SetRow``'s three-element shape with one element fewer that is a control — the badge and the
    /// outcome are labels here, because a tap on either would act on four sets at once.
    private var summary: some View {
        layout {
            badge
            values
            outcomeLabel
        }
        .frame(minHeight: TouchTarget.standard.points)
    }

    /// A line at ordinary sizes and a stack at `NFR-1.10`'s — ``SetRow/layout``'s measured switch,
    /// applied to a line carrying one more numeral than that one does.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs.points))
            : AnyLayout(HStackLayout(spacing: Spacing.sm.points))
    }

    /// The load, the repetitions, the count — one VoiceOver element, because they are one group, and
    /// the control that opens it.
    ///
    /// **The disclosure carries the fold as a value rather than a trait**, on
    /// ``WarmupSectionHeader``'s rule: SwiftUI has no expanded trait, and `.isSelected` means a
    /// chosen filter everywhere else in this app.
    private var values: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                layout {
                    HStack(spacing: Spacing.sm.points) {
                        Text(
                            group.record.weight,
                            format: AppFormat.weight(
                                WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
                        )
                        .font(valueFont)
                        .foregroundStyle(valueColour)
                        multiplicationSign
                        Text(group.record.reps, format: AppFormat.count(locale: locale))
                            .font(valueFont)
                            .foregroundStyle(valueColour)
                            .accessibilityLabel(Text(LoggingStrings.setReps(group.record.reps)))
                        multiplicationSign
                        Text(group.count, format: AppFormat.count(locale: locale))
                            .font(valueFont)
                            .foregroundStyle(valueColour)
                            .accessibilityLabel(Text(LoggingStrings.setGroupCount(group.count)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                rating
                recordMark
                modifiers
                plannedTarget
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityHint(Text(LoggingStrings.setGroupExpandHint))
    }

    /// The drawn `×`, which is punctuation rather than a word (`G-4.2`).
    private var multiplicationSign: some View {
        Image(systemName: "multiply")
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textTertiary)
            .accessibilityHidden(true)
    }

    /// The numbers the group spans — `1–4`, or `W1–4` for warmups.
    ///
    /// A label rather than `FR-1.2.4`'s control: see ``mark``. The capsule stays, so a group keeps
    /// the alignment the rows around it have.
    private var badge: some View {
        numberText
            .font(numberFont)
            .foregroundStyle(ColorToken.textTertiary)
            .frame(minWidth: TouchTarget.standard.points, minHeight: TouchTarget.standard.points)
            .background(ColorToken.surfaceRaised, in: .capsule)
            .accessibilityElement()
            .accessibilityLabel(Text(numberLabel))
    }

    /// The badge's text. Both numerals go through `AppFormat`, on ``SetRow/numberText``'s rule.
    private var numberText: Text {
        let rendered = String(
            localized: LoggingStrings.setNumberRange(
                first: group.numbers.lowerBound.formatted(AppFormat.count(locale: locale)),
                last: group.numbers.upperBound.formatted(AppFormat.count(locale: locale))
            ))
        return group.isWarmup
            ? Text(LoggingStrings.setWarmupNumber(rendered))
            : Text(verbatim: rendered)
    }

    /// The same range as VoiceOver reads it (`G-4.2`).
    private var numberLabel: LocalizedStringResource {
        group.isWarmup
            ? LoggingStrings.setWarmupPositionRange(
                first: group.numbers.lowerBound, last: group.numbers.upperBound)
            : LoggingStrings.setPositionRange(
                first: group.numbers.lowerBound, last: group.numbers.upperBound)
    }

    /// `FR-1.2.5`'s outcome, which the group cannot mix — a label here, never the control
    /// ``SetRow/outcome`` is.
    private var outcomeLabel: some View {
        Image(systemName: group.isCompleted ? "checkmark.circle" : "xmark.circle")
            .font(Typography.caption.font)
            .foregroundStyle(group.isCompleted ? ColorToken.textTertiary : ColorToken.negative)
            .frame(minWidth: TouchTarget.standard.points, minHeight: TouchTarget.standard.points)
            .accessibilityElement()
            .accessibilityLabel(Text(LoggingStrings.setOutcome(isCompleted: group.isCompleted)))
    }

    /// `FR-16.2.4`'s badge: the maximal scheme this run set — **PR 5×5**.
    ///
    /// **The run's cells, gathered over every member.** The cache names a run by its *first* set
    /// (`SetRun.setOffset`), so all of them are found under one identifier in practice; reading every
    /// member costs nothing and keeps the line right if a group is ever drawn over sets the cache
    /// attributed separately.
    @ViewBuilder private var recordMark: some View {
        if let badge = recordBadge {
            Text(badge.text)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.onBrandAccent)
                .padding(.horizontal, Spacing.sm.points)
                .padding(.vertical, Spacing.xxs.points)
                .background(ColorToken.brandAccent, in: .capsule)
                .accessibilityLabel(Text(badge.label))
        }
    }

    /// The badge this run carries, or `nil` where no member holds a record.
    private var recordBadge: RecordBadge? {
        RecordBadge(schemes: group.members.flatMap { recordSchemes($0.id) })
    }

    /// `FR-1.2.8`'s modifiers, which the group cannot mix — see
    /// ``DerivedValues/SetGrouping/Grain/displayed``.
    @ViewBuilder private var modifiers: some View {
        if !group.record.modifiers.isEmpty {
            Text(
                group.record.modifiers.map(\.displayName)
                    .formatted(.list(type: .and).locale(locale))
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textTertiary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// `FR-15.3.1`'s target, **only where every member was planned against the same group**.
    ///
    /// The plan is not a compared field, and it need not agree across a run: two planned groups can
    /// prescribe the same load and reps, so four identical sets can straddle them. Drawn once, the
    /// line would name one member's target under all four — so where they differ it belongs to the
    /// rows, which is one tap away.
    @ViewBuilder private var plannedTarget: some View {
        if let shared = group.sharedTarget(target) {
            PlannedTargetLine(
                target: shared,
                comparison: PlannedTargetComparison(set: group.record, target: shared),
                unit: unit
            )
        }
    }

    /// The rating, where the group carries one.
    ///
    /// **Below the values rather than beside them, at every size** — unlike ``SetRow/rating``, which
    /// keeps the line until `NFR-1.10`'s ceiling. Measured: this line carries one numeral pair more
    /// than that one does, and with the rating beside it `100.0 kg` broke across two lines at the
    /// **default** type size, which is T-1.23's finding reached one field earlier.
    @ViewBuilder private var rating: some View {
        if let rpe = group.record.rpe {
            Text(
                LoggingStrings.setRPE(
                    rpe.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
                )
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// One member's own row — ``SetRow``, unchanged, so a set reads identically wherever it is drawn.
    ///
    /// - Parameter numbered: The member and its number.
    /// - Returns: The row.
    private func row(for numbered: NumberedSet) -> some View {
        SetRow(
            numbered: numbered,
            unit: unit,
            recordSchemes: recordSchemes(numbered.id),
            mark: mark,
            markCompleted: markCompleted,
            edit: edit,
            target: target(numbered.id)
        )
    }

    /// The badge's role in the type scale — ``SetRow/numberFont``'s rule.
    private var numberFont: Font {
        group.isWarmup ? Typography.caption.font : Typography.numericValue.font
    }

    /// The values' role in it, likewise.
    private var valueFont: Font {
        group.isWarmup ? Typography.caption.font : Typography.numericValue.font
    }

    /// Their place in the colour ramp — ``SetRow/valueColour``'s rule, which a group shares because
    /// it cannot mix either fact.
    private var valueColour: ColorToken {
        guard group.isCompleted else { return ColorToken.negative }
        return group.isWarmup ? ColorToken.textSecondary : ColorToken.textPrimary
    }
}
