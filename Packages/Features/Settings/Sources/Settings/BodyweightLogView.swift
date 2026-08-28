import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// `FR-1.8.1` and `FR-1.8.3`: what the lifter weighed, when, and the trend under it.
///
/// **Pushed from Settings rather than living in a tab of its own.** `D-8` fixes the four tabs and
/// none of them is the body log; the row that opens this screen sits beside the gyms, which is also
/// where `FR-1.10.4`'s HealthKit permission will land when `T-1.51` reads the same log from Health.
///
/// The view half of the pattern: it holds ``BodyweightLogState`` in `@State`, reads it and calls it,
/// and hands everything drawable to ``BodyweightLogReading`` so a snapshot can render the states
/// without a store behind them.
public struct BodyweightLogView: View {
    @State private var state: BodyweightLogState

    /// Whether the entry form is up.
    @State private var isAddingReading = false

    /// Builds the screen over the repositories its state reads and writes through.
    ///
    /// - Parameters:
    ///   - repository: The bodyweight log.
    ///   - settings: Where the display unit comes from (`G-3.1`).
    ///   - health: `FR-1.8.2`'s sample source. `nil` draws the screen without an import command.
    public init(
        repository: any BodyweightRepository,
        settings: any SettingsRepository,
        health: (any BodyweightSampleSource)? = nil
    ) {
        _state = State(
            initialValue: BodyweightLogState(
                repository: repository, settings: settings, health: health))
    }

    /// The log, the command that adds to it, and the form that command raises.
    public var body: some View {
        ScrollView {
            BodyweightLogReading(
                state: BodyweightLogScreenState.current(state.phase),
                currentAverage: state.currentAverage,
                unit: state.displayUnit,
                writeFailure: state.writeFailure,
                healthImport: state.isHealthImportAvailable ? state.healthImport : nil,
                retry: { Task { await state.load() } },
                add: addReading,
                importFromHealth: { Task { await state.importFromHealth() } }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.bodyweightTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addReading) { Text(SettingsStrings.bodyweightAddAction) }
            }
        }
        .sheet(isPresented: $isAddingReading) {
            BodyweightEntryFormSheet(
                unit: state.displayUnit,
                calendar: state.calendar,
                writeFailure: state.writeFailure,
                save: { draft in
                    if await state.save(draft) { isAddingReading = false }
                },
                cancel: { isAddingReading = false }
            )
        }
        .task { await state.load() }
    }

    /// Opens the form on a clean slate: ``BodyweightLogState/writeFailure`` outlives the operation
    /// that set it, and a failure from the last save must not be the first thing a new form reports.
    private func addReading() {
        state.clearWriteFailure()
        isAddingReading = true
    }
}

/// What the bodyweight screen draws, with no store behind it — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, for the equipment editor's reason: `ImageRenderer` draws none of one's
/// content, so a reference taken over the screen would be a picture of an empty scroll area.
struct BodyweightLogReading: View {
    /// Which of `FR-1.13.1`'s states to draw.
    let state: BodyweightLogScreenState

    /// The seven-day average ending today, or `nil` when this week holds too few readings.
    let currentAverage: Weight?

    /// The unit every reading is shown in (`G-3.1`).
    let unit: MassUnit

    /// The last write that failed, as a diagnostic (`G-3.4`), or `nil`.
    let writeFailure: String?

    /// What `FR-1.8.2`'s import last did, or `nil` where this device has no source — which draws
    /// the command away rather than dimming it.
    let healthImport: BodyweightLogState.HealthImport?

    /// What the error state's retry does.
    let retry: () -> Void

    /// What the empty state's action does.
    let add: () -> Void

    /// What the import command does.
    let importFromHealth: () -> Void

    /// Which locale the numbers and dates are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// A failed write above whichever state is current.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if let writeFailure {
                BodyweightDiagnosticCard(
                    title: Text(SettingsStrings.bodyweightWriteErrorTitle), detail: writeFailure)
            }
            // A failed import is a diagnostic beside the log, never in place of it — the write
            // failure's rule, for the same reason: the readings are still there.
            if case .failed(let detail) = healthImport {
                BodyweightDiagnosticCard(
                    title: Text(SettingsStrings.bodyweightHealthErrorTitle), detail: detail)
            }
            // Offered over a log that answered, and not over one that has not. An import
            // de-duplicates against the rows, so a screen that could not read them has nothing to
            // de-duplicate against and would import blind.
            if let healthImport, state == .empty || isReady {
                BodyweightHealthImportCard(phase: healthImport, run: importFromHealth)
            }
            switch state {
            case .loading:
                LoadingStateView()
            case .empty:
                EmptyStateView(
                    symbolName: "scalemass",
                    headline: Text(SettingsStrings.bodyweightEmptyHeadline),
                    message: Text(SettingsStrings.bodyweightEmptyMessage),
                    action: StateAction(Text(SettingsStrings.bodyweightAddAction), handler: add)
                )
            case .failed:
                ErrorStateView(
                    headline: Text(SettingsStrings.bodyweightErrorHeadline),
                    message: Text(SettingsStrings.bodyweightErrorMessage),
                    retry: retry
                )
            case .ready(let readings):
                average
                history(readings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Whether the log answered with rows.
    private var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    /// `FR-1.8.3`'s average, or what would make one showable (`FR-1.13.3`).
    ///
    /// **Today's window and not the newest reading's**, which is what makes the refusal meaningful:
    /// a lifter who last weighed in a month ago has no current average, and the sentence here says
    /// so rather than presenting a month-old figure as this week's.
    @ViewBuilder
    private var average: some View {
        if let currentAverage {
            MetricTile(
                label: Text(SettingsStrings.bodyweightAverageTitle),
                value: Text(currentAverage, format: Self.weightStyle(unit: unit, locale: locale)))
        } else {
            InsufficientDataView(
                headline: Text(SettingsStrings.bodyweightAverageTitle),
                message: Text(SettingsStrings.bodyweightAverageNone))
        }
    }

    /// The log, newest first (`FR-1.8.3`).
    private func history(_ readings: [BodyweightReading]) -> some View {
        GroupedSection(Text(SettingsStrings.bodyweightHistoryTitle)) {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                ForEach(readings) { reading in
                    BodyweightReadingRow(reading: reading, unit: unit)
                }
            }
        }
    }
}

extension BodyweightLogReading {
    /// How a bodyweight is written (`G-3.1`, `G-3.3`).
    ///
    /// **A tenth of a unit rather than `G-3.3`'s default step**, which is the one place this screen
    /// departs from every other weight in the app. That default is the step a *barbell* moves in —
    /// half a kilo, a whole pound — and it is what a plate can be loaded to; a scale reads finer
    /// than that, so a reading entered as 82.4 kg would be drawn back as 82.5 kg, a number the user
    /// did not type. The average needs the same width for the opposite reason: rounded to the
    /// nearest half kilo it moves in jumps a week of readings never made.
    static func weightStyle(unit: MassUnit, locale: Locale) -> WeightStyle {
        AppFormat.weight(in: unit, precision: .tenth, locale: locale)
    }
}

/// One row of the log: the day, what was weighed on it, and that day's own window.
struct BodyweightReadingRow: View {
    /// The reading to draw.
    let reading: BodyweightReading

    /// The unit it is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the number and the date are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// How large the user reads at — what decides whether the day and the weight sit side by side
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The day and the weight, with the row's own average beneath where there is one.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                if dynamicTypeSize.isAccessibilitySize {
                    stacked
                } else {
                    inline
                }
                // Absent rather than dashed where the window is too thin: the average above says
                // once what would be enough, and a row repeating it for every early reading would
                // be that sentence a dozen times over.
                if let average = reading.average {
                    caption(average)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    /// The day and the weight on one line, the weight pushed to the trailing edge.
    private var inline: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm.points) {
            day
            Spacer(minLength: Spacing.sm.points)
            weight
        }
    }

    /// The same two, stacked — what `accessibility3` needs, where a weight beside a date wraps its
    /// numeral across three lines.
    ///
    /// **A `VStack` rather than the switched `AnyLayout` the dashboard's rows use**, deliberately: a
    /// `Spacer` that pushes to the trailing edge in one layout expands *vertically* in the other,
    /// which is a blank half-row inside the card at the largest type size.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            day
            weight
        }
    }

    /// The day the reading is for.
    private var day: some View {
        Text(reading.date, format: AppFormat.date(locale: locale))
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
    }

    /// What was weighed.
    private var weight: some View {
        Text(reading.weight, format: BodyweightLogReading.weightStyle(unit: unit, locale: locale))
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
    }

    /// This row's own seven-day figure, labelled — stacked at the largest type size for the reason
    /// ``stacked`` gives.
    @ViewBuilder
    private func caption(_ average: Weight) -> some View {
        let label = Text(SettingsStrings.bodyweightReadingAverage)
        let value = Text(
            average, format: BodyweightLogReading.weightStyle(unit: unit, locale: locale))
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            if dynamicTypeSize.isAccessibilitySize {
                label
                value
            } else {
                HStack(spacing: Spacing.xs.points) {
                    label
                    value
                }
            }
        }
        .font(Typography.caption.font)
        .foregroundStyle(ColorToken.textSecondary)
    }
}

/// `FR-1.8.2`'s command, what it reads, and what the last run did.
///
/// **The consent context sits beside the button, not only in the system prompt** (`G-5.4`,
/// `TR-1.9`): the prompt names the app and the data type, and this line is where the app says the
/// readings stay on the device.
struct BodyweightHealthImportCard: View {
    /// What the last import did, and whether one is running.
    let phase: BodyweightLogState.HealthImport

    /// What the command does.
    let run: () -> Void

    /// The command, its detail line, and the last run's outcome under both.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Button(action: run) { Text(SettingsStrings.bodyweightHealthAction) }
                    .disabled(phase == .importing)
                Text(SettingsStrings.bodyweightHealthDetail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                outcome
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What the last import did — nothing at all before one has run, and nothing for a failure,
    /// which is drawn as its own diagnostic above.
    @ViewBuilder
    private var outcome: some View {
        switch phase {
        case .idle, .failed:
            EmptyView()
        case .importing:
            Text(SettingsStrings.bodyweightHealthRunning)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        case .imported(let added, let daysAlreadyEntered):
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                Text(SettingsStrings.bodyweightHealthResultTitle)
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(SettingsStrings.bodyweightHealthAdded(added))
                Text(SettingsStrings.bodyweightHealthKept(daysAlreadyEntered))
            }
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
    }
}

/// A failure, shown as what it is rather than as a sentence written for the user (`G-3.4`).
struct BodyweightDiagnosticCard: View {
    /// What failed, in the screen's words.
    let title: Text

    /// The error's description.
    let detail: String

    /// The heading and the diagnostic under it.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                title
                    .font(Typography.cardTitle.font)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(verbatim: detail)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
