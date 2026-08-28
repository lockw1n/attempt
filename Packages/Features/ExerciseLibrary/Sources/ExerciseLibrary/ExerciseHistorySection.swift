import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// This exercise's logged history, newest first and grouped by session (`FR-1.5.2`).
///
/// **A section with a read of its own, inside a screen that has already done one.** It holds its own
/// ``ExerciseHistoryState`` and runs its own `.task`, so a workout store that cannot answer costs the
/// reader this section and not `FR-1.1.6`'s movement, equipment and notes — the split
/// ``ExerciseDetailState/hasLoggedSets()`` makes by swallowing, made properly now that there is
/// something to report.
struct ExerciseHistorySection: View {
    @State private var state: ExerciseHistoryState

    /// Builds the section over the exercise it is about.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's history to show.
    ///   - workouts: Where it is read from.
    ///   - settings: The settings row, for the unit the loads are shown in.
    init(
        exerciseID: UUID,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository
    ) {
        _state = State(
            initialValue: ExerciseHistoryState(
                exerciseID: exerciseID,
                workouts: workouts,
                settings: settings
            )
        )
    }

    /// The heading, then whichever of the section's four states is current.
    ///
    /// `load()` on every appearance rather than once: a set logged in another tab, or edited on a
    /// past session's screen, has to be here on the way back — the state's own note.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.historySection)) {
            switch ExerciseHistoryScreenState.current(state.phase) {
            case .loading:
                LoadingStateView()
            case .noneYet:
                InsufficientDataView(message: Text(ExerciseLibraryStrings.historyNone))
            case .failed:
                ErrorStateView(
                    message: Text(ExerciseLibraryStrings.historyError),
                    retry: { Task { await state.load() } }
                )
            case .ready:
                history
            }
        }
        .task { await state.load() }
    }

    /// The groups, then the way past the page boundary.
    @ViewBuilder private var history: some View {
        ForEach(state.groups) { group in
            ExerciseHistoryGroupView(group: group, unit: state.displayUnit)
        }
        if state.extendFailure != nil {
            // Beside the groups already built rather than in place of them: nothing on screen was
            // lost. It stands **in place of the control** rather than under it, because its retry
            // is that same command — two tappable affordances for one action, one of them silent
            // about the failure, is the worse of the two readings (`FR-1.13.1`).
            ErrorStateView(
                message: Text(ExerciseLibraryStrings.historyMoreError),
                retry: { Task { await state.loadMore() } }
            )
        } else if state.hasMore {
            Button {
                Task { await state.loadMore() }
            } label: {
                Text(ExerciseLibraryStrings.historyMore)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One training day's work, under its date (`FR-1.5.2`).
///
/// Taking the value rather than the state, on ``ExerciseFactsSection``'s rule: this is what the
/// snapshot renders, and a reference over the whole section would be a reference over a `.task` that
/// reads a store.
struct ExerciseHistoryGroupView: View {
    /// The session's date and its sets.
    let group: ExerciseSessionHistory

    /// The unit the loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the date is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The date, then the sets under it.
    ///
    /// The date is a **heading** for VoiceOver rather than a plain label: it is what a reader
    /// navigating by heading jumps between, and without the trait the only way through the section is
    /// row by row (`G-4.2`).
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(group.date, format: AppFormat.date(locale: locale))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(group.sets) { set in
                ExerciseHistoryRow(loggedSet: set, unit: unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One logged set, in `FR-1.5.2`'s `weight × reps @ RPE` form.
///
/// **The rating is omitted rather than blank when it was not recorded**, which is the requirement's
/// own wording: a trailing `@` with nothing after it claims a rating that was never given.
///
/// **The multiplication sign is drawn and hidden from VoiceOver**, and the two numerals either side
/// carry labels of their own — `SetRow`'s rule, for its reason: it is punctuation between two
/// numbers, and read aloud it is noise.
///
/// **A warmup says so in a word, and a failed set carries a glyph.** Dimmer text and red text are
/// colour, which `G-4.5` will not let carry a distinction alone. The failed mark is drawn only on the
/// sets that failed, unlike the live row's — there the glyph is a *control* and has to exist on every
/// row to be reachable, where this is a readout and only needs the mark that distinguishes.
struct ExerciseHistoryRow: View {
    /// The set this row reports.
    ///
    /// Named `loggedSet` rather than `set`, which at the head of a computed property's body is
    /// parsed as an accessor keyword rather than as this property.
    let loggedSet: SetEntry

    /// The unit its load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// How large the user reads at — what decides whether this row is a line or a stack (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The load, the repetitions, the rating and the outcome — one VoiceOver element, because they
    /// are one set, and no controls, because a past set is not editable from here (`FR-1.2.7`'s edit
    /// is the past-session screen's).
    var body: some View {
        layout {
            // A child of the switching layout rather than a word inside the values' own stack: at
            // `accessibility3` the two share a line that fits neither, and the label — the shorter
            // of the two — is what gives way, breaking as "Warmu / p". Stacked, it takes its own
            // line and the load keeps the width it needs.
            if loggedSet.isWarmup {
                warmupLabel
            }
            HStack(spacing: Spacing.sm.points) {
                Text(
                    loggedSet.weight,
                    format: AppFormat.weight(
                        WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)
                )
                .font(valueFont)
                .foregroundStyle(valueColour)
                Image(systemName: "multiply")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
                Text(loggedSet.reps, format: AppFormat.count(locale: locale))
                    .font(valueFont)
                    .foregroundStyle(valueColour)
                    .accessibilityLabel(Text(ExerciseLibraryStrings.historyReps(loggedSet.reps)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.sm.points) {
                rating
                outcome
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A line at ordinary sizes and a stack at `NFR-1.10`'s.
    ///
    /// `SetRow`'s measured switch, applied to a row with the same load in it: at `accessibility3` a
    /// rating pushed to the trailing edge takes the width `102.5 kg` needs and the number breaks
    /// mid-digit. One `AnyLayout` rather than two branches of the body, so the two halves keep their
    /// identity — and with it the accessibility element — across the switch.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs.points))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.sm.points))
    }

    /// `G-1.8`'s warmup flag, said in a word.
    ///
    /// Drawn only where the flag is set — the caller decides, so that a working set contributes no
    /// subview to the layout above and therefore no leading gap.
    private var warmupLabel: some View {
        Text(ExerciseLibraryStrings.historyWarmup)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textTertiary)
            .fixedSize()
    }

    /// The rating, where the set carries one.
    @ViewBuilder private var rating: some View {
        if let rpe = loggedSet.rpe {
            Text(
                ExerciseLibraryStrings.historyRPE(
                    rpe.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
                )
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// `FR-1.2.5`'s outcome, drawn only where the set failed.
    @ViewBuilder private var outcome: some View {
        if !loggedSet.isCompleted {
            Image(systemName: "xmark.circle")
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.negative)
                .accessibilityLabel(Text(ExerciseLibraryStrings.historyFailed))
        }
    }

    /// The load and the repetitions' role in the type scale. Warmups sit one step down, `SetRow`'s
    /// de-emphasis applied to the same two numbers.
    private var valueFont: Font {
        loggedSet.isWarmup ? Typography.caption.font : Typography.numericValue.font
    }

    /// Their place in the colour ramp.
    ///
    /// A failed set is red wherever it sits in that ramp (`G-7.3`), so the outcome outranks the
    /// warmup de-emphasis rather than compounding with it — a failed warmup is a missed lift too.
    private var valueColour: ColorToken {
        guard loggedSet.isCompleted else { return ColorToken.negative }
        return loggedSet.isWarmup ? ColorToken.textSecondary : ColorToken.textPrimary
    }
}
