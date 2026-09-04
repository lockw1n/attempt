import DesignSystem
import Foundation
import Localization
import RepositoryInterface
import SwiftUI

/// The whole store as one file the lifter can keep (`FR-1.11.3`).
///
/// The view half of the pattern: it holds ``BackupState`` in `@State`, reads its phase, and hands
/// everything drawable to ``BackupReading`` so a reference can be rendered without a store.
public struct BackupView: View {
    @State private var state: BackupState

    /// Builds the screen over the store it backs up.
    ///
    /// **Six repositories rather than a reader**, which is this module's shape for a screen: the
    /// app hands down one protocol at a time (`TR-0.1.2`) and what they are assembled into is this
    /// module's business. Two more than the export takes, because a backup is the configuration too
    /// — the gyms, and the routines the lifter trains from (`FR-15.2`).
    ///
    /// - Parameters:
    ///   - exercises: The catalogue and its training-max history.
    ///   - trainingMaxes: Each exercise's training-max configuration and history.
    ///   - workouts: Sessions, entries, sets and their planned targets.
    ///   - bodyweight: The bodyweight log.
    ///   - equipment: The gyms.
    ///   - routines: The routines, their slots and their target groups.
    ///   - settings: The preferences row — a row in the file here, not a value read from it.
    public init(
        exercises: any ExerciseRepository,
        trainingMaxes: any TrainingMaxRepository,
        workouts: any WorkoutRepository & PlannedTargetRepository,
        bodyweight: any BodyweightRepository,
        equipment: any EquipmentRepository,
        routines: any RoutineRepository,
        settings: any SettingsRepository
    ) {
        _state = State(
            initialValue: BackupState(
                backup: FullBackup(
                    exercises: exercises,
                    trainingMaxes: trainingMaxes,
                    workouts: workouts,
                    bodyweight: bodyweight,
                    equipment: equipment,
                    routines: routines,
                    settings: settings)))
    }

    /// Whichever of the three states the preparation has reached.
    public var body: some View {
        ScrollView {
            BackupReading(
                state: BackupScreenState.current(state.phase),
                retry: { Task { await state.prepare() } }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.backupTitle))
        .task { await state.prepare() }
    }
}

/// What the backup screen draws — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, this module's other screens' reason: `ImageRenderer` draws none of one's
/// content.
struct BackupReading: View {
    /// Which state to draw.
    let state: BackupScreenState

    /// What to run again where running it again could work.
    let retry: () -> Void

    /// The locale the counts are joined in.
    @Environment(\.locale) private var locale

    /// The state, and nothing else — every one of the three is the whole screen.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            switch state {
            case .preparing:
                LoadingStateView(message: Text(SettingsStrings.backupPreparing))
            case .ready(let file):
                ready(file)
            case .failed:
                ErrorStateView(
                    headline: Text(SettingsStrings.backupErrorHeadline),
                    message: Text(SettingsStrings.backupErrorMessage),
                    retry: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The file, what is in it, and the sentences that qualify it.
    ///
    /// **The copy does not promise that the file can be put back**, which is `AboutView`'s refusal
    /// to link a privacy policy that does not exist yet, applied here: `FR-1.11.4`'s restore is a
    /// screen this build does not have, and a sentence saying "you can restore this later" would be
    /// a claim the binary carrying it cannot keep. What it says instead is what is true — the file
    /// holds everything, including what was deleted.
    private func ready(_ file: BackupFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            paragraph(SettingsStrings.backupIntro)
            summary(file)
            GroupedSection(Text(SettingsStrings.backupFileTitle)) {
                paragraph(SettingsStrings.backupFileDetail)
                ShareLink(item: file.url) {
                    Text(SettingsStrings.backupShare)
                }
                .buttonStyle(.primaryAction)
            }
            paragraph(SettingsStrings.backupDestinations)
            paragraph(SettingsStrings.backupIncludesDeleted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What is in the file, as counts the lifter can check against what they remember.
    ///
    /// **Joined by `AppFormat.list` rather than by a separator of this screen's own**, the export's
    /// reason: the counts are one phrase, and what joins a phrase is the locale's business (`G-3.4`).
    ///
    /// **The deleted count is dropped from the phrase when it is zero** rather than read as
    /// "0 deleted records" — a lifter who has removed nothing is being told about a category that
    /// does not apply to them, and the sentence below already says the file would carry them.
    private func summary(_ file: BackupFile) -> some View {
        var counts = [
            String(localized: SettingsStrings.backupRecordCount(file.recordCount)),
            String(localized: SettingsStrings.backupWorkoutCount(file.workoutCount)),
        ]
        if file.deletedCount > 0 {
            counts.append(String(localized: SettingsStrings.backupDeletedCount(file.deletedCount)))
        }
        return Text(verbatim: AppFormat.list(counts, locale: locale))
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .accessibilityElement(children: .combine)
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
