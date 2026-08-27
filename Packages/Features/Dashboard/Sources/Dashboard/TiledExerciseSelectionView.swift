import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// Which of the picker's four states is current (`FR-1.13.1`).
///
/// No insufficient-data state and no offline one: nothing here is derived, and the catalogue is
/// local (`G-2.1`). The empty case is a catalogue with nothing in it, which a seeded install cannot
/// reach — but a restore of an emptied store can, so it is a state rather than an impossibility.
enum TiledExerciseSelectionScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// The catalogue holds nothing that can be tiled.
    case empty

    /// There are exercises to choose among.
    case ready([TiledExerciseChoice])

    /// The catalogue could not be read; a retry may work.
    case failed

    /// Which state a load is in. The failure outranks a list already on screen, on the tiles
    /// section's rule.
    ///
    /// - Parameter state: The picker's load.
    /// - Returns: The state to draw.
    static func current(_ state: TiledExerciseSelectionState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        return state.choices.isEmpty ? .empty : .ready(state.choices)
    }
}

/// `FR-1.9.1`'s "configurable which exercises appear": the catalogue, with a tick against every
/// exercise the dashboard tiles.
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct TiledExerciseSelectionView: View {
    /// The screen's own state.
    @State private var state: TiledExerciseSelectionState

    /// Builds the screen.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose among.
    ///   - settings: Where the selection is stored.
    public init(catalogue: any ExerciseRepository, settings: any SettingsRepository) {
        _state = State(
            initialValue: TiledExerciseSelectionState(catalogue: catalogue, settings: settings))
    }

    /// The list, and the read that fills it.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                TiledExerciseSelectionReading(
                    state: TiledExerciseSelectionScreenState.current(state),
                    hasFailedWrite: state.writeFailure != nil,
                    retry: { Task { await state.load() } },
                    toggle: { exerciseID in Task { await state.toggle(exerciseID) } }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(DashboardStrings.tilesChooseTitle))
        .task { await state.load() }
    }
}

/// What the picker draws, with no store behind it — `TR-1.12`'s renderable half.
struct TiledExerciseSelectionReading: View {
    /// Which of the four states to draw.
    let state: TiledExerciseSelectionScreenState

    /// Whether the last toggle failed to store. Nothing changed if it did.
    let hasFailedWrite: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Adds or removes one exercise's tile.
    let toggle: (UUID) -> Void

    /// The state, and the failed write beneath it where there is one.
    @ViewBuilder var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                switch state {
                case .loading:
                    LoadingStateView()
                case .empty:
                    EmptyStateView(headline: Text(DashboardStrings.tilesChooseEmpty))
                case .failed:
                    ErrorStateView(message: Text(DashboardStrings.tilesChooseError), retry: retry)
                case .ready(let choices):
                    ForEach(choices) { choice in
                        TiledExerciseRow(choice: choice, toggle: toggle)
                    }
                }
            }
        }
        if hasFailedWrite {
            // No retry closure: nothing was stored and the row is unchanged, so trying again is the
            // same tap on the same row.
            ErrorStateView(message: Text(DashboardStrings.tilesChooseWriteError))
        }
    }
}

/// One exercise, and whether it is tiled.
///
/// **A `Toggle` rather than a tick and a tap target**, so the control announces its own state to
/// VoiceOver (`G-4.2`) instead of leaving it to a glyph.
struct TiledExerciseRow: View {
    /// The exercise and its current membership.
    let choice: TiledExerciseChoice

    /// What flipping it does.
    let toggle: (UUID) -> Void

    /// The row.
    var body: some View {
        Toggle(
            isOn: Binding(get: { choice.isTiled }, set: { _ in toggle(choice.exerciseID) })
        ) {
            Text(verbatim: choice.name)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .tint(ColorToken.brandAccent)
        .frame(minHeight: TouchTarget.standard.points)
    }
}
