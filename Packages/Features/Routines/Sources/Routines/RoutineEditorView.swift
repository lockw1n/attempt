import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// The routine editor (`FR-15.2.1`, `FR-15.2.2`).
///
/// **One screen for both modes**, which is `ExerciseFormView`'s call: they differ in the title and
/// in whether a record is read, and both differences live in ``RoutineEditorState``.
///
/// **The store is handed in rather than built here**, unlike every other screen in this project.
/// Adding an exercise pushes another module's chooser, and the app target composes that chooser
/// over this same store — see ``RoutineEditorState`` for the whole argument.
public struct RoutineEditorView: View {
    /// The editor's draft, which outlives this screen.
    @Bindable var store: RoutineEditorState

    /// Which routine this screen is about. Applied to the store on appearance.
    private let mode: RoutineEditorMode

    /// The locale every number on this screen is parsed and rendered against (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Pops the editor once a save has landed. The list underneath re-reads for itself.
    @Environment(\.dismiss) private var dismiss

    /// Builds the screen over the app's editor store.
    ///
    /// - Parameters:
    ///   - mode: Whether this authors a new routine or edits an existing one.
    ///   - store: The app-lifetime editor state the exercise chooser also writes into.
    public init(mode: RoutineEditorMode, store: RoutineEditorState) {
        self.mode = mode
        self.store = store
    }

    /// The draft, or whichever of the screen's three other states is current.
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
        .task {
            store.locale = locale
            await store.open(mode)
        }
        // The save is what ends this screen, and the store is what knows the save landed — a
        // dismissal driven from the button would fire on a write that failed.
        .onChange(of: store.didSave) { _, saved in
            if saved { dismiss() }
        }
    }

    /// The screen's title, which is the only copy the two modes do not share.
    private var title: LocalizedStringResource {
        switch mode {
        case .create: RoutinesStrings.editorCreateTitle
        case .edit: RoutinesStrings.editorEditTitle
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state**, the store being local (`G-2.1`, `G-2.3`); **no insufficient-data
    /// state**, nothing here being derived. The `Empty` state is the exercise list's rather than
    /// the screen's — a routine with a name and no exercises is a form in progress, not an empty
    /// screen. A failed *save* is not a phase either: it renders beside the save button and costs
    /// the draft nothing.
    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.editorErrorHeadline),
                message: Text(RoutinesStrings.editorErrorMessage),
                retry: { Task { await store.reload() } }
            )
        case .missing:
            // No retry: the identifier resolved to nothing, and reading again resolves to nothing.
            ErrorStateView(
                headline: Text(RoutinesStrings.editorMissingHeadline),
                message: Text(RoutinesStrings.editorMissingMessage)
            )
        case .ready:
            ready
        }
    }

    /// The name, the exercises, and the command that commits them.
    ///
    /// Everything goes inert while a save is in flight: the records are built when the button is
    /// tapped, and a form that accepted keystrokes afterwards would be taking edits it is about to
    /// dismiss without storing.
    @ViewBuilder private var ready: some View {
        RoutineNameSection(store: store)
            .disabled(store.isSaving)
        RoutineSlotsSection(store: store)
            .disabled(store.isSaving)
        saveCommand
    }

    /// The save button, its refusal, and a failed save beneath it.
    ///
    /// The button is disabled rather than hidden: a command that vanishes gives the user nothing to
    /// aim at, and the sentence beside it says why it is off.
    @ViewBuilder private var saveCommand: some View {
        Button {
            Task { await store.save() }
        } label: {
            Text(RoutinesStrings.editorSave)
        }
        .buttonStyle(.primaryAction(.fill))
        .disabled(!store.canSave)
        .opacity(store.canSave ? Opacity.opaque.value : Opacity.disabled.value)

        if !store.everyGroupResolves {
            Text(RoutinesStrings.editorGroupRefusal)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if store.writeFailure != nil {
            // The shared error component rather than a local label, and the draft stays on screen
            // beside it — a failed write costs the screen nothing.
            ErrorStateView(
                message: Text(RoutinesStrings.editorWriteError),
                retry: { Task { await store.save() } }
            )
        }
    }
}

/// The routine's name (`FR-15.2.1`) — the one field outside the exercises.
struct RoutineNameSection: View {
    /// The draft this field writes into.
    @Bindable var store: RoutineEditorState

    var body: some View {
        GroupedSection(Text(RoutinesStrings.editorNameLabel)) {
            VStack(alignment: .leading, spacing: Spacing.xs.points) {
                TextField(text: $store.name, prompt: Text(RoutinesStrings.editorNamePrompt)) {
                    Text(RoutinesStrings.editorNameLabel)
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
                if store.trimmedName.isEmpty {
                    Text(RoutinesStrings.editorNameCaption)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The routine's exercises in order, each with its target groups (`FR-15.2.1`).
struct RoutineSlotsSection: View {
    /// The draft these rows write into.
    @Bindable var store: RoutineEditorState

    var body: some View {
        GroupedSection(Text(RoutinesStrings.editorExercisesSection)) {
            if store.slots.isEmpty {
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(RoutinesStrings.editorExercisesEmptyHeadline),
                    message: Text(RoutinesStrings.editorExercisesEmptyMessage)
                )
            } else {
                ForEach(Array(store.slots.enumerated()), id: \.element.id) { index, slot in
                    RoutineSlotCard(store: store, slot: slot, index: index)
                }
            }
            NavigationLink(value: Route.exerciseLibrary(.routineExercisePicker)) {
                Text(RoutinesStrings.editorAddExercise)
            }
            .buttonStyle(.primaryAction(.fill))
        }
    }
}
