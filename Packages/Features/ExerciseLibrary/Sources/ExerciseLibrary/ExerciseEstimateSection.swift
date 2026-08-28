import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the section's five states is current (`FR-1.13.1`, `FR-1.13.3`, `FR-1.7.5`).
///
/// **Five states over eight sentences.** The insufficient-data case carries `FR-1.7.1`'s reason
/// rather than branching on it: a screen that had a state per refusal would have to be changed by
/// every guard added to `E1RMCalculator`, where this one only needs a string.
///
/// **A manual override is a state and not a flag on ``ready(_:formula:days:)``.** It has no source
/// set to link to, no formula behind it and no window it was read over — three of the four things
/// that case carries — so a Boolean would leave every one of them meaningless-but-present.
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

    /// The user entered the number themselves, and it outranks whatever the sets say (`FR-1.7.5`).
    case manual(Weight)

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
        case .manual(let weight):
            return .manual(weight)
        case .absence(let absence):
            return .insufficient(absence, days: estimate.lookback.days)
        }
    }

    /// The number on screen, or `nil` when there is none — what the override field starts from, so
    /// that a user adjusting an estimate types over it rather than retyping it. Reachable in both
    /// directions: an override is editable without being cleared first.
    var weight: Weight? {
        switch self {
        case .ready(let record, _, _, _): record.weight
        case .manual(let weight): weight
        case .loading, .insufficient, .failed: nil
        }
    }

    /// What the override field opens holding: the number above it, at **the step that number is
    /// displayed at**, or empty where there is none to type over.
    ///
    /// **Not the exact grams.** The tile is snapped to `G-3.3`'s step and a computed estimate lands
    /// on one only by accident, so a field seeded with the exact value opens reading `116,667` under
    /// a tile reading `116,5` — and a save with no edit stores a number the user never saw. See
    /// ``Localization/LocalizedNumberField/render(_:in:at:locale:)``.
    ///
    /// - Parameters:
    ///   - unit: The unit the tile is drawn in (`G-3.1`).
    ///   - locale: The locale it is drawn for (`G-3.4`).
    /// - Returns: The field's opening contents.
    func prefill(in unit: MassUnit, locale: Locale) -> String {
        guard let weight else { return "" }
        return LocalizedNumberField.render(
            weight, in: unit, at: .default(for: unit), locale: locale)
    }

    /// Whether an override is what is on screen, which decides which of `FR-1.7.5`'s commands
    /// the section offers.
    var isManual: Bool {
        if case .manual = self { return true }
        return false
    }

    /// Whether the section knows what is in force yet.
    ///
    /// **The override controls are hidden until it does.** Offering "set manually" over a spinner
    /// invites a write against a number nobody has read, and offering it over the error state
    /// invites one against a store that has just refused to answer.
    var isSettled: Bool {
        switch self {
        case .loading, .failed: false
        case .ready, .manual, .insufficient: true
        }
    }
}

/// This exercise's current estimated one-rep maximum (`FR-1.7.1`), and `FR-1.7.5`'s override of it.
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

    /// What is in the override field, or `nil` when it is not open.
    ///
    /// **One optional rather than a string and a flag**, because "not editing" and "editing an
    /// empty field" are different states and the second one is reachable: an exercise with no
    /// estimate at all opens the field blank.
    @State private var draft: String?

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
            draft: $draft,
            hasFailedWrite: state.manualFailure != nil,
            retry: { Task { await state.loadEstimate() } },
            commit: { weight in
                // The field closes on the command rather than on its result: the write reports its
                // own failure below, and a field left open over one is a second copy of the number
                // the user is being told about.
                draft = nil
                Task { await state.setManualEstimate(weight) }
            }
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
    /// Which of the five states to draw.
    let state: ExerciseEstimateScreenState

    /// The unit the load is shown in (`G-3.1`).
    let unit: MassUnit

    /// What is in the override field, or `nil` when it is closed.
    @Binding var draft: String?

    /// Whether the last override write failed. The number on screen is unchanged either way.
    let hasFailedWrite: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Stores an override, or clears it with `nil` — `FR-1.7.5`'s two directions, one call.
    let commit: (Weight?) -> Void

    /// Which locale the load is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view — `nil` outside the app, where
    /// the unit's own factory step stands.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The heading, whichever of the five states is current, and the override's own controls.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.e1rmSection)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .ready(let record, let formula, let days, let sessionID):
                estimate(record, formula: formula, days: days, sessionID: sessionID)
            case .manual(let weight):
                manual(weight)
            case .insufficient(let absence, let days):
                InsufficientDataView(
                    message: Text(ExerciseLibraryStrings.e1rmAbsence(absence, days: days)))
            case .failed:
                ErrorStateView(message: Text(ExerciseLibraryStrings.e1rmError), retry: retry)
            }
            if state.isSettled { override }
            if hasFailedWrite {
                // No retry closure: nothing was stored and the field has closed, so the way to try
                // again is the command itself, which is on screen directly above this.
                ErrorStateView(message: Text(ExerciseLibraryStrings.e1rmOverrideError))
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

    /// The overridden number, marked as one (`FR-1.7.5`).
    ///
    /// **No link and no provenance line.** There is no source set to navigate to, and naming the
    /// formula under a number it took no part in would be the misattribution the badge exists to
    /// prevent.
    private func manual(_ weight: Weight) -> some View {
        MetricTile(
            label: Text(ExerciseLibraryStrings.e1rmValue),
            value: Text(
                weight,
                format: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale))
        ) {
            Text(ExerciseLibraryStrings.e1rmManualBadge)
        }
        .accessibilityElement(children: .combine)
    }

    /// `FR-1.7.5`'s controls: the field while it is open, and otherwise the commands that apply.
    ///
    /// **An override is editable, not only revertible.** Offering the way back alone would make
    /// adjusting a manual number a two-step round trip through the computed one — which writes,
    /// announces and re-walks the history to produce a value the user is about to overwrite, and
    /// loses the figure they were adjusting on the way.
    @ViewBuilder private var override: some View {
        if draft != nil {
            editor
        } else if state.isManual {
            command(Text(ExerciseLibraryStrings.e1rmOverrideEdit)) { openEditor() }
            command(Text(ExerciseLibraryStrings.e1rmOverrideRevert)) { commit(nil) }
        } else {
            command(Text(ExerciseLibraryStrings.e1rmOverrideAction)) { openEditor() }
        }
    }

    /// Opens the field over whatever number is on screen. See ``ExerciseEstimateScreenState/prefill(in:locale:)``.
    private func openEditor() {
        draft = state.prefill(in: unit, locale: locale)
    }

    /// The field, with the two commands that act on it.
    ///
    /// **Save is disabled rather than hidden while the field does not hold a number**, so the
    /// control the user is reaching for stays where it was — and a locale that writes the decimal
    /// as a comma refuses `8.5` on purpose (`G-3.4`), which is a state they have to be able to see
    /// themselves out of.
    private var editor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            TextField(
                text: Binding(get: { draft ?? "" }, set: { draft = $0 }),
                prompt: Text(ExerciseLibraryStrings.e1rmOverrideField)
            ) {
                Text(ExerciseLibraryStrings.e1rmOverrideField)
            }
            .labelsHidden()
            .decimalKeyboard()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.sm.points) {
                    save
                    cancel
                }
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    save
                    cancel
                }
            }
        }
    }

    /// Commits what was typed, read in the user's own locale and unit (`G-3.4`, `G-3.1`).
    private var save: some View {
        Button {
            if let weight = entered { commit(weight) }
        } label: {
            Text(ExerciseLibraryStrings.e1rmOverrideSave)
        }
        .buttonStyle(.primaryAction)
        .disabled(entered == nil)
    }

    /// Closes the field, changing nothing.
    private var cancel: some View {
        Button {
            draft = nil
        } label: {
            Text(ExerciseLibraryStrings.e1rmOverrideCancel)
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
                .frame(minHeight: TouchTarget.standard.points)
        }
        .buttonStyle(.plain)
    }

    /// What the field currently holds, or `nil` when it holds nothing this locale reads as a mass.
    private var entered: Weight? {
        draft.flatMap { LocalizedNumberField.weight($0, in: unit, locale: locale) }
    }

    /// One of the override's two commands, as a full-width row — ``ExerciseArchiveSection``'s shape,
    /// for a control that changes what the rest of the app shows.
    private func command(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points)
                )
        }
        .buttonStyle(.plain)
    }
}
