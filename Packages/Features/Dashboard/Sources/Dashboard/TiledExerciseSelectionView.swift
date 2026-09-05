import DerivedValues
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

    /// There are exercises to choose among, split into `FR-16.5.3`'s two sections.
    case ready([ExerciseChoiceSection])

    /// The catalogue could not be read; a retry may work.
    case failed

    /// Which state a load is in. The failure outranks a list already on screen, on the tiles
    /// section's rule.
    ///
    /// - Parameter state: The picker's load.
    /// - Returns: The state to draw.
    /// **`empty` is measured on the catalogue, not on the sections.** A search that matched nothing
    /// is not a catalogue with nothing in it: the first has a query to clear and the second has
    /// nothing to do at all, and ``ExerciseChoiceList`` draws the no-matches state itself, under the
    /// field that causes it.
    static func current(_ state: TiledExerciseSelectionState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        return state.choices.isEmpty ? .empty : .ready(state.sections)
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

    /// The locale the exercise names in this section are resolved in (`FR-1.14.2`), handed to the
    /// state before its read.
    @Environment(\.locale) private var locale

    /// Builds the screen.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises to choose among.
    ///   - settings: Where the selection is stored.
    ///   - records: The app's one recompute actor, for `FR-16.5.1`'s fallback ranking.
    public init(
        catalogue: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: TiledExerciseSelectionState(
                catalogue: catalogue, settings: settings, records: records))
    }

    /// The list, and the read that fills it.
    public var body: some View {
        @Bindable var state = state
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                TiledExerciseSelectionReading(
                    state: TiledExerciseSelectionScreenState.current(state),
                    searchText: $state.searchText,
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
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
    }
}

/// What the picker draws, with no store behind it — `TR-1.12`'s renderable half.
struct TiledExerciseSelectionReading: View {
    /// Which of the four states to draw.
    let state: TiledExerciseSelectionScreenState

    /// What the user typed, bound to the state that holds it.
    @Binding var searchText: String

    /// Whether the last toggle failed to store. Nothing changed if it did.
    let hasFailedWrite: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Adds or removes one exercise's tile.
    let toggle: (UUID) -> Void

    /// The state, and the failed write beneath it where there is one.
    ///
    /// **The three non-`ready` states keep the `Card`; `ready` does not.** `FR-16.5.3`'s sections
    /// are ``DesignSystem/GroupedSection``s, which are cards already, and nesting them inside one
    /// more would draw a surface around a surface. A message, a spinner or an error is a single
    /// block and still wants one.
    @ViewBuilder var body: some View {
        switch state {
        case .loading:
            Card { LoadingStateView() }
        case .empty:
            Card { EmptyStateView(headline: Text(DashboardStrings.tilesChooseEmpty)) }
        case .failed:
            Card {
                ErrorStateView(message: Text(DashboardStrings.tilesChooseError), retry: retry)
            }
        case .ready(let sections):
            ExerciseChoiceList(searchText: $searchText, sections: sections, toggle: toggle)
        }
        if hasFailedWrite {
            // No retry closure: nothing was stored and the row is unchanged, so trying again is the
            // same tap on the same row.
            ErrorStateView(message: Text(DashboardStrings.tilesChooseWriteError))
        }
    }
}
