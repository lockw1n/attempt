import DesignSystem
import Foundation
import Localization
import RepositoryInterface
import SwiftUI

/// The training log as two files the lifter can take away (`FR-1.11.1`, `FR-1.11.2`).
///
/// The view half of the pattern: it holds ``DataExportState`` in `@State`, reads its phase, and
/// hands everything drawable to ``DataExportReading`` so a reference can be rendered without a
/// store.
public struct DataExportView: View {
    @State private var state: DataExportState

    /// Builds the screen over the store it exports.
    ///
    /// **Four repositories rather than a reader**, which is this module's shape for a screen: the
    /// app hands down one protocol at a time (`TR-0.1.2`) and what they are assembled into is this
    /// module's business.
    ///
    /// - Parameters:
    ///   - exercises: The catalogue.
    ///   - workouts: Sessions, entries and sets.
    ///   - bodyweight: The bodyweight log.
    ///   - settings: The preferences row, read for the unit the CSV is written in.
    public init(
        exercises: any ExerciseRepository,
        workouts: any WorkoutRepository,
        bodyweight: any BodyweightRepository,
        settings: any SettingsRepository
    ) {
        _state = State(
            initialValue: DataExportState(
                export: TrainingLogExport(
                    exercises: exercises, workouts: workouts, bodyweight: bodyweight),
                settings: settings))
    }

    /// Whichever of the four states the preparation has reached.
    public var body: some View {
        ScrollView {
            DataExportReading(
                state: DataExportScreenState.current(state.phase),
                retry: { Task { await state.prepare() } }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.exportTitle))
        .task { await state.prepare() }
    }
}

/// What the export screen draws — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, this module's other screens' reason: `ImageRenderer` draws none of one's
/// content.
struct DataExportReading: View {
    /// Which state to draw.
    let state: DataExportScreenState

    /// What to run again where running it again could work.
    let retry: () -> Void

    /// The locale the two counts are joined in.
    @Environment(\.locale) private var locale

    /// The state, and nothing else — every one of the four is the whole screen.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            switch state {
            case .preparing:
                LoadingStateView(message: Text(SettingsStrings.exportPreparing))
            case .ready(let files):
                ready(files)
            case .empty:
                EmptyStateView(
                    symbolName: "square.and.arrow.up",
                    headline: Text(SettingsStrings.exportEmptyHeadline),
                    message: Text(SettingsStrings.exportEmptyMessage))
            case .failed:
                ErrorStateView(
                    headline: Text(SettingsStrings.exportErrorHeadline),
                    message: Text(SettingsStrings.exportErrorMessage),
                    retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Both files, what is in them, and the two sentences that qualify them.
    private func ready(_ files: TrainingLogExportFiles) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            paragraph(SettingsStrings.exportIntro)
            summary(files)
            format(
                title: SettingsStrings.exportCSVTitle,
                detail: SettingsStrings.exportCSVDetail,
                file: files.csv)
            format(
                title: SettingsStrings.exportJSONTitle,
                detail: SettingsStrings.exportJSONDetail,
                file: files.json)
            paragraph(SettingsStrings.exportDestinations)
            paragraph(SettingsStrings.exportExcludesDeleted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What is in the files, as the two counts a lifter can check against what they remember.
    ///
    /// **Joined by `AppFormat.list` rather than by a separator of this screen's own.** The two
    /// counts are one phrase, and what joins a phrase is the locale's business (`G-3.4`) — a
    /// hard-coded bullet or comma is an English list punctuation shipped to every language.
    private func summary(_ files: TrainingLogExportFiles) -> some View {
        let counts = [
            String(localized: SettingsStrings.exportWorkoutCount(files.sessionCount)),
            String(localized: SettingsStrings.exportSetCount(files.setCount)),
        ]
        return Text(verbatim: AppFormat.list(counts, locale: locale))
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .accessibilityElement(children: .combine)
    }

    /// One format: what it is, what it is for, and the one command that hands it over.
    ///
    /// **`ShareLink`, which is `FR-1.11.2`'s two paths in one control.** The system sheet it raises
    /// carries Save to Files alongside every other destination, so "share sheet, and to Files" is
    /// one action rather than two — a second, Files-only button would offer the same sheet with
    /// fewer choices in it.
    private func format(
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        file: URL
    ) -> some View {
        GroupedSection(Text(title)) {
            paragraph(detail)
            ShareLink(item: file) {
                Text(SettingsStrings.exportShare)
            }
            .buttonStyle(.primaryAction)
        }
    }

    /// One sentence of the copy.
    private func paragraph(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
