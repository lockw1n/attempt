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
/// **Four states over eight sentences.** The insufficient-data case carries `FR-1.7.1`'s reason
/// rather than branching on it: a screen that had a state per refusal would have to be changed by
/// every guard added to `E1RMCalculator`, where this one only needs a string.
///
/// **There is no manual state, since `D-16.1`.** `FR-1.7.5` is `WITHDRAWN`: the estimate is
/// observed, and the number a lifter enters is the training max the section above this one holds.
///
/// No empty and no offline state, on the records section's rule — the estimate is computed from
/// local rows, and "no set says anything about a maximum" is `FR-1.13.3`'s case rather than an
/// emptied list.
enum ExerciseEstimateScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// There is a computed number, under the formula and window it was produced with, and the
    /// session holding the set it came from where that resolved (`FR-1.7.4`).
    case ready(DatedRecord, formula: E1RMFormulaID, days: Int, sessionID: UUID?)

    /// There is none, and this is why.
    case insufficient(EstimateAbsence, days: Int)

    /// It could not be computed; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The estimate's own failure, not the merged one**, on `ExerciseRecordsScreenState`'s rule:
    /// this section draws no rep max and must not report one as unreadable.
    ///
    /// **The failure outranks the last good answer.** A read that failed leaves the previous
    /// estimate in place, and drawing it under no diagnostic presents a stale number as a current
    /// one — which for a value the whole point of is being *current* is the worse of the two.
    static func current(_ state: ExerciseRecordsState) -> Self {
        if state.estimateFailure != nil { return .failed }
        guard let estimate = state.estimate else { return .loading }
        switch estimate.content {
        case .record(let record):
            return .ready(
                record,
                formula: estimate.formula,
                days: estimate.lookback.days,
                sessionID: state.estimateSourceSession)
        case .absence(let absence):
            return .insufficient(absence, days: estimate.lookback.days)
        }
    }

}

/// This exercise's current estimated one-rep maximum (`FR-1.7.1`).
///
/// **A section with a read of its own**, on ``ExerciseRecordsSection``'s rule and for its reason.
/// It declines the rep maxes in both its read and its subscription: the two halves walk different
/// stores, and a section drawing one number would otherwise re-read a cached list and re-resolve its
/// links every time a set was logged against this exercise.
///
/// **It is the section a formula change moves** (`FR-1.7.3`). A rep max reads no setting, so the
/// pipeline's `everyExercise` announcement reaches exactly this — which is why the subscription
/// keeps the estimate half where the records section drops it.
struct ExerciseEstimateSection: View {
    @State private var state: ExerciseRecordsState

    /// The unit the load is shown in (`G-3.1`) — the screen's own read, on the records section's
    /// rule, and kilograms until it lands.
    @State private var unit: MassUnit = .kilograms

    /// Where the display unit comes from.
    private let settings: any SettingsRepository

    /// Builds the section over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's estimate to show.
    ///   - records: The app's one recompute actor (`TR-1.6`), so a set logged anywhere — and a
    ///     formula chosen in Settings — reaches this.
    ///   - settings: The settings row, for the unit the load is shown in.
    init(exerciseID: UUID, records: PersonalRecordRecomputer, settings: any SettingsRepository) {
        self.settings = settings
        _state = State(initialValue: ExerciseRecordsState(exerciseID: exerciseID, recomputer: records))
    }

    /// The heading and its reading, plus the two tasks that keep it current.
    ///
    /// **Two tasks, because they have different lifetimes** — the first is a read that finishes, the
    /// second runs until the screen goes away, which is what `TR-1.5`'s subscription is.
    var body: some View {
        ExerciseEstimateReading(
            state: ExerciseEstimateScreenState.current(state),
            unit: unit,
            retry: { Task { await state.loadEstimate() } }
        )
        .task {
            await state.loadEstimate()
            if let stored = try? await settings.settings().displayUnit { unit = stored }
        }
        .task { await state.observeChanges(includingRecords: false) }
    }
}

/// What the estimate section draws, with no store behind it.
///
/// **Split out so `TR-1.12` has something to render.** The section above is a `.task` over a
/// repository, and a reference recorded through one is a reference over a loading spinner.
struct ExerciseEstimateReading: View {
    /// Which of the four states to draw.
    let state: ExerciseEstimateScreenState

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// What the error state's retry does.
    let retry: () -> Void

    /// Which locale the load is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The heading, and whichever of the four states is current.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.e1rmSection)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .ready(let record, let formula, let days, let sessionID):
                estimate(record, formula: formula, days: days, sessionID: sessionID)
            case .insufficient(let absence, let days):
                InsufficientDataView(
                    message: Text(ExerciseLibraryStrings.e1rmAbsence(absence, days: days)))
            case .failed:
                ErrorStateView(message: Text(ExerciseLibraryStrings.e1rmError), retry: retry)
            }
        }
    }

    /// The number, with what produced it under it, linked to the set it came from.
    ///
    /// **The provenance line is not decoration.** The same sets estimate differently under each of
    /// the six formulas and over each window, so a bare number is one a lifter cannot reconcile with
    /// anything they have seen elsewhere — and `FR-1.7.3` means it can move without a set being
    /// logged.
    ///
    /// **The tile is the link, and only where the source set resolved** — `ExerciseRecordRow`'s
    /// rule and for its reason: a tile whose set could not be located is drawn as a number rather
    /// than as a control that would navigate nowhere. The destination is a `Route.history` pushed
    /// onto whichever stack this screen is on, not a tab switch, so Back returns to the exercise.
    @ViewBuilder private func estimate(
        _ record: DatedRecord, formula: E1RMFormulaID, days: Int, sessionID: UUID?
    ) -> some View {
        let tile = MetricTile(
            label: Text(ExerciseLibraryStrings.e1rmValue),
            value: Text(
                record.weight,
                format: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale))
        ) {
            Text(
                ExerciseLibraryStrings.e1rmProvenance(
                    String(localized: ExerciseLibraryStrings.name(for: formula)), days: days))
        }
        if let sessionID {
            NavigationLink(value: Route.history(.session(sessionID: sessionID))) {
                // `contentShape` is what makes the *tile* the target rather than its glyphs.
                // Measured in the simulator: without it a tap beside the number — most of the
                // tile's width — reaches nothing, and the link looks broken rather than absent.
                tile.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(ExerciseLibraryStrings.e1rmSourceHint))
        } else {
            tile
        }
    }
}
