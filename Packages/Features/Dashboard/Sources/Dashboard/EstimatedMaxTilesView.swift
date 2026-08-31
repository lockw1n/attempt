import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the section's four states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Four, and the empty one is a real state rather than a degenerate list.** A lifter who removes
/// every tile has configured something, and a screen that answered that with a blank band would be
/// the outcome `FR-1.13.1` exists to rule out. The individual refusals are *not* states here — they
/// are a tile's, one per tile, so a squat with an estimate sits beside a bench without one.
///
/// No offline state: the numbers are computed from local rows, so there is no fetch to be offline
/// for (`G-2.1`).
enum EstimatedMaxTilesScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// Nothing is tiled — either the user removed every tile, or every one they chose names an
    /// exercise the catalogue no longer holds.
    case noneTiled

    /// There are tiles to draw.
    case ready([EstimatedMaxTile])

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
        return state.tiles.isEmpty ? .noneTiled : .ready(state.tiles)
    }
}

/// `FR-1.9.1`'s e1RM tiles, with the delta since the previous value and the way to change which
/// exercises appear.
struct EstimatedMaxTilesSection: View {
    /// The section's own state.
    @State private var state: EstimatedMaxTilesState

    /// Builds the section.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor (`TR-1.6`).
    ///   - catalogue: The exercises.
    ///   - settings: The settings row, for the selection and the unit.
    init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        _state = State(
            initialValue: EstimatedMaxTilesState(
                records: records, catalogue: catalogue, settings: settings))
    }

    /// The tiles and the picker link, plus the two tasks that keep them current — a read that
    /// finishes, and a subscription that runs until the screen goes away.
    var body: some View {
        EstimatedMaxTilesReading(
            state: EstimatedMaxTilesScreenState.current(state),
            unit: state.unit,
            retry: { Task { await state.load() } }
        )
        .task { await state.load() }
        .task { await state.observeChanges() }
    }
}

/// What the tiles section draws, with no store behind it.
///
/// **Split out so `TR-1.12` has something to render**, on `ExerciseEstimateReading`'s rule: the
/// section above is a `.task` over three repositories, and a reference recorded through one is a
/// reference over a spinner.
struct EstimatedMaxTilesReading: View {
    /// Which of the four states to draw.
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
                ErrorStateView(message: Text(DashboardStrings.tilesError), retry: retry)
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
/// not a blank numeral with a footnote — that is the shape `FR-1.13.3` names — so a refused estimate
/// replaces the tile with `T-1.09`'s insufficient-data view, headed by the exercise so the reader
/// still knows which lift is being talked about.
struct EstimatedMaxTileView: View {
    /// The exercise and its estimate.
    let tile: EstimatedMaxTile

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the load is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// Whichever of the estimate's three contents this tile holds.
    @ViewBuilder var body: some View {
        switch tile.estimate.content {
        case .record(let record):
            metric(record.weight) { delta }
        case .manual(let weight):
            metric(weight) { Text(DashboardStrings.tileManual) }
        case .absence(let absence):
            InsufficientDataView(
                headline: Text(verbatim: tile.name),
                message: Text(
                    DashboardStrings.tileAbsence(absence, days: tile.estimate.lookback.days)))
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
