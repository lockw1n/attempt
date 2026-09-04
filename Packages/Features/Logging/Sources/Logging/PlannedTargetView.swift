import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// What a routine prescribed, drawn beside what was done (`FR-15.3.1`, `FR-15.3.2`).
///
/// **The target is drawn whether or not the set deviated.** A mark that appeared only on a miss
/// would leave the lifter unable to tell "matched the plan" from "was not planned at all", which
/// are the two states this line exists to separate — and `FR-15.3.1`'s words are *shown alongside*,
/// not *shown when wrong*.
///
/// **Deviation is never carried by colour alone** (`G-4.5`). Each direction arrives as
/// ``DesignSystem/DeltaIndicator``, which draws an arrow and a sign beside the magnitude, and a set
/// that matched says so in a word next to a check glyph.
struct PlannedTargetLine: View {
    /// The group this set was planned against.
    let target: PlannedTargetGroup

    /// How the set measured against it, or `nil` on a row that only shows the plan.
    let comparison: PlannedTargetComparison?

    /// The unit both the target and the deviation are shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// How large the user reads at — what decides whether the two indicators share a line
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The target, then whatever the set did against it — always on two lines.
    ///
    /// **Stacked at every size, and that is measured rather than cautious.** Drawn as one line, a
    /// set that missed on both dimensions put `Target 85.0 kg × 8` and two indicators into what is
    /// left of a row already spending its width on two 44pt controls and the load — and the first
    /// reference taken of it broke `2.5 kg` into `0.` / `— 0` / `kg` and `reps` into `re` / `ps`.
    /// That is the same trap T-1.23 measured on the badge, one line further down, and it has the
    /// same answer as ``SetRow``'s record mark and modifier list: take a line of your own.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(targetText)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            verdict
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The two indicators side by side at ordinary sizes and stacked at `NFR-1.10`'s ceiling, where
    /// a line of their own is still not enough for two signed numbers with units.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs.points))
            : AnyLayout(HStackLayout(spacing: Spacing.sm.points))
    }

    /// What the set did: nothing where there is no set yet, a word where it matched, and one
    /// indicator per dimension that moved.
    ///
    /// **Only the dimensions that moved are drawn.** A set that hit its load and missed its reps
    /// says `−1 reps` and nothing else; the `— 0.0 kg` the first rendering of this carried is a
    /// signed zero the reader has to look past on the way to the number that changed.
    ///
    /// **The load's indicator is absent, not neutral, where the plan named no load** (`FR-15.2.2`).
    /// A `minus` glyph there would report a set as matching a target that was never set — and it is
    /// a different absence from the one above, which is why ``PlannedTargetComparison/weight`` is
    /// optional rather than merely sometimes `unchanged`.
    @ViewBuilder private var verdict: some View {
        if let comparison {
            if comparison.isOnTarget {
                onTargetMark
            } else {
                layout {
                    if let moved = comparison.movedWeight {
                        DeltaIndicator(moved.direction, value: rendered(moved.difference))
                    }
                    if comparison.reps != .unchanged {
                        DeltaIndicator(
                            comparison.reps,
                            value: String(
                                localized: LoggingStrings.sessionPlanRepsDelta(
                                    comparison.repsDifference))
                        )
                    }
                }
            }
        }
    }

    /// The match, as a glyph and a word — the pair `G-4.5` asks for on a fact the tint would
    /// otherwise carry alone.
    private var onTargetMark: some View {
        HStack(spacing: Spacing.xxs.points) {
            Image(systemName: "checkmark")
                .accessibilityHidden(true)
            Text(LoggingStrings.sessionPlanOnTarget)
        }
        .font(Typography.metricContext.font)
        .foregroundStyle(ColorToken.positive)
        .accessibilityElement(children: .combine)
    }

    /// The prescription in words — with the load, or saying it named none.
    private var targetText: LocalizedStringResource {
        guard let weight = target.targetWeight else {
            return LoggingStrings.sessionPlanTargetOpenLoad(reps: target.targetReps)
        }
        return LoggingStrings.sessionPlanTarget(
            weight: rendered(weight), reps: target.targetReps)
    }

    /// One load, in the display unit and at the app's precision.
    ///
    /// - Parameter weight: The load.
    /// - Returns: It, rendered.
    private func rendered(_ weight: Weight) -> String {
        weight.formatted(
            AppFormat.weight(WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale))
    }
}

/// The plan's next set, and the one tap that logs it (`FR-15.3.1`, `NFR-15.3`).
///
/// **The command is offered only where the plan named a load.** A blank-weight group prescribes the
/// reps and leaves the load to the lifter (`FR-15.2.2`), so there is nothing to log without asking
/// — the card's **Add set** opens pre-filled there instead, which is one tap more and the only
/// honest number available.
struct PlannedNextSetSection: View {
    /// What the routine prescribed for the next working set.
    let target: PlannedTargetGroup

    /// The unit the target is shown in (`G-3.1`).
    let unit: MassUnit

    /// Logs it exactly as prescribed.
    let log: () -> Void

    /// The heading, the target, and — where there is a load — the command.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(LoggingStrings.sessionPlanNextHeading)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            PlannedTargetLine(target: target, comparison: nil, unit: unit)
            if target.targetWeight != nil {
                // Secondary, on `FR-16.6.4`'s count: this is the same class of action as **Repeat
                // set** and **Log next set** — one more set on one card — and the screen's single
                // accent belongs to the command that ends the workout (`G-7.2`).
                Button(action: log) {
                    Text(LoggingStrings.sessionPlanLogAction)
                }
                .buttonStyle(.secondaryAction(.fill, touch: .logging))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `FR-15.3.4`'s per-exercise check-off — one action for the whole exercise.
///
/// **A checkbox rather than a swipe or a long press**, on the reorder controls' argument: a gesture
/// is invisible to VoiceOver and to Switch Control, and this is the one control on the card the
/// author asked for by name.
///
/// **The glyph carries the state, and so does the label** (`G-4.5`). A filled circle and an empty
/// one differ in shape before they differ in tint, and the command says which way it would go.
struct ExerciseDoneToggle: View {
    /// Whether the lifter has already checked this exercise off.
    let isMarkedDone: Bool

    /// Flips it.
    let toggle: () -> Void

    /// The control, across the card's width.
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: isMarkedDone ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
                Text(LoggingStrings.sessionExerciseDoneAction(isDone: isMarkedDone))
                Spacer(minLength: Spacing.sm.points)
            }
            .font(Typography.actionLabel.font)
            .foregroundStyle(isMarkedDone ? ColorToken.positive : ColorToken.textPrimary)
            .padding(.horizontal, Spacing.md.points)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
            .background(ColorToken.surface, in: .rect(cornerRadius: CornerRadius.control.points))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isMarkedDone ? [.isSelected] : [])
    }
}
