import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// `FR-1.4.2`'s form: one gym's name, bar, collars and plates, presented over the list.
///
/// **Presented rather than pushed, and it carries no `Route`** — the set editor's reason: a form
/// holding an unsaved draft is not a place in the app, and a restored stack that reopened it would
/// present an empty form claiming to be an edit of a row nothing had read.
struct EquipmentProfileEditorSheet: View {
    /// The gym being edited, or `nil` while one is being added.
    let profile: EquipmentProfile?

    /// The unit every weight here is entered in (`G-3.1`).
    let unit: MassUnit

    /// Writes the profile. Leaves the sheet open when the write fails, so the draft is not lost.
    let save: (EquipmentProfileDraft) async -> Void

    /// Soft-deletes the profile being edited (`G-1.3`). Never called while one is being added.
    let delete: () async -> Void

    /// Leaves without writing anything.
    let cancel: () -> Void

    /// What the form holds. Seeded once, from the row being edited or from nothing at all.
    @State private var draft: EquipmentProfileDraft

    /// Whether the deletion's confirmation is on screen.
    ///
    /// Held here so it cannot outlive the sheet it was raised from — `SetEditorCommands`' rule.
    @State private var isConfirmingDelete = false

    /// Which locale the numbers are read and written in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the form.
    ///
    /// - Parameters:
    ///   - profile: The gym being edited, or `nil` for a new one.
    ///   - unit: The unit weights are entered in.
    ///   - save: Writes the profile.
    ///   - delete: Deletes the profile being edited.
    ///   - cancel: Leaves without writing.
    init(
        profile: EquipmentProfile?,
        unit: MassUnit,
        save: @escaping (EquipmentProfileDraft) async -> Void,
        delete: @escaping () async -> Void,
        cancel: @escaping () -> Void
    ) {
        self.profile = profile
        self.unit = unit
        self.save = save
        self.delete = delete
        self.cancel = cancel
        // The locale is not readable from an initializer, so the draft is seeded in the current one
        // and re-seeded on appearance where they differ. See `body`.
        _draft =
            State(
                initialValue: profile.map {
                    EquipmentProfileDraft(editing: $0, unit: unit, locale: .current)
                } ?? EquipmentProfileDraft(unit: unit, locale: .current))
    }

    /// The fields, the refusal where there is one, and the commands.
    var body: some View {
        NavigationStack {
            ScrollView {
                EquipmentProfileEditorContent(draft: $draft, unit: unit)
                    .padding(Spacing.lg.points)
            }
            .background(ColorToken.background)
            .navigationTitle(
                Text(
                    profile == nil
                        ? LoggingStrings.equipmentCreateTitle
                        : LoggingStrings.equipmentEditTitle)
            )
            .safeAreaInset(edge: .bottom) { commands }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: cancel) { Text(LoggingStrings.equipmentCancelAction) }
                }
            }
        }
        // The environment's locale rather than the process's: a draft seeded in the wrong one parses
        // "102,5" against a decimal point and refuses a weight the user can see on screen. Re-seeded
        // only when they differ, so a form the user is typing into is never rebuilt under them.
        .onAppear {
            guard draft.locale != locale else { return }
            draft =
                profile.map { EquipmentProfileDraft(editing: $0, unit: unit, locale: locale) }
                ?? EquipmentProfileDraft(unit: unit, locale: locale)
        }
    }

    /// The refusal, the save, and — on an existing gym — the deletion behind a confirmation.
    ///
    /// **Pinned below the fields** on `SetEditorCommands`' argument: the save must not need a scroll
    /// first, and the deletion sits last so the two commands a thumb reaches for are not one
    /// destructive tap apart.
    private var commands: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Divider().overlay(ColorToken.separator)
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                if let refusal = draft.refusal, !draft.isBlank {
                    FieldRefusal(message: Text(LoggingStrings.equipmentRefusal(refusal)))
                }
                Button {
                    Task { await save(draft) }
                } label: {
                    Text(LoggingStrings.equipmentSaveAction)
                }
                .buttonStyle(.primaryAction(.fill))
                .disabled(!draft.isSavable)

                if profile != nil {
                    deleteCommand
                }
            }
            .padding(.horizontal, Spacing.lg.points)
        }
        .padding(.bottom, Spacing.lg.points)
        .background(ColorToken.background)
        .confirmationDialog(
            Text(LoggingStrings.equipmentDeleteConfirmTitle),
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await delete() }
            } label: {
                Text(LoggingStrings.equipmentDeleteConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.equipmentDeleteConfirmCancel)
            }
        } message: {
            Text(LoggingStrings.equipmentDeleteConfirmMessage)
        }
    }

    /// The deletion, last and behind a confirmation.
    ///
    /// **A glyph as well as the colour** (`G-4.5`): destructive must not be carried by the tint
    /// alone. **Confirmed**, because the delete is soft (`G-1.3`) and nothing in Phase 1 undoes one:
    /// the row survives in the store and no screen will show it again.
    private var deleteCommand: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: Spacing.sm.points) {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text(LoggingStrings.equipmentDeleteAction)
            }
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.negative)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The form's fields, without the sheet around them.
///
/// A type of its own for ``PlateCalculatorContent``'s reason (`TR-1.12`): `ImageRenderer` draws none
/// of a `ScrollView`'s content, so a reference taken over the sheet would be a picture of a
/// navigation bar.
struct EquipmentProfileEditorContent: View {
    /// What the form holds.
    @Binding var draft: EquipmentProfileDraft

    /// The unit every weight here is entered in (`G-3.1`).
    let unit: MassUnit

    /// Name, bar, collars, then the plate list.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            FieldRow(
                label: Text(LoggingStrings.equipmentNameLabel),
                hint: Text(LoggingStrings.equipmentNameHint)
            ) {
                TextField(text: $draft.name) { Text(LoggingStrings.equipmentNameLabel) }
                    .accessibilityLabel(Text(LoggingStrings.equipmentNameLabel))
                    .textFieldStyle(.plain)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    .padding(Spacing.md.points)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                    .background(
                        ColorToken.surfaceRaised,
                        in: .rect(cornerRadius: CornerRadius.control.points))
            }

            weightField(label: LoggingStrings.equipmentBarLabel, hint: nil, text: $draft.barText)

            // FR-1.4.2's trap, and it is named in the label rather than in a placeholder: the stored
            // column is the mass of ONE collar, and a number entered as the pair doubles every
            // loading the app works out — invisibly, because both readings look plausible on screen.
            weightField(
                label: LoggingStrings.equipmentCollarLabel,
                hint: LoggingStrings.equipmentCollarHint,
                text: $draft.collarText
            )

            plates
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The denominations, each with how many pairs, and the command that adds one.
    private var plates: some View {
        GroupedSection(Text(LoggingStrings.equipmentPlatesSection)) {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                Text(LoggingStrings.equipmentPlatesHint)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach($draft.plates) { $row in
                    plateRow($row, id: row.id)
                }
                Button {
                    draft.plates.append(PlateDraft())
                } label: {
                    Text(LoggingStrings.equipmentAddPlateAction)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.brandAccent)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One denomination: what it weighs, how many pairs, and the way to take it off the list.
    ///
    /// - Parameters:
    ///   - row: The row's fields.
    ///   - id: Which row this is, for the removal.
    /// - Returns: The row.
    private func plateRow(_ row: Binding<PlateDraft>, id: UUID) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.sm.points) {
            weightField(label: LoggingStrings.equipmentPlateLabel, hint: nil, text: row.weightText)
            FieldRow(label: Text(LoggingStrings.equipmentPairsLabel), hint: nil) {
                numberField(label: LoggingStrings.equipmentPairsLabel, text: row.pairsText)
            }
            Button {
                draft.plates.removeAll { $0.id == id }
            } label: {
                Image(systemName: "minus.circle")
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.negative)
                    .frame(minWidth: TouchTarget.logging.points, minHeight: TouchTarget.logging.points)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LoggingStrings.equipmentRemovePlateAction))
        }
    }

    /// A labelled weight field, in the user's unit.
    ///
    /// - Parameters:
    ///   - label: What the field is.
    ///   - hint: What it accepts, where the label alone does not say it.
    ///   - text: The field's contents.
    /// - Returns: The row.
    private func weightField(
        label: LocalizedStringResource,
        hint: LocalizedStringResource?,
        text: Binding<String>
    ) -> some View {
        FieldRow(label: Text(label), hint: hint.map(Text.init)) {
            HStack(spacing: Spacing.sm.points) {
                numberField(label: label, text: text)
                Text(LoggingStrings.setUnitSymbol(for: unit))
                    .font(Typography.metricLabel.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
    }

    /// The field itself — text, never a bound number, on ``LocalizedNumberField``'s argument.
    ///
    /// The label is the row's own, announced rather than drawn: the visible one is `FieldRow`'s, and
    /// a field with none is a control VoiceOver reads as "text field" (`G-4.2`).
    ///
    /// - Parameters:
    ///   - label: What the field is.
    ///   - text: The field's contents.
    /// - Returns: The field.
    private func numberField(label: LocalizedStringResource, text: Binding<String>) -> some View {
        TextField(text: text) { Text(label) }
            .textFieldStyle(.plain)
            .decimalKeyboard()
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
            .multilineTextAlignment(.leading)
            .padding(Spacing.md.points)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.logging.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points)
            )
            .accessibilityLabel(Text(label))
    }
}
