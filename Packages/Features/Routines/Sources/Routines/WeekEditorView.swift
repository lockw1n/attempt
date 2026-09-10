import DesignSystem
import DesignTokens
import Foundation
import SwiftUI

/// The one editor routines and programs collapsed into (`FR-17.10.1`, `D-17.9`).
///
/// **The name is a draft and everything else is written straight through** — see
/// ``WeekEditorState`` for why the screen is split that way. The consequence here is that there is
/// one **Save**, it is beside the name field, and it is the only control on the screen that
/// commits anything typed. It is also the screen's one filled accent (`FR-16.6.4`).
///
/// **The store is handed in rather than built here**, unlike most screens in this project. Adding
/// an exercise pushes another module's chooser, and the app target composes that chooser over this
/// same store — see ``WeekEditorState`` for the whole argument.
public struct WeekEditorView: View {
    /// The week's editor, which outlives this screen.
    @Bindable var store: WeekEditorState

    /// The locale every number on this screen is parsed and rendered against (`G-3.4`).
    @Environment(\.locale) private var locale

    /// This screen's own identity, which tells a re-run of `.task` from a fresh push.
    ///
    /// `@State` is created once per view identity: it survives the exercise chooser being pushed
    /// over this screen and does not survive the screen being popped. That is exactly the
    /// distinction ``WeekEditorState/open(screen:)`` needs.
    @State private var screen = UUID()

    /// The day whose name is being retyped, or `nil`.
    @State private var renaming: WeekEditorDay?

    /// What the rename prompt's field holds.
    @State private var renameText = ""

    /// The day the removal is being confirmed for, or `nil`.
    @State private var removing: WeekEditorDay?

    /// Builds the screen over the app's week editor.
    ///
    /// - Parameter store: The app-lifetime editor the exercise chooser also writes into.
    public init(store: WeekEditorState) {
        self.store = store
    }

    /// The week, or whichever of the screen's other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(RoutinesStrings.weekEditorTitle))
        .task {
            store.locale = locale
            await store.open(screen: screen)
        }
        .alert(
            Text(RoutinesStrings.dayRenameTitle),
            isPresented: presentation(of: $renaming),
            presenting: renaming
        ) { day in
            // An alert rather than a screen: one field, two answers, and nothing to come back to.
            // It carries no route for the set editor's reason — a half-typed rename is not a place
            // in the app.
            TextField(text: $renameText) { Text(RoutinesStrings.dayRenamePrompt) }
            Button(role: .cancel) {
                renaming = nil
            } label: {
                Text(RoutinesStrings.cancel)
            }
            Button {
                commitRename(day)
            } label: {
                Text(RoutinesStrings.dayRename)
            }
        }
        .alert(
            Text(RoutinesStrings.dayRemoveTitle),
            isPresented: presentation(of: $removing),
            presenting: removing
        ) { day in
            Button(role: .cancel) {
                removing = nil
            } label: {
                Text(RoutinesStrings.cancel)
            }
            Button(role: .destructive) {
                commitRemoval(day)
            } label: {
                Text(RoutinesStrings.dayRemove)
            }
        } message: { _ in
            Text(RoutinesStrings.dayRemoveMessage)
        }
    }

    /// The screen's three states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state**, the store being local (`G-2.1`, `G-2.3`); **no insufficient-data
    /// state**, nothing here being derived; **no missing state**, unlike the two editors this
    /// replaces — a week with no program is not an identifier that resolved to nothing, it is the
    /// screen doing its other job (`FR-17.10.3`). The empty state is the *week's*, and it carries
    /// **Add day**. A failed write is not a phase either: it renders above the days and costs the
    /// screen nothing.
    @ViewBuilder private var content: some View {
        switch store.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.weekEditorErrorHeadline),
                message: Text(RoutinesStrings.weekEditorErrorMessage),
                retryEmphasis: .primary,
                retry: { Task { await store.reload() } }
            )
        case .ready:
            WeekNameSection(store: store)
            refusals
            WeekDaysSection(store: store, rename: beginRename, remove: { removing = $0 })
        }
    }

    /// The two sentences a command can leave behind, said once for the whole screen.
    ///
    /// **One place rather than one per control**, which is ``WeekEditorState/writeFailed``'s own
    /// argument: every write here fails the same way and asks for the same thing.
    ///
    /// **The week's own name is not one of them**, and that is a correction: it is refused under
    /// the field it names, in ``WeekNameSection``. Both refusals once read one flag, so either
    /// drew both sentences and one of the two was always false.
    @ViewBuilder private var refusals: some View {
        if store.dayNameRequired {
            ErrorStateView(message: Text(RoutinesStrings.dayNameRequiredMessage))
        }
        if store.writeFailed {
            ErrorStateView(message: Text(RoutinesStrings.weekEditorWriteError))
        }
    }

    /// Opens the rename prompt on a day, seeded with the name it has.
    ///
    /// - Parameter day: The day being renamed.
    private func beginRename(_ day: WeekEditorDay) {
        renameText = day.name ?? ""
        renaming = day
    }

    /// Renames `day` and closes the prompt.
    ///
    /// **The field's text is read before the prompt is dismissed**, the alert's own dismissal being
    /// what would otherwise race the read.
    ///
    /// - Parameter day: The day being renamed.
    private func commitRename(_ day: WeekEditorDay) {
        let typed = renameText
        renaming = nil
        Task { await store.renameDay(day.id, to: typed) }
    }

    /// Removes `day` and closes the confirmation.
    ///
    /// - Parameter day: The day being removed.
    private func commitRemoval(_ day: WeekEditorDay) {
        removing = nil
        Task { await store.removeDay(day.id) }
    }

    /// A `Bool` binding over an optional, for the two `alert` presentations.
    ///
    /// - Parameter value: The state the alert is presented from.
    /// - Returns: A binding that is `true` while it holds something, and clears it on dismissal.
    private func presentation(of value: Binding<WeekEditorDay?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { presented in
                if !presented { value.wrappedValue = nil }
            })
    }
}

/// The week's name and the one command that stores it (`FR-17.10.1`).
struct WeekNameSection: View {
    /// The draft this field writes into.
    @Bindable var store: WeekEditorState

    var body: some View {
        GroupedSection(Text(RoutinesStrings.weekEditorNameLabel)) {
            TextField(text: $store.name, prompt: Text(RoutinesStrings.weekEditorNamePrompt)) {
                Text(RoutinesStrings.weekEditorNameLabel)
            }
            .labelsHidden()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points))
            if store.nameRequired {
                Text(RoutinesStrings.weekEditorNameRequired)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Task { await store.saveName() }
            } label: {
                Text(RoutinesStrings.weekEditorSave)
            }
            // The screen's one filled accent (`FR-16.6.4`): it is the only control here that
            // commits anything the lifter typed, everything else being written as it is chosen.
            .buttonStyle(.primaryAction(.fill))
            .disabled(!store.hasUnsavedName)
            .opacity(store.hasUnsavedName ? Opacity.opaque.value : Opacity.disabled.value)
        }
    }
}

/// The week's days in order, or the empty state that offers the first one (`FR-17.10.1`).
///
/// **A view of its own rather than a branch inside the screen**, which is what makes a reference
/// over it evidence about the screen: a fixture assembling `EmptyStateView` by hand would inherit
/// whatever default it was given rather than the weight this screen chose (T-16.17).
struct WeekDaysSection: View {
    /// The store these sections write into.
    @Bindable var store: WeekEditorState

    /// Opens the one-field prompt that retitles a day. The prompt is the screen's — a store cannot
    /// ask.
    let rename: (WeekEditorDay) -> Void

    /// Asks whether to take a day out of the week. The confirmation is the screen's, for the same
    /// reason.
    let remove: (WeekEditorDay) -> Void

    @ViewBuilder var body: some View {
        if store.days.isEmpty {
            EmptyStateView(
                symbolName: "calendar",
                headline: Text(RoutinesStrings.weekEditorEmptyHeadline),
                message: Text(RoutinesStrings.weekEditorEmptyMessage),
                // Secondary: **Save** is this screen's one filled accent (`FR-16.6.4`), and
                // T-16.17's rule puts a section's own action at the lighter weight.
                action: StateAction(
                    Text(RoutinesStrings.weekEditorAddDay),
                    emphasis: .secondary,
                    handler: { Task { await store.addDay() } })
            )
        } else {
            ForEach(Array(store.days.enumerated()), id: \.element.id) { index, day in
                WeekEditorDaySection(
                    store: store,
                    day: day,
                    index: index,
                    rename: { rename(day) },
                    remove: { remove(day) })
            }
            Button {
                Task { await store.addDay() }
            } label: {
                Text(RoutinesStrings.weekEditorAddDay)
            }
            // Intrinsic width is unchanged — `PrimaryActionWidth` chooses width and nothing else,
            // which is why a call site like this one is invisible to a grep for `.fill`.
            .buttonStyle(.secondaryAction(.intrinsic))
        }
    }
}
