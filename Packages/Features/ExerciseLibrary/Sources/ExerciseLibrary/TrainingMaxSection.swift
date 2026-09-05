import DerivedValues
import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the section's four states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **The absent case is the common one and it is `FR-1.13.3`'s, not an empty list.** Nothing on a
/// lifter's device writes a training max until this screen does, so "there is none" is what almost
/// every exercise draws — and what it needs is the sentence saying what setting one buys, headed by
/// the command that sets it.
///
/// No offline state: the number is a local row, so there is no fetch to be offline for (`G-2.1`).
enum TrainingMaxScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// There is one, with everything `FR-15.1.5`'s indicator needs, and the history behind it.
    case ready(TrainingMaxHistoryEntry, history: [TrainingMaxHistoryEntry])

    /// Nothing is in force, and whatever has been entered anyway.
    ///
    /// **`history` is not always empty here, and that is the whole reason it is carried.** An
    /// exercise that has never had a training max reports an empty one; an exercise whose changes
    /// are every one of them dated ahead of today reports them, because they exist, the lifter
    /// entered them, and a screen that answered "there is none" would be hiding a row it had just
    /// written (`FR-15.1.4`). The change sheet's date is unbounded forward on purpose, so one save
    /// reaches this.
    case none(history: [TrainingMaxHistoryEntry])

    /// It could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks the last good answer**, on ``ExerciseEstimateScreenState``'s rule: a
    /// read that failed leaves the previous number in place, and drawing it under no diagnostic
    /// presents a superseded figure as the one in force.
    ///
    /// - Parameter state: The section's load.
    /// - Returns: The state to draw.
    static func current(_ state: TrainingMaxSectionState) -> Self {
        if state.readFailure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        guard let current = state.current else { return .none(history: state.history) }
        return .ready(current, history: state.history)
    }
}

/// One history row and the entry it actually follows (`FR-15.1.4`).
///
/// **``replaced`` is derived from the list rather than read from
/// ``RepositoryInterface/TrainingMaxHistoryEntry/oldWeight``**, which is `G-1.4` applied to a column
/// that can go stale: a change backdated between two existing ones leaves the later one still naming
/// what *it* replaced before the insert, so a history rendered off the stored value reads as a chain
/// that does not connect — `180 ← 160` above `170 ← 160`. The column stays written, because
/// `FR-15.1.4` asks for it and the archive round-trips it; what is drawn is recomputed.
struct TrainingMaxHistoryReading: Identifiable, Equatable {
    /// The change.
    let entry: TrainingMaxHistoryEntry

    /// What was in force immediately before it, or `nil` for the oldest entry an exercise has.
    let replaced: Weight?

    /// See `Identifiable`.
    var id: UUID { entry.id }

    /// Pairs each entry with the one it follows.
    ///
    /// - Parameter history: The exercise's changes, newest ``RepositoryInterface/TrainingMaxHistoryEntry/effectiveFrom``
    ///   first — the order the repository returns and the section draws.
    /// - Returns: One reading per entry, in the same order.
    static func rows(_ history: [TrainingMaxHistoryEntry]) -> [TrainingMaxHistoryReading] {
        history.indices.map { index in
            TrainingMaxHistoryReading(
                entry: history[index],
                replaced: index + 1 < history.count ? history[index + 1].newWeight : nil)
        }
    }
}

/// This exercise's training max, its history, and the sheet that changes it (`FR-15.1.4`,
/// `FR-15.1.5`, `FR-16.7.2`).
///
/// **Above the estimate, and that is the point of the pair.** The coach's number and the observed
/// one are two different claims about the same lift, and the one a lifter trains off goes first;
/// reading them one under the other is what stops either being mistaken for the other.
struct TrainingMaxSection: View {
    /// The section's own state.
    @State private var state: TrainingMaxSectionState

    /// Whether the change sheet is open.
    @State private var isEditing = false

    /// Whether `FR-15.1.4`'s history is disclosed.
    @State private var showsHistory = false

    /// Which locale the numbers, dates and the entered value are read in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Whose days a date belongs to (`G-3.4`).
    @Environment(\.calendar) private var calendar

    /// Builds the section over the exercise it reports on.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's training max to show.
    ///   - trainingMaxes: Where it is stored.
    ///   - settings: The settings row, for the unit it is shown in.
    ///   - records: The app's one recompute actor (`TR-1.6`), told when the number moves.
    init(
        exerciseID: UUID,
        trainingMaxes: any TrainingMaxRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: TrainingMaxSectionState(
                exerciseID: exerciseID,
                trainingMaxes: trainingMaxes,
                settings: settings,
                records: records))
    }

    /// The reading, the sheet over it, and the read that fills both.
    var body: some View {
        TrainingMaxReading(
            state: TrainingMaxScreenState.current(state),
            unit: state.unit,
            hasFailedWrite: state.writeFailure != nil,
            showsHistory: $showsHistory,
            retry: { Task { await state.load() } },
            change: { isEditing = true }
        )
        .sheet(isPresented: $isEditing) {
            TrainingMaxEditorSheet(
                unit: state.unit,
                draft: state.newDraft(locale: locale, calendar: calendar),
                writeFailure: state.writeFailure,
                save: { draft in
                    if await state.save(draft) { isEditing = false }
                },
                cancel: { isEditing = false }
            )
        }
        .task {
            await state.loadDisplayUnit()
            await state.load()
        }
    }
}

/// What the training max section draws, with no store behind it.
///
/// **Split out so `TR-1.12` has something to render**, on ``ExerciseEstimateReading``'s rule: the
/// section above is a `.task` over two repositories, and a reference recorded through one is a
/// reference over a spinner.
struct TrainingMaxReading: View {
    /// Which of the four states to draw.
    let state: TrainingMaxScreenState

    /// The unit the number is shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether the last write failed. The number on screen is unchanged either way.
    let hasFailedWrite: Bool

    /// Whether `FR-15.1.4`'s history is disclosed.
    @Binding var showsHistory: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Opens the change sheet.
    let change: () -> Void

    /// Which locale the number and the dates are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The heading, whichever of the four states is current, and the command that changes it.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.trainingMaxSection)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .ready(let current, let history):
                inForce(current)
                command(Text(ExerciseLibraryStrings.trainingMaxChangeAction))
                disclosedHistory(history)
            case .none(let history):
                // T-1.09's insufficient-data view rather than its empty one: nothing was removed
                // from a list here — a value the app cannot compute has simply never been given.
                InsufficientDataView(
                    message: Text(
                        history.isEmpty
                            ? ExerciseLibraryStrings.trainingMaxNone
                            : ExerciseLibraryStrings.trainingMaxNotYet))
                command(
                    Text(
                        history.isEmpty
                            ? ExerciseLibraryStrings.trainingMaxSetAction
                            : ExerciseLibraryStrings.trainingMaxChangeAction))
                disclosedHistory(history)
            case .failed:
                ErrorStateView(message: Text(ExerciseLibraryStrings.trainingMaxError), retry: retry)
            }
            if hasFailedWrite {
                // No retry closure: nothing was stored and the sheet stayed open over it, so the
                // way to try again is the command directly above this.
                ErrorStateView(message: Text(ExerciseLibraryStrings.trainingMaxWriteError))
            }
        }
    }

    /// `FR-15.1.4`'s history behind its disclosure, where the exercise has any.
    ///
    /// **Drawn under both the number in force and its absence.** An exercise whose only changes are
    /// dated ahead of today has no number in force and a history all the same, and that is the case
    /// where hiding the list would hide a row the lifter had just written.
    ///
    /// - Parameter history: The changes, newest first.
    /// - Returns: The disclosure and, while it is open, the rows.
    @ViewBuilder private func disclosedHistory(
        _ history: [TrainingMaxHistoryEntry]
    ) -> some View {
        if !history.isEmpty {
            TrainingMaxHistoryDisclosure(isExpanded: $showsHistory)
            if showsHistory {
                ForEach(TrainingMaxHistoryReading.rows(history)) { reading in
                    TrainingMaxHistoryRow(reading: reading, unit: unit)
                }
            }
        }
    }

    /// The number in force, with `FR-15.1.5`'s indicator under it.
    ///
    /// **The date and the note are one line and never a badge.** What makes a training max legible
    /// is when it started and who said so; a marker drawn as a tint would be exactly the cue `G-4.5`
    /// says cannot stand alone, so both arrive as words.
    private func inForce(_ entry: TrainingMaxHistoryEntry) -> some View {
        MetricTile(
            label: Text(ExerciseLibraryStrings.trainingMaxValue),
            value: Text(
                entry.newWeight,
                format: AppFormat.weight(
                    WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale))
        ) {
            Text(indicator(for: entry))
        }
        .accessibilityElement(children: .combine)
    }

    /// The line under the number: the day it took effect, and the note where there is one.
    ///
    /// - Parameter entry: The change in force.
    /// - Returns: The indicator's copy.
    private func indicator(for entry: TrainingMaxHistoryEntry) -> LocalizedStringResource {
        let day = entry.effectiveFrom.formatted(AppFormat.date(locale: locale))
        guard !entry.reason.isEmpty else { return ExerciseLibraryStrings.trainingMaxSince(day) }
        return ExerciseLibraryStrings.trainingMaxSince(day, note: entry.reason)
    }

    /// The section's one command, as a full-width row — ``ExerciseArchiveSection``'s shape, for a
    /// control that changes what the rest of the app shows.
    ///
    /// **Not the accent** (`FR-16.6.4`, `G-7.2`). This screen already spends its filled button on
    /// the notes save, and a second one would leave the reader two primary actions to choose from.
    private func command(_ label: Text) -> some View {
        Button(action: change) {
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

/// `FR-15.1.4`'s disclosure.
///
/// ``RecordDisclosureHeader``'s shape and for its reasons: the whole line is the target, and the
/// fold is announced as a *value* because there is no expanded trait and `.isSelected` means a
/// chosen filter everywhere else in this app.
struct TrainingMaxHistoryDisclosure: View {
    /// Whether the history is revealed.
    @Binding var isExpanded: Bool

    /// The label and its chevron, as one control across the section's width.
    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Text(ExerciseLibraryStrings.trainingMaxHistory)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Spacing.sm.points)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            Text(
                isExpanded
                    ? ExerciseLibraryStrings.trainingMaxHistoryExpanded
                    : ExerciseLibraryStrings.trainingMaxHistoryCollapsed
            )
        )
    }
}

/// One change: what it became, what it replaced, when, and why (`FR-15.1.4`, `FR-16.7.2`).
///
/// **The oldest entry for an exercise has no left-hand side**, and a `0 → 140` in its place would
/// report a number the lifter never had — see ``TrainingMaxHistoryReading``, which is also where
/// the left-hand side comes from.
struct TrainingMaxHistoryRow: View {
    /// The change, and what it follows.
    let reading: TrainingMaxHistoryReading

    /// The change itself.
    private var entry: TrainingMaxHistoryEntry { reading.entry }

    /// The unit both loads are shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the numbers and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    /// The change, then the day and the note under it — one VoiceOver element, because it is one
    /// change (`G-4.2`).
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(change)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            footnote
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// `170 kg → 180 kg`, or `Set to 180 kg` for the first.
    ///
    /// Off ``TrainingMaxHistoryReading/replaced`` rather than the stored column — see that type for
    /// the backdated change that makes the two disagree.
    private var change: LocalizedStringResource {
        guard let old = reading.replaced else {
            return ExerciseLibraryStrings.trainingMaxFirst(rendered(entry.newWeight))
        }
        return ExerciseLibraryStrings.trainingMaxChange(
            from: rendered(old), to: rendered(entry.newWeight))
    }

    /// The day it took effect, with the note where there is one.
    ///
    /// **Not the indicator's "In force since".** Every row but the newest names a number that has
    /// since been replaced, and a list of superseded entries each claiming to be in force is a
    /// list that contradicts itself three times over. The date alone says what a history row means:
    /// this is when it started.
    private var footnote: Text {
        let day = Text(entry.effectiveFrom, format: AppFormat.date(locale: locale))
        guard !entry.reason.isEmpty else { return day }
        return Text(
            ExerciseLibraryStrings.trainingMaxRowNote(
                entry.effectiveFrom.formatted(AppFormat.date(locale: locale)),
                note: entry.reason))
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
