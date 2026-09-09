import DerivedValues
import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// Which of the picker's four states is current (`FR-1.13.1`).
///
/// ``TiledExerciseSelectionScreenState``'s four, for its reasons: nothing here is derived and the
/// catalogue is local, and `empty` is measured on the catalogue rather than on the sections because
/// a search that matched nothing has a query to clear and ``ExerciseChoiceList`` offers that itself.
enum RecentRecordsExercisesScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// The catalogue holds nothing to choose among.
    case empty

    /// There are exercises to choose among, split into `FR-16.5.3`'s two sections.
    case ready([ExerciseChoiceSection])

    /// The catalogue could not be read; a retry may work.
    case failed

    /// Which state a load is in. The failure outranks a list already on screen.
    ///
    /// - Parameter state: The picker's load.
    /// - Returns: The state to draw.
    static func current(_ state: RecentRecordsExercisesState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        return state.choices.isEmpty ? .empty : .ready(state.sections)
    }
}

/// `FR-17.3.3`'s screen: which lifts the recent-PR feed reports on.
///
/// **The third host of ``ExerciseChoiceList``, and the second to give it a navigation title.** It
/// passes no `title` of its own for that reason — the tile picker's shape rather than the inline
/// list's, which needed a heading because it sat between other headed sections.
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct RecentRecordsExercisesView: View {
    /// The screen's own state.
    @State private var state: RecentRecordsExercisesState

    /// The locale the exercise names are resolved in (`FR-1.14.2`), handed to the state before its
    /// read.
    @Environment(\.locale) private var locale

    /// Builds the screen.
    ///
    /// - Parameters:
    ///   - settings: Where the selection is stored.
    ///   - catalogue: The exercises to choose among.
    ///   - records: The app's one recompute actor, so a tick reaches the feed (`TR-1.5`).
    public init(
        settings: any SettingsRepository,
        catalogue: any ExerciseRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: RecentRecordsExercisesState(
                settings: settings, catalogue: catalogue, records: records))
    }

    /// The list, and the read that fills it.
    public var body: some View {
        @Bindable var state = state
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                RecentRecordsExercisesReading(
                    state: RecentRecordsExercisesScreenState.current(state),
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
        .navigationTitle(Text(DashboardStrings.recentRecordsExercisesTitle))
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
    }
}

/// What the picker draws, with no store behind it — `TR-1.12`'s renderable half.
struct RecentRecordsExercisesReading: View {
    /// Which of the four states to draw.
    let state: RecentRecordsExercisesScreenState

    /// What the user typed, bound to the state that holds it.
    @Binding var searchText: String

    /// Whether the last tick failed to store. Nothing changed if it did.
    let hasFailedWrite: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Adds or removes one lift.
    let toggle: (UUID) -> Void

    /// The state, and the failed write beneath it where there is one.
    ///
    /// **The three non-`ready` states keep the `Card`; `ready` does not**, on
    /// ``TiledExerciseSelectionReading``'s rule: `FR-16.5.3`'s sections are cards already.
    ///
    /// The screen's own accent is spent here and nowhere else: this is the one filled control it
    /// has, and it is a `case .failed:` in a screen's phase switch.
    @ViewBuilder var body: some View {
        switch state {
        case .loading:
            Card { LoadingStateView() }
        case .empty:
            Card { EmptyStateView(headline: Text(DashboardStrings.recentRecordsExercisesEmpty)) }
        case .failed:
            Card {
                ErrorStateView(
                    message: Text(DashboardStrings.recentRecordsExercisesError),
                    retryEmphasis: .primary,
                    retry: retry)
            }
        case .ready(let sections):
            ExerciseChoiceList(searchText: $searchText, sections: sections, toggle: toggle)
        }
        if hasFailedWrite {
            // No retry closure: nothing was stored and the row is unchanged, so trying again is the
            // same tap on the same row.
            ErrorStateView(message: Text(DashboardStrings.recentRecordsExercisesWriteError))
        }
    }
}
