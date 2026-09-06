import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the section's five states is current (`FR-1.13.1`, `FR-1.13.3`, `FR-16.5.2`).
///
/// **Five, and the empty one is a real state rather than a degenerate list.** A lifter who removes
/// every tile has configured something, and a screen that answered that with a blank band would be
/// the outcome `FR-1.13.1` exists to rule out. The individual refusals are *not* states here — they
/// are a tile's, one per tile, so a squat with an estimate sits beside a bench without one — until
/// *no* tile has one, which is ``noEstimates(_:)`` and is the section's own state rather than a
/// tile's (`FR-16.5.2`). A refusal repeated on every row of a section says one thing, and says it
/// in the place a reader has to assemble it from three.
///
/// **``noEstimates(_:)`` still carries its tiles**, because a tile holds more than its estimate:
/// the training max under it is a number the lifter typed and `FR-15.1.8` says it must not be
/// invisible, and the exercise a lifter has just been handed a coach's number for is precisely the
/// one with no estimate yet. What the section takes over is the *reason* — said once above the
/// tiles rather than once per tile — not the tiles themselves.
///
/// No offline state: the numbers are computed from local rows, so there is no fetch to be offline
/// for (`G-2.1`).
enum EstimatedMaxTilesScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// Nothing is tiled — either the user removed every tile, or every one they chose names an
    /// exercise the catalogue no longer holds.
    case noneTiled

    /// There are tiles to draw, and at least one of them has a number.
    case ready([EstimatedMaxTile])

    /// Exercises are tiled and not one of them has an estimate — a new install, or a lifter who has
    /// tiled three lifts they do not train. The tiles are still drawn, without their own reasons.
    case noEstimates([EstimatedMaxTile])

    /// They could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks tiles already on screen**, on `ExerciseEstimateSection`'s rule: a read
    /// that failed leaves the last answer in place, and drawing it under no diagnostic presents
    /// stale numbers as current ones — worst of all for a value whose whole point is being current.
    ///
    /// - Parameter state: The section's load.
    /// - Returns: The state to draw.
    static func current(_ state: EstimatedMaxTilesState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        guard !state.tiles.isEmpty else { return .noneTiled }
        guard state.tiles.contains(where: \.hasEstimate) else { return .noEstimates(state.tiles) }
        return .ready(state.tiles)
    }
}

/// `FR-1.9.1`'s e1RM tiles, with the delta since the previous value and the way to change which
/// exercises appear.
struct EstimatedMaxTilesSection: View {
    /// The section's own state.
    @State private var state: EstimatedMaxTilesState

    /// The locale the exercise names in this section are resolved in (`FR-1.14.2`), handed to the
    /// state before its read.
    @Environment(\.locale) private var locale

    /// Builds the section.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor (`TR-1.6`).
    ///   - catalogue: The exercises.
    ///   - settings: The settings row, for the selection and the unit.
    ///   - trainingMaxes: Where `FR-15.1.8`'s number under each tile comes from.
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        trainingMaxes: any TrainingMaxRepository
    ) {
        _state = State(
            initialValue: EstimatedMaxTilesState(
                records: records,
                catalogue: catalogue,
                settings: settings,
                trainingMaxes: trainingMaxes))
    }

    /// The tiles and the picker link, plus the two tasks that keep them current — a read that
    /// finishes, and a subscription that runs until the screen goes away.
    var body: some View {
        EstimatedMaxTilesReading(
            state: EstimatedMaxTilesScreenState.current(state),
            unit: state.unit,
            retry: { Task { await state.load() } }
        )
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
        .task { await state.observeChanges() }
    }
}

/// What the tiles section draws, with no store behind it.
///
/// **Split out so `TR-1.12` has something to render**, on `ExerciseEstimateReading`'s rule: the
/// section above is a `.task` over three repositories, and a reference recorded through one is a
/// reference over a spinner.
struct EstimatedMaxTilesReading: View {
    /// Which of the five states to draw.
    let state: EstimatedMaxTilesScreenState

    /// The unit the loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// What the error state's retry does.
    let retry: () -> Void

    /// The heading, whichever state is current, and the way to the picker.
    var body: some View {
        GroupedSection(Text(DashboardStrings.tilesTitle)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .noneTiled:
                // T-1.09's empty state and not its insufficient-data one: nothing is missing from a
                // computation here, the list of things to compute is empty — and the way to fill it
                // is the link below, which is why this state carries no action of its own.
                EmptyStateView(
                    symbolName: "square.grid.2x2",
                    headline: Text(DashboardStrings.tilesNoneChosen),
                    message: Text(DashboardStrings.tilesNoneChosenMessage))
            case .failed:
                ErrorStateView(message: Text(DashboardStrings.tilesError), retryEmphasis: .secondary, retry: retry)
            case .noEstimates(let tiles):
                InsufficientDataView(message: Text(DashboardStrings.tilesNoEstimates))
                ForEach(tiles) { tile in
                    EstimatedMaxTileView(tile: tile, unit: unit, explainsAbsence: false)
                }
            case .ready(let tiles):
                ForEach(tiles) { tile in
                    EstimatedMaxTileView(tile: tile, unit: unit)
                }
            }
            NavigationLink(value: Route.dashboard(.estimatedMaxExercises)) {
                Text(DashboardStrings.tilesChooseAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.brandAccent)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: TouchTarget.standard.points,
                        alignment: .leading
                    )
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

/// One exercise's tile: the number, or the reason there is none (`FR-1.9.1`, `FR-1.13.3`).
///
/// **A tile and an explanation are the same width and never both drawn.** The estimate's absence is
/// not a blank numeral with a footnote — that is the shape `FR-1.13.3` names — so where the numeral
/// would be a refused estimate puts the reason instead, on one line beside the exercise, so the
/// reader still knows which lift is being talked about (`FR-16.5.2`).
struct EstimatedMaxTileView: View {
    /// The exercise and its estimate.
    let tile: EstimatedMaxTile

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether this tile names its own reason for having no estimate.
    ///
    /// **`false` only under ``EstimatedMaxTilesScreenState/noEstimates(_:)``**, where every tile
    /// would give the same answer and the section has already given it once. What stays is the
    /// exercise and its training max — the tile's job there is `FR-15.1.8`, not the refusal.
    var explainsAbsence = true

    /// Which locale the load is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// Whichever of the estimate's two contents this tile holds.
    @ViewBuilder var body: some View {
        switch tile.estimate.content {
        case .record(let record):
            metric(record.weight) {
                delta
                trainingMax
            }
        case .absence(let absence):
            unestimatedTile(absence)
        }
    }

    /// The whole of a tile with no number, and the long sentence behind its short line.
    ///
    /// **The hint is applied rather than emptied where the section has spoken.** The line is short
    /// so the tile can be one line; the sentence it was shortened from is what a reader who cannot
    /// see the layout gets (`G-4.2`), as a hint rather than a label so the name and the short
    /// reason still read first. Under ``EstimatedMaxTilesScreenState/noEstimates(_:)`` there is no
    /// short line to expand, and a hint expanding nothing is worse than none.
    ///
    /// - Parameter absence: Why there is no number.
    /// - Returns: The tile.
    @ViewBuilder private func unestimatedTile(_ absence: EstimateAbsence) -> some View {
        let content = VStack(alignment: .leading, spacing: Spacing.xs.points) {
            unestimated(explainsAbsence ? absence : nil)
            trainingMax
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)

        if explainsAbsence {
            content.accessibilityHint(
                Text(DashboardStrings.tileAbsence(absence, days: tile.estimate.lookback.days)))
        } else {
            content
        }
    }

    /// A tile with no estimate: the exercise and, beside it, why there is no number
    /// (`FR-16.5.2`).
    ///
    /// **One line, not an empty-state block.** Three exercises the app cannot estimate used to be
    /// three icons and three sentences stacked where three numbers belong, which is a screen
    /// apologising at the size of the thing it is apologising for. The reason is still named — the
    /// short form of the same seven — and the sentence is still what VoiceOver reads, above.
    ///
    /// **The name keeps `metricLabel`, so it lines up with the tiles that do have numbers.** A tile
    /// without an estimate is the same tile, one line shorter.
    ///
    /// - Parameter absence: Why there is no number, or `nil` where the section has said it already.
    /// - Returns: The line.
    private func unestimated(_ absence: EstimateAbsence?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
            Text(verbatim: tile.name)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer(minLength: Spacing.sm.points)
            if let absence {
                Text(DashboardStrings.tileAbsenceShort(absence, days: tile.estimate.lookback.days))
                    .font(Typography.metricContext.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// The tile itself: the exercise's name, its estimate, and whatever context line applies.
    private func metric<Context: View>(
        _ weight: Weight, @ViewBuilder context: () -> Context
    ) -> some View {
        MetricTile(
            label: Text(verbatim: tile.name),
            value: Text(
                weight,
                format: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale)),
            context: context
        )
    }

    /// `FR-15.1.8`'s training max, where the exercise has one.
    ///
    /// **One line, secondary, and labelled by a word.** The two numbers are different claims about
    /// the same lift — one observed, one set by a coach — and a second bare numeral under the first
    /// would be unreadable as either. Where there is none the line is absent: no zero, no dash.
    ///
    /// **Drawn under the refusal as well as under the estimate**, because `FR-15.1.8`'s second
    /// sentence is that the training max must not be invisible — and an exercise the app cannot
    /// estimate is exactly the one a coach has just handed a number for. It sits *beneath* the
    /// insufficient-data view rather than inside it: the explanation is about the estimate, and
    /// this is a separate statement about a number that does exist.
    @ViewBuilder private var trainingMax: some View {
        if let trainingMax = tile.trainingMax {
            Text(
                DashboardStrings.tileTrainingMax(
                    trainingMax.formatted(
                        AppFormat.weight(
                            WeightDisplay(unit: unit, resolving: displayPrecision),
                            locale: locale))))
        }
    }

    /// `FR-1.9.1`'s delta, or the line that says there is nothing to compare against.
    ///
    /// **Colour is never the only cue** — that is ``DesignSystem/DeltaIndicator``'s guarantee (`G-4.5`), and the
    /// magnitude is formatted here because the indicator writes the sign itself.
    @ViewBuilder private var delta: some View {
        if let delta = tile.estimate.delta {
            DeltaIndicator(
                Self.direction(of: delta),
                value: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale
                )
                .format(Weight(grams: abs(delta.grams))))
        } else {
            Text(DashboardStrings.tileNoPrevious)
        }
    }

    /// Which way the estimate moved.
    ///
    /// **Only ``DesignSystem/DeltaDirection/increase`` is reachable today**, and the other two are
    /// written out rather than folded away. ``DerivedValues/EstimatedMax/delta`` is strictly
    /// positive wherever it is not `nil` — its own doc comment has the argument — so a fall and a
    /// zero both arrive here as *no previous value* instead. This function reads the arithmetic
    /// rather than restating that: a definition of "the previous value" that can report a decline
    /// costs this screen nothing, where a function that had collapsed the cases would have to be
    /// found and re-derived first.
    ///
    /// - Parameter delta: The signed change.
    /// - Returns: The direction to draw it in.
    static func direction(of delta: Weight) -> DeltaDirection {
        if delta.grams > 0 { return .increase }
        return delta.grams < 0 ? .decrease : .unchanged
    }
}
