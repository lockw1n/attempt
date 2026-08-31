import AppNavigation
import DesignSystem
import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The create/edit form (`FR-1.1.3`, `FR-1.1.4`).
///
/// The view half of `TR-1.2`'s pattern, and the same `ScrollView`/`LazyVStack` shape the other two
/// screens use for the same reason — `TR-1.12`'s harness renders through `ImageRenderer`, which
/// draws a placeholder for anything UIKit-backed.
///
/// **One screen for both modes.** They differ in three places — the title, whether a record is read,
/// and whether the save mints a row or replaces one — and every one of those differences lives in
/// ``ExerciseFormState``. A second view would be the same fields twice.
///
/// **Every option is a chip rather than a `Picker` or a `Menu`.** Both of those are UIKit-backed, so
/// the snapshot would see a grey rectangle where the selection is, and the selection is the one
/// thing about this screen a reference can check. The name field is the exception the harness cannot
/// avoid: a `TextField` does not rasterise, which is why it has no reference of its own.
public struct ExerciseFormView: View {
    @State private var state: ExerciseFormState

    /// Pops the form once a save has landed. The screen underneath re-reads for itself.
    @Environment(\.dismiss) private var dismiss

    /// Builds the screen over what it is editing.
    ///
    /// - Parameters:
    ///   - mode: Whether this authors a new exercise or edits an existing one.
    ///   - repository: Where the catalogue and the edited record come from. `Persistence`'s
    ///     implementation in the app; anything conforming in a test or a preview.
    public init(mode: ExerciseFormMode, repository: any ExerciseRepository) {
        _state = State(initialValue: ExerciseFormState(mode: mode, repository: repository))
    }

    /// The form, or whichever of the screen's three other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(title))
        .task { await state.load() }
        // The save is what ends this screen, and the state is what knows the save landed — a
        // dismissal driven from the button would fire on a write that failed.
        .onChange(of: state.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    /// The screen's title, which is the only copy the two modes do not share.
    private var title: LocalizedStringResource {
        switch state.mode {
        case .create: ExerciseLibraryStrings.formCreateTitle
        case .edit: ExerciseLibraryStrings.formEditTitle
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state and no empty one**, on the arguments the list and the detail screen
    /// already make: the store is local and bundle-seeded, so there is no fetch to be offline for
    /// (`G-2.1`, `NFR-1.7`), and a form is never empty — it has fields, filled or not. Nothing here
    /// is derived, so there is no insufficient-data state either. A failed *save* is not a phase: it
    /// renders beside the save button and costs the form nothing.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(ExerciseLibraryStrings.formErrorHeadline),
                message: Text(ExerciseLibraryStrings.formErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .missing:
            // No retry: the identifier resolved to nothing, and reading again resolves to nothing.
            ErrorStateView(
                headline: Text(ExerciseLibraryStrings.formMissingHeadline),
                message: Text(ExerciseLibraryStrings.formMissingMessage)
            )
        case .ready:
            ready
        }
    }

    /// The fields, the parent picker, and the command that commits them.
    ///
    /// **The parent picker is absent on a built-in exercise**, whose parent the catalogue owns —
    /// ``ExerciseFormState/catalogueOwnsFields`` has the rule, and the fields section renders that
    /// exercise's parent as a fact alongside the other four it cannot change.
    ///
    /// Both sections go inert while a save is in flight: the record is taken when the button is
    /// tapped, and a form that accepted keystrokes afterwards would be taking edits it is about to
    /// dismiss without storing.
    @ViewBuilder private var ready: some View {
        ExerciseFieldsSection(state: state)
            .disabled(state.isSaving)
        if !state.catalogueOwnsFields {
            ExerciseParentSection(state: state)
                .disabled(state.isSaving)
        }
        saveCommand
    }

    /// The save button, and a failed save beneath it.
    ///
    /// The button is disabled rather than hidden while the name is empty: a command that vanishes
    /// gives the user nothing to aim at, and the sentence under the name field says why it is off.
    @ViewBuilder private var saveCommand: some View {
        Button {
            Task { await state.save() }
        } label: {
            Text(ExerciseLibraryStrings.formSave)
        }
        .buttonStyle(.primaryAction(.fill))
        .disabled(!state.canSave)
        .opacity(state.canSave ? Opacity.opaque.value : Opacity.disabled.value)

        if state.writeFailure != nil {
            // The shared error component rather than a local label, and the form stays on screen
            // beside it — `SettingsLandingState`'s rule that a failed write costs the screen nothing.
            ErrorStateView(
                message: Text(ExerciseLibraryStrings.formWriteError),
                retry: { Task { await state.save() } }
            )
        }
    }
}

/// The exercise's own fields (`FR-1.1.3`, `FR-1.14.2`): the two names, then the four vocabularies.
struct ExerciseFieldsSection: View {
    /// The form these fields are bound to.
    @Bindable var state: ExerciseFormState

    /// The two name fields, then either the vocabularies or — on a built-in — the facts they would
    /// edit.
    ///
    /// **The Ukrainian name is above the catalogue-owned split, with the name**, because it is
    /// editable on a built-in for the same reason the name is: the seed merge fills that column and
    /// never re-supplies it, so an edit here is not undone by the next import (`FR-1.14.2`).
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.formSection)) {
            nameField
            ukrainianNameField
            if state.catalogueOwnsFields {
                catalogueOwnedFacts
            } else {
                vocabularies
            }
        }
    }

    /// The one field every exercise has in common, and the sentence saying it is required.
    @ViewBuilder private var nameField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(ExerciseLibraryStrings.formName)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            TextField(
                text: $state.name,
                prompt: Text(ExerciseLibraryStrings.formNamePrompt)
            ) {
                Text(ExerciseLibraryStrings.formName)
            }
            .labelsHidden()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
            if !state.isNameValid {
                Text(ExerciseLibraryStrings.formNameRequired)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
    }

    /// The second name (`FR-1.14.2`), and the sentence saying what leaving it blank does.
    ///
    /// The sentence is always there, unlike the name field's, which appears only while the name is
    /// missing: this one describes a choice rather than reporting a problem.
    @ViewBuilder private var ukrainianNameField: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(ExerciseLibraryStrings.formUkrainianName)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            TextField(
                text: $state.ukrainianName,
                prompt: Text(ExerciseLibraryStrings.formUkrainianNamePrompt)
            ) {
                Text(ExerciseLibraryStrings.formUkrainianName)
            }
            .labelsHidden()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
            Text(ExerciseLibraryStrings.formUkrainianNameOptional)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }

    /// What a built-in exercise's other five fields are, and whose they are.
    @ViewBuilder private var catalogueOwnedFacts: some View {
        CatalogueOwnedFacts(
            movement: state.movement,
            equipment: state.equipment,
            barType: state.barType,
            laterality: state.laterality,
            parentName: state.selectedParent?.name
        )
    }

    /// One chip row per vocabulary, for the exercises whose fields are the user's.
    @ViewBuilder private var vocabularies: some View {
        OptionChipRow(
            title: ExerciseLibraryStrings.formMovement,
            options: Movement.allCases,
            selection: $state.movement,
            label: ExerciseLibraryStrings.label(for:)
        )
        OptionChipRow(
            title: ExerciseLibraryStrings.formEquipment,
            options: Equipment.allCases,
            selection: $state.equipment,
            label: ExerciseLibraryStrings.label(for:)
        )
        OptionChipRow(
            title: ExerciseLibraryStrings.formBar,
            options: BarType.allCases,
            selection: $state.barType,
            label: ExerciseLibraryStrings.label(for:)
        )
        OptionChipRow(
            title: ExerciseLibraryStrings.formLaterality,
            options: Laterality.allCases,
            selection: $state.laterality,
            label: ExerciseLibraryStrings.label(for:)
        )
    }
}

/// The five fields a built-in exercise's form shows rather than edits, and whose they are.
///
/// **Shown rather than omitted.** The values are on the detail screen either way, so hiding them
/// here would leave the user comparing two screens to work out why one of them is shorter; the
/// sentence above them is the thing a silently reverted edit would never have said.
/// ``ExerciseFormState/catalogueOwnsFields`` is the rule, and its only home.
///
/// Takes values rather than the state, for the reason `ExerciseGroupList` gives — this is what the
/// reference renders.
struct CatalogueOwnedFacts: View {
    /// Which lift the catalogue says this is a form of.
    let movement: Movement

    /// What the catalogue says it is performed with.
    let equipment: Equipment

    /// The bar category the catalogue gives it.
    let barType: BarType

    /// How many sides the catalogue says a rep works.
    let laterality: Laterality

    /// The name of the exercise the catalogue says this one varies, or `nil` for a root exercise.
    let parentName: String?

    /// The sentence, then one fact per field.
    var body: some View {
        Text(ExerciseLibraryStrings.formCatalogueOwned)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
        ExerciseFactRow(
            label: ExerciseLibraryStrings.formMovement,
            value: ExerciseLibraryStrings.label(for: movement)
        )
        ExerciseFactRow(
            label: ExerciseLibraryStrings.formEquipment,
            value: ExerciseLibraryStrings.label(for: equipment)
        )
        ExerciseFactRow(
            label: ExerciseLibraryStrings.formBar,
            value: ExerciseLibraryStrings.label(for: barType)
        )
        ExerciseFactRow(
            label: ExerciseLibraryStrings.formLaterality,
            value: ExerciseLibraryStrings.label(for: laterality)
        )
        // The parent as a fact, which is why the picker section is absent for these exercises. A
        // name is data and arrives `verbatim`; "Nothing" is copy and does not.
        ExerciseFactRow(
            label: ExerciseLibraryStrings.formParentSection,
            value: parentName.map { Text(verbatim: $0) }
                ?? Text(ExerciseLibraryStrings.formParentNone)
        )
    }
}

/// One vocabulary, as a row of chips with exactly one of them selected.
///
/// `ExerciseFilterBar`'s row with the optional taken out: a filter has an "All" position and a field
/// does not — every one of these carries the schema's own default until the user picks another
/// (`TR-0.3.1`), so there is no unset position to offer.
struct OptionChipRow<Value: Hashable>: View {
    /// What the row is choosing.
    let title: LocalizedStringResource

    /// Every value the user may pick, in the vocabulary's own order.
    let options: [Value]

    /// The value in force.
    @Binding var selection: Value

    /// A value's display name.
    let label: (Value) -> LocalizedStringResource

    /// The label, then the chips, scrolling horizontally so a long vocabulary does not wrap into a
    /// wall.
    ///
    /// **The row opens scrolled to whatever is selected**, which a filter row has no need of and this
    /// one does: three of the four vocabularies default to `other`, which sits *last*, so a create
    /// form without this shows three rows with no chip lit and reads as three fields nobody has
    /// filled in. An edit form has the same problem for any value late in its vocabulary.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Text(title)
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.sm.points) {
                        ForEach(options, id: \.self) { option in
                            FilterChip(
                                label: Text(label(option)),
                                isSelected: selection == option
                            ) {
                                // No toggle-to-clear, unlike the filter bar: a field with nothing in
                                // it is not a state this form can store.
                                selection = option
                            }
                            .id(option)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                // Once, on appear. A row that followed the selection afterwards would move under the
                // finger that had just tapped the chip it moved.
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

/// The parent picker (`FR-1.1.7`): which exercise this one is a variation of.
struct ExerciseParentSection: View {
    /// The form whose parent this chooses.
    @Bindable var state: ExerciseFormState

    /// The widening chip, the "nothing" row, then one row per candidate.
    var body: some View {
        GroupedSection(Text(ExerciseLibraryStrings.formParentSection)) {
            FilterChip(
                label: Text(ExerciseLibraryStrings.formParentEveryMovement),
                isSelected: state.offersEveryMovementAsParent
            ) {
                state.offersEveryMovementAsParent.toggle()
            }
            ExerciseParentList(
                candidates: state.parentCandidates,
                selection: $state.parentExerciseID
            )
        }
    }
}

/// The parent picker's rows, taking values rather than the state — this is what the snapshot
/// renders, for the reason `ExerciseGroupList` gives.
struct ExerciseParentList: View {
    /// The exercises that may be chosen, already filtered and ordered.
    let candidates: [Exercise]

    /// Which one is chosen, or `nil` for a root exercise.
    @Binding var selection: UUID?

    /// "Nothing" first — it is the default answer and the way back out of a choice — then the
    /// candidates, then the sentence that explains a picker with nothing in it.
    var body: some View {
        ExerciseChoiceRow(
            label: Text(ExerciseLibraryStrings.formParentNone),
            isSelected: selection == nil
        ) {
            selection = nil
        }
        ForEach(candidates) { candidate in
            ExerciseChoiceRow(
                label: Text(verbatim: candidate.name),
                detail: ExerciseLibraryStrings.label(for: candidate.movement),
                isSelected: selection == candidate.id
            ) {
                selection = candidate.id
            }
        }
        if candidates.isEmpty {
            Text(ExerciseLibraryStrings.formParentEmpty)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }
}

/// One selectable row: a checkmark where it is chosen, and its label.
struct ExerciseChoiceRow: View {
    /// The row's copy, built by the caller — an exercise's name is data and arrives `verbatim`.
    let label: Text

    /// What else identifies it, where a name alone would not. `nil` on the "nothing" row.
    var detail: LocalizedStringResource?

    /// Whether this row is the chosen one.
    let isSelected: Bool

    /// What choosing it does.
    let action: () -> Void

    /// The whole row is one VoiceOver element carrying the selected trait (`G-4.2`, `G-4.5`) —
    /// selection is never colour alone, and the checkmark is decoration once the trait says it.
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md.points) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(Typography.body.font)
                    .foregroundStyle(isSelected ? ColorToken.brandAccent : ColorToken.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    label
                        .font(Typography.body.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    if let detail {
                        Text(detail)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.textSecondary)
                    }
                }
                Spacer(minLength: Spacing.sm.points)
            }
            .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
