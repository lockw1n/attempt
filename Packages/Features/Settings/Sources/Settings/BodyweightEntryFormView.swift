import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import SwiftUI

/// `FR-1.8.1`'s manual entry: what was weighed, and the day it was weighed on.
///
/// **Presented rather than pushed, and it carries no `Route`** — the equipment editor's reason: a
/// form holding an unsaved draft is not a place the app can be restored to.
struct BodyweightEntryFormSheet: View {
    /// The unit the reading is entered in (`G-3.1`).
    let unit: MassUnit

    /// Whose days the date is snapped to (`G-3.4`).
    let calendar: Calendar

    /// The last write that failed, as a diagnostic (`G-3.4`), or `nil`.
    ///
    /// Drawn here as well as behind, on the equipment editor's rule: this sheet covers the screen,
    /// so a diagnostic rendered under it reports the failure to nobody.
    let writeFailure: String?

    /// Writes the reading. Leaves the sheet open when the write fails, so the draft is not lost.
    let save: (BodyweightEntryDraft) async -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// What the form holds.
    @State private var draft: BodyweightEntryDraft

    /// Whether a write is in flight — the command is disabled while one runs, so a second tap
    /// cannot start a second write.
    @State private var isSaving = false

    /// Which locale the number is read in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the form.
    ///
    /// - Parameters:
    ///   - unit: The unit the reading is entered in.
    ///   - calendar: Whose days the date is snapped to.
    ///   - writeFailure: The diagnostic from the last failed write, or `nil`.
    ///   - save: Writes the reading.
    ///   - cancel: Leaves without writing.
    init(
        unit: MassUnit,
        calendar: Calendar,
        writeFailure: String?,
        save: @escaping (BodyweightEntryDraft) async -> Void,
        cancel: @escaping () -> Void
    ) {
        self.unit = unit
        self.calendar = calendar
        self.writeFailure = writeFailure
        self.save = save
        self.cancel = cancel
        // The locale is not readable from an initializer, so the draft is seeded in the current one
        // and re-seeded on appearance where they differ — see `body`.
        _draft = State(
            initialValue: BodyweightEntryDraft(unit: unit, locale: .current, calendar: calendar))
    }

    /// The fields, the refusal where there is one, and the commands.
    var body: some View {
        NavigationStack {
            ScrollView {
                BodyweightEntryFormContent(draft: $draft, unit: unit)
                    .padding(Spacing.lg.points)
            }
            .background(ColorToken.background)
            .navigationTitle(Text(SettingsStrings.bodyweightFormTitle))
            .safeAreaInset(edge: .bottom) {
                commands
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) { Text(SettingsStrings.bodyweightCancelAction) }
                }
            }
        }
        // The environment's locale rather than the process's: a draft seeded in the wrong one parses
        // "82,4" against a decimal point and refuses a number the user can see on screen. The
        // identity is carried across — it is what a save writes to.
        .onAppear {
            guard draft.locale != locale else { return }
            draft = BodyweightEntryDraft(
                unit: unit,
                locale: locale,
                calendar: calendar,
                day: draft.date,
                newEntryID: draft.newEntryID
            )
        }
    }

    /// The refusal, the last failure, and the command that writes.
    private var commands: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Divider().overlay(ColorToken.separator)
            if let writeFailure {
                BodyweightDiagnosticCard(
                    title: Text(SettingsStrings.bodyweightWriteErrorTitle), detail: writeFailure)
            }
            // Not while the field is still blank: a form nobody has typed into has done nothing
            // wrong, and an opening screen that refuses is a screen that scolds.
            if !draft.isBlank, let refusal = draft.refusal {
                Text(SettingsStrings.bodyweightRefusal(refusal))
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
                Text(SettingsStrings.bodyweightSaveAction)
            }
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
/// A type of its own for the equipment editor's reason (`TR-1.12`): `ImageRenderer` draws none of a
/// `ScrollView`'s content, so a reference over the sheet would be a picture of a navigation bar.
struct BodyweightEntryFormContent: View {
    /// What the form holds.
    @Binding var draft: BodyweightEntryDraft

    /// The unit the reading is entered in (`G-3.1`).
    let unit: MassUnit

    /// The weight, then the day it is for.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            GroupedSection(Text(SettingsStrings.bodyweightWeightLabel)) {
                HStack(spacing: Spacing.sm.points) {
                    TextField(text: $draft.weightText) {
                        Text(SettingsStrings.bodyweightWeightLabel)
                    }
                    .accessibilityLabel(Text(SettingsStrings.bodyweightWeightLabel))
                    .textFieldStyle(.plain)
                    .decimalKeyboard()
                    .font(Typography.numericValue.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    Text(SettingsStrings.unitSymbol(for: unit))
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                .padding(Spacing.md.points)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points))
            }

            GroupedSection(Text(SettingsStrings.bodyweightDateLabel)) {
                // Bounded above at now, the training day's own rule: a reading cannot be taken
                // tomorrow, and backdating is what `FR-1.8.1` carries a date for at all.
                DatePicker(selection: $draft.date, in: ...Date.now, displayedComponents: .date) {
                    Text(SettingsStrings.bodyweightDateLabel)
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                }
                .tint(ColorToken.brandAccent)
                Text(SettingsStrings.bodyweightDateHint)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
