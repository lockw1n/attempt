import DerivedValues
import DesignSystem
import Foundation
import Localization
import RepositoryInterface
import SwiftUI
import UniformTypeIdentifiers

/// A backup file read back onto this device (`FR-1.11.4`).
///
/// The view half of the pattern: it holds ``RestoreState`` in `@State`, reads its phase, and hands
/// everything drawable to ``RestoreReading`` so a reference can be rendered without a store.
///
/// **The picker lives here and not in the reading**, because it is the one thing on this screen that
/// is not a function of the phase: `fileImporter` is a presentation, and a reference rendered over a
/// presented sheet would be a reference of the sheet.
public struct RestoreView: View {
    @State private var state: RestoreState

    /// Whether the system file picker is up.
    @State private var isChoosingFile = false

    /// Builds the screen over the store it writes into.
    ///
    /// **Six dependencies — the backup's five, plus the recompute actor.** Writing rows the store
    /// has not seen makes every cached personal record wrong (`TR-0.3.9`, `G-1.4`), and the backup
    /// file deliberately does not carry the cache, so the restore is what has to rebuild it.
    ///
    /// - Parameters:
    ///   - exercises: The catalogue and its training-max history.
    ///   - workouts: Sessions, entries and sets.
    ///   - bodyweight: The bodyweight log.
    ///   - equipment: The gyms.
    ///   - settings: The preferences row — written from the file here, not read for a display unit.
    ///   - records: The app's one recompute actor.
    public init(
        exercises: any ExerciseRepository,
        workouts: any WorkoutRepository,
        bodyweight: any BodyweightRepository,
        equipment: any EquipmentRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: RestoreState(
                restore: StoreRestore(
                    exercises: exercises,
                    workouts: workouts,
                    bodyweight: bodyweight,
                    equipment: equipment,
                    settings: settings,
                    records: records)))
    }

    /// Whichever of the seven states the restore has reached, and the picker over it.
    public var body: some View {
        ScrollView {
            RestoreReading(
                state: RestoreScreenState.current(state.phase),
                chooseFile: { isChoosingFile = true },
                confirm: { Task { await state.confirmRestore() } },
                chooseAnother: { state.chooseAnother() }
            )
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(SettingsStrings.restoreTitle))
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.json]) { result in
            // A cancelled pick is not a refusal and leaves the phase alone: the lifter closed the
            // sheet, which is not a thing the screen has to report back to them.
            guard case .success(let url) = result else { return }
            Task { await state.read(url) }
        }
    }
}

/// What the restore screen draws — `TR-1.12`'s renderable half.
///
/// No `ScrollView` here, this module's other screens' reason: `ImageRenderer` draws none of one's
/// content.
struct RestoreReading: View {
    /// Which state to draw.
    let state: RestoreScreenState

    /// Opens the system picker.
    let chooseFile: () -> Void

    /// Writes the file that has been counted.
    let confirm: () -> Void

    /// Goes back to the picker without writing.
    let chooseAnother: () -> Void

    /// Whether the destructive dialog is up.
    ///
    /// **The second of the two taps `FR-1.11.4` asks for**, and it is view state rather than the
    /// screen's: nothing outside this view can raise it, which is what stops a caller from
    /// assembling a one-tap path to ``confirm``.
    ///
    /// **It guards both ways in, which is why the dialog hangs off the body rather than off the
    /// confirmation.** The retry out of ``RestoreScreenState/failed`` writes the same rows over the
    /// same store as the first attempt, so a retry that called ``confirm`` directly would be
    /// exactly the single-tap path to a destructive write this state exists to prevent — the
    /// failure being the second time round buys no permission the first tap did not.
    @State private var isConfirming = false

    /// The locale the counts are joined in.
    @Environment(\.locale) private var locale

    /// The state, and nothing else — every one of the seven is the whole screen.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            switch state {
            case .waiting:
                waiting
            case .reading:
                LoadingStateView(message: Text(SettingsStrings.restoreReading))
            case .confirming(let summary):
                confirming(summary)
            case .restoring:
                LoadingStateView(message: Text(SettingsStrings.restoreRestoring))
            case .restored(let summary):
                restored(summary)
            case .refused(let refusal):
                refused(refusal)
            case .failed:
                ErrorStateView(
                    headline: Text(SettingsStrings.restoreErrorHeadline),
                    message: Text(SettingsStrings.restoreErrorMessage),
                    retry: { isConfirming = true })
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            Text(SettingsStrings.restoreDialogTitle),
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button(role: .destructive, action: confirm) {
                Text(SettingsStrings.restoreDialogAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(SettingsStrings.restoreDialogCancel)
            }
        } message: {
            Text(SettingsStrings.restoreDialogMessage)
        }
    }

    /// No file chosen, and the way to choose one — `FR-1.13.1`'s empty state.
    ///
    /// **This screen's emptiness is about the *screen* and not about the store**, which is what
    /// makes it the shared component's case rather than an argument against it: there is genuinely
    /// nothing here yet, and the one thing that changes that is the action the component carries.
    private var waiting: some View {
        EmptyStateView(
            symbolName: "arrow.down.document",
            headline: Text(SettingsStrings.restoreWaitingHeadline),
            message: Text(SettingsStrings.restoreWaitingMessage),
            action: StateAction(Text(SettingsStrings.restoreChoose), handler: chooseFile))
    }

    /// What the file holds, what writing it would do, and the two commands.
    ///
    /// **The destructive command raises a dialog rather than running**: `FR-1.11.4`'s "cannot be
    /// bypassed accidentally" is a count of deliberate taps, and this screen's count is three —
    /// choose, replace, confirm. **The retry out of a failed write is counted the same way**, which
    /// is why the dialog is the body's and not this state's.
    ///
    /// **The way out sits above the destructive command, which is last**, on the two Logging
    /// editors' rule: put them the other way round and the two commands a thumb reaches for are one
    /// destructive tap apart.
    private func confirming(_ summary: BackupSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            GroupedSection(Text(SettingsStrings.restoreConfirmTitle)) {
                VStack(alignment: .leading, spacing: Spacing.md.points) {
                    contents(summary)
                    paragraph(SettingsStrings.restoreConfirmDetail)
                    paragraph(SettingsStrings.restoreConfirmDeleted)
                    Button(action: chooseAnother) {
                        Text(SettingsStrings.restoreConfirmOther)
                            .font(Typography.actionLabel.font)
                            .foregroundStyle(ColorToken.brandAccent)
                            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    replaceCommand
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The command that raises the destructive confirmation.
    ///
    /// **Not `.primaryAction`**, although it is the one thing this state is for: that style paints
    /// the brand accent, which is the tint the backup screen's **Share** wears — so the one command
    /// in the app that overwrites the store would have looked exactly like the safest one beside it.
    ///
    /// **A glyph as well as the colour** (`G-4.5`), the two Logging editors' rule: destructive must
    /// not be carried by the tint alone.
    private var replaceCommand: some View {
        Button {
            isConfirming = true
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(SettingsStrings.restoreConfirmAction)
            }
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.negative)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// That every row landed, and what was in the file that landed.
    ///
    /// **Not one of `FR-1.13.1`'s five**, and it is not meant to be: the five are the ways a screen
    /// can have nothing useful to draw, and this screen has just done the one thing it is for.
    private func restored(_ summary: BackupSummary) -> some View {
        GroupedSection(Text(SettingsStrings.restoreDoneHeadline)) {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                contents(summary)
                paragraph(SettingsStrings.restoreDoneDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Which of the three refusals this is — `FR-1.13.1`'s error state, three times.
    ///
    /// **The component is drawn without its retry, and the command beneath it is the picker.**
    /// Nothing this screen could run again would make the same bytes acceptable, so a retry is the
    /// wrong offer — and `ErrorStateView`'s own is labelled "Try again", which on a refusal would
    /// invite the lifter to re-pick the file that was just turned down. The way forward is a
    /// different file, so that is what the button says. Filed against `T-1.09`: the shared error
    /// state has one retry label for two recoveries, and this screen has both.
    private func refused(_ refusal: RestoreRefusal) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            ErrorStateView(
                headline: Text(Self.headline(for: refusal)),
                message: Text(Self.message(for: refusal)))
            Button(action: chooseFile) {
                Text(SettingsStrings.restoreChoose)
            }
            .buttonStyle(.primaryAction)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the file holds, as the counts the lifter can check against what they remember.
    ///
    /// **Joined by `AppFormat.list` rather than by a separator of this screen's own**, the backup's
    /// reason: the counts are one phrase, and what joins a phrase is the locale's business
    /// (`G-3.4`).
    ///
    /// **The deleted count is dropped when it is zero**, the backup's rule again — and here it also
    /// takes the sentence below it its subject, since no record is coming back.
    ///
    /// **All three counts are the backup screen's own keys, this one included.** A phrase in a list
    /// has to be a noun phrase: a restore-specific "7 deleted records come back" put a verb in the
    /// third item and made the whole list read as though the first two came back too. What those
    /// rows do on the way in is the paragraph under this one, where it can be a sentence.
    private func contents(_ summary: BackupSummary) -> some View {
        var counts = [
            String(localized: SettingsStrings.backupRecordCount(summary.recordCount)),
            String(localized: SettingsStrings.backupWorkoutCount(summary.workoutCount)),
        ]
        if summary.deletedCount > 0 {
            counts.append(
                String(localized: SettingsStrings.backupDeletedCount(summary.deletedCount)))
        }
        return VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            Text(verbatim: AppFormat.list(counts, locale: locale))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(
                SettingsStrings.restoreTakenOn(
                    summary.takenAt.formatted(AppFormat.fullDate(locale: locale)))
            )
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The heading for a refusal.
    ///
    /// - Parameter refusal: Why the file cannot be used.
    /// - Returns: The heading.
    static func headline(for refusal: RestoreRefusal) -> LocalizedStringResource {
        switch refusal {
        case .unreadable: SettingsStrings.restoreUnreadableHeadline
        case .futureVersion: SettingsStrings.restoreFutureHeadline
        case .notABackup: SettingsStrings.restoreNotBackupHeadline
        }
    }

    /// What that means and what to do about it.
    ///
    /// **The claimed version is not drawn**, although ``RestoreRefusal/futureVersion(_:)`` carries
    /// it: a number naming an internal format tells the lifter nothing they can act on, and what
    /// they can act on — update the app — does not depend on which number it was. It is carried so
    /// that a test and a diagnostic can tell the two refusals apart.
    ///
    /// - Parameter refusal: Why the file cannot be used.
    /// - Returns: The message.
    static func message(for refusal: RestoreRefusal) -> LocalizedStringResource {
        switch refusal {
        case .unreadable: SettingsStrings.restoreUnreadableMessage
        case .futureVersion: SettingsStrings.restoreFutureMessage
        case .notABackup: SettingsStrings.restoreNotBackupMessage
        }
    }
}
