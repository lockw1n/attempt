import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import SwiftUI

/// `FR-16.7.2`'s change: the number, the day it takes effect, and why it moved.
///
/// **Presented rather than pushed, and it carries no `Route`** — `Settings.BodyweightEntryFormSheet`'s
/// reason: a form holding an unsaved draft is not a place the app can be restored to. Its
/// `screen-inventory.md` row is therefore a `screen.` one.
struct TrainingMaxEditorSheet: View {
    /// The unit the number is entered in (`G-3.1`).
    let unit: MassUnit

    /// The last write that failed, as a diagnostic (`G-3.4`), or `nil`.
    ///
    /// Drawn here as well as behind, on the bodyweight form's rule: this sheet covers the screen, so
    /// a diagnostic rendered under it reports the failure to nobody.
    let writeFailure: String?

    /// Writes the change. Leaves the sheet open when the write fails, so the draft is not lost.
    let save: (TrainingMaxDraft) async -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// What the form holds.
    @State private var draft: TrainingMaxDraft

    /// Whether a write is in flight — the command is disabled while one runs, so a second tap
    /// cannot start a second write.
    @State private var isSaving = false

    /// Which locale the number is read in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the form.
    ///
    /// - Parameters:
    ///   - unit: The unit the number is entered in.
    ///   - draft: What the form opens holding — seeded by the section, which knows the unit and the
    ///     day.
    ///   - writeFailure: The diagnostic from the last failed write, or `nil`.
    ///   - save: Writes the change.
    ///   - cancel: Leaves without writing.
    init(
        unit: MassUnit,
        draft: TrainingMaxDraft,
        writeFailure: String?,
        save: @escaping (TrainingMaxDraft) async -> Void,
        cancel: @escaping () -> Void
    ) {
        self.unit = unit
        self.writeFailure = writeFailure
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: draft)
    }

    /// The fields, the refusal where there is one, and the commands.
    var body: some View {
        NavigationStack {
            ScrollView {
                TrainingMaxEditorContent(draft: $draft, unit: unit)
                    .padding(Spacing.lg.points)
            }
            .background(ColorToken.background)
            .navigationTitle(Text(ExerciseLibraryStrings.trainingMaxFormTitle))
            .safeAreaInset(edge: .bottom) {
                commands
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) {
                        Text(ExerciseLibraryStrings.trainingMaxCancelAction)
                    }
                }
            }
        }
        // The environment's locale rather than the process's, on the bodyweight form's rule: a draft
        // seeded in the wrong one parses "182,5" against a decimal point and refuses a number the
        // user can see on screen. The identity is carried across — it is what a save writes to.
        .onAppear {
            guard draft.locale != locale else { return }
            draft = TrainingMaxDraft(
                unit: unit,
                locale: locale,
                calendar: draft.calendar,
                day: draft.effectiveFrom,
                newEntryID: draft.newEntryID
            )
        }
    }

    /// The refusal, the last failure, and the command that writes.
    private var commands: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Divider().overlay(ColorToken.separator)
            if let writeFailure {
                ErrorStateView(
                    message: Text(ExerciseLibraryStrings.trainingMaxWriteError),
                    retry: nil
                )
                .accessibilityValue(Text(verbatim: writeFailure))
            }
            // Not while the field is still blank: a form nobody has typed into has done nothing
            // wrong, and an opening screen that refuses is a screen that scolds.
            if !draft.isBlank, let refusal = draft.refusal {
                Text(ExerciseLibraryStrings.trainingMaxRefusal(refusal))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    await save(draft)
                    isSaving = false
                }
            } label: {
                Text(ExerciseLibraryStrings.trainingMaxSaveAction)
            }
            // The sheet's own accent, which is `FR-16.6.4` rather than an exception to it: a sheet
            // is a screen, and this is the one thing it exists to do.
            .buttonStyle(.primaryAction(.fill))
            .disabled(!draft.isSavable || isSaving)
        }
        .padding(.horizontal, Spacing.lg.points)
        .padding(.bottom, Spacing.lg.points)
        .background(ColorToken.background)
    }
}

/// The form's fields, without the sheet around them.
///
/// A type of its own for the bodyweight form's reason (`TR-1.12`): `ImageRenderer` draws none of a
/// `ScrollView`'s content, so a reference over the sheet would be a picture of a navigation bar.
struct TrainingMaxEditorContent: View {
    /// What the form holds.
    @Binding var draft: TrainingMaxDraft

    /// The unit the number is entered in (`G-3.1`).
    let unit: MassUnit

    /// The number, the day it takes effect, then the note.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            GroupedSection(Text(ExerciseLibraryStrings.trainingMaxWeightLabel)) {
                HStack(spacing: Spacing.sm.points) {
                    TextField(text: $draft.weightText) {
                        Text(ExerciseLibraryStrings.trainingMaxWeightLabel)
                    }
                    .accessibilityLabel(Text(ExerciseLibraryStrings.trainingMaxWeightLabel))
                    .textFieldStyle(.plain)
                    .decimalKeyboard()
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    Text(ExerciseLibraryStrings.trainingMaxUnitSymbol(for: unit))
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                .padding(Spacing.md.points)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points))
            }

            GroupedSection(Text(ExerciseLibraryStrings.trainingMaxDateLabel)) {
                // Unbounded in both directions, unlike the bodyweight form's: a training max is
                // announced for a block that has not started yet as often as it is backdated, and
                // `trainingMax(forExerciseID:on:)` resolves a future entry as one not yet in force.
                DatePicker(selection: $draft.effectiveFrom, displayedComponents: .date) {
                    Text(ExerciseLibraryStrings.trainingMaxDateLabel)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                }
                .tint(ColorToken.brandAccent)
                Text(ExerciseLibraryStrings.trainingMaxDateHint)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GroupedSection(Text(ExerciseLibraryStrings.trainingMaxNoteLabel)) {
                TextField(
                    text: $draft.reason,
                    prompt: Text(ExerciseLibraryStrings.trainingMaxNotePrompt)
                ) {
                    Text(ExerciseLibraryStrings.trainingMaxNoteLabel)
                }
                .labelsHidden()
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
                .textFieldStyle(.plain)
                .padding(Spacing.md.points)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
