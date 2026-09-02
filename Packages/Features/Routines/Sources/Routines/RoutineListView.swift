import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import RepositoryInterface
import SwiftUI

/// Every routine the lifter has authored (`FR-15.2.1`).
///
/// The view half of `TR-1.2`'s pattern, and the same `ScrollView`/`LazyVStack` shape the Phase 1
/// screens use for the same reason — `TR-1.12`'s harness renders through `ImageRenderer`, which
/// draws a placeholder for anything UIKit-backed.
public struct RoutineListView: View {
    @State private var state: RoutineListState

    /// Starts a workout from one routine, reporting what that did (`FR-15.2.3`).
    ///
    /// **A closure the app target supplies**, on `LastWorkoutSection`'s precedent: writing a
    /// session is `Logging`'s and `TR-1.3` keeps the feature packages off each other, so the target
    /// that owns both composes them. Required rather than optional — this screen's primary command
    /// is starting a workout, and a default that did nothing would be a button that silently is not
    /// one.
    private let startWorkout: @MainActor (UUID) async -> RoutineStartOutcome

    /// Which routine the rename prompt is open over, or `nil` (`FR-15.2.5`).
    ///
    /// **The screen's rather than the state's**, on the set editor's rule one module over: a name
    /// being typed into a prompt is not a fact about the library until the command is confirmed.
    @State private var renaming: RoutineSummary?

    /// What is in that prompt's field. Seeded from the routine's stored name when it opens.
    @State private var renameText = ""

    /// Which routine the archive confirmation is open over, or `nil`.
    ///
    /// **It asks first, unlike the other two commands**, this being the one here with no way back —
    /// see ``RoutineListState/archive(_:)``.
    @State private var archiving: RoutineSummary?

    /// The shell's navigation position: starting a workout lands on Train's session screen, which
    /// is not a push from here.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the screen over the repository it reads through.
    ///
    /// - Parameters:
    ///   - repository: Where routines come from. `Persistence`'s implementation in the app;
    ///     anything conforming in a test or a preview.
    ///   - startWorkout: Starts a workout from the routine it is given (`FR-15.2.3`).
    public init(
        repository: any RoutineRepository,
        startWorkout: @escaping @MainActor (UUID) async -> RoutineStartOutcome
    ) {
        _state = State(initialValue: RoutineListState(repository: repository))
        self.startWorkout = startWorkout
    }

    /// The routines, or whichever of the screen's three other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(RoutinesStrings.listTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: Route.routines(.routineCreate)) {
                    Text(RoutinesStrings.listNewRoutine)
                }
            }
        }
        // Re-read on every appearance, not only the first: the editor pushed over this screen is
        // what changes what it lists, and it writes on its way out.
        .task { await state.load() }
        .alert(
            Text(RoutinesStrings.listRenameTitle),
            isPresented: presentation(of: $renaming),
            presenting: renaming
        ) { routine in
            // An alert rather than a screen: one field, two answers, and nothing to come back to.
            // It carries no route for the reason the set editor carries none — a half-typed rename
            // is not a place in the app.
            TextField(text: $renameText) { Text(RoutinesStrings.listRenamePrompt) }
            Button(role: .cancel) {
                renaming = nil
            } label: {
                Text(RoutinesStrings.listCancel)
            }
            Button {
                commitRename(routine)
            } label: {
                Text(RoutinesStrings.listRename)
            }
        }
        .alert(
            Text(RoutinesStrings.listArchiveTitle),
            isPresented: presentation(of: $archiving),
            presenting: archiving
        ) { routine in
            Button(role: .cancel) {
                archiving = nil
            } label: {
                Text(RoutinesStrings.listCancel)
            }
            Button(role: .destructive) {
                commitArchive(routine)
            } label: {
                Text(RoutinesStrings.listArchive)
            }
        } message: { _ in
            Text(RoutinesStrings.listArchiveMessage)
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state**, on the argument every local screen makes: the store is on the device
    /// (`G-2.1`, `G-2.3`), so there is no fetch to be offline for. **No insufficient-data state**
    /// either (`FR-1.13.3`) — a routine is what the lifter typed in, not a value derived from
    /// history.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.listErrorHeadline),
                message: Text(RoutinesStrings.listErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .ready where state.routines.isEmpty:
            // FR-1.13.2: the first-launch empty state carries the action that ends it.
            EmptyStateView(
                symbolName: "list.bullet.rectangle",
                headline: Text(RoutinesStrings.listEmptyHeadline),
                message: Text(RoutinesStrings.listEmptyMessage)
            )
            NavigationLink(value: Route.routines(.routineCreate)) {
                Text(RoutinesStrings.listNewRoutine)
            }
            .buttonStyle(.primaryAction(.fill))
        case .ready:
            refusals
            LazyVStack(spacing: Spacing.md.points) {
                ForEach(state.routines) { routine in
                    RoutineCard(
                        routine: routine,
                        start: { start(routine.id) },
                        duplicate: { Task { await state.duplicate(routine.id) } },
                        rename: { openRename(routine) },
                        archive: { archiving = routine }
                    )
                }
            }
        }
    }

    /// Whichever write refusals are current, drawn above the routines rather than over them: the
    /// list is still what the lifter came for.
    ///
    /// **Four separate sentences and up to two of them at once** (`FR-15.2.3`, `FR-15.2.5`). Each
    /// says a different thing — one names an action the lifter can take, one names a field they can
    /// fill in, and two name only the store — and a start refusal is not retired by a management
    /// command failing.
    @ViewBuilder private var refusals: some View {
        switch state.startFailure {
        case .workoutInProgress:
            ErrorStateView(message: Text(RoutinesStrings.listStartInProgressMessage))
        case .writeFailed:
            ErrorStateView(message: Text(RoutinesStrings.listStartWriteErrorMessage))
        case .started, nil:
            EmptyView()
        }
        switch state.managementFailure {
        case .nameRequired:
            ErrorStateView(message: Text(RoutinesStrings.listNameRequiredMessage))
        case .writeFailed:
            ErrorStateView(message: Text(RoutinesStrings.listManageWriteErrorMessage))
        case nil:
            EmptyView()
        }
    }

    /// Starts a workout from `routineID` and opens it (`FR-15.2.3`, `NFR-15.3`).
    ///
    /// **The push happens only when a workout was started**, on `TrainingHomeView`'s rule for the
    /// same command: a refusal leaves the lifter on this screen with the reason beside the routines
    /// rather than on a session screen showing a workout they did not ask for.
    ///
    /// - Parameter routineID: The routine to start from.
    private func start(_ routineID: UUID) {
        Task {
            let outcome = await startWorkout(routineID)
            state.startDidFinish(outcome)
            guard outcome == .started else { return }
            navigation?.navigate(to: .training(.activeSession))
        }
    }

    /// Opens the rename prompt over `routine`, holding the name it has now (`FR-15.2.5`).
    ///
    /// **Seeded rather than empty**, because a rename is usually an edit: a lifter fixing a typo
    /// should not have to retype the rest.
    ///
    /// - Parameter routine: The row whose command was tapped.
    private func openRename(_ routine: RoutineSummary) {
        renameText = routine.name
        renaming = routine
    }

    /// Renames `routine` to what the prompt held and closes it.
    ///
    /// **The field's text is read before the prompt is dismissed**, the alert's own dismissal being
    /// what would otherwise race the read.
    ///
    /// - Parameter routine: The routine being renamed.
    private func commitRename(_ routine: RoutineSummary) {
        let typed = renameText
        renaming = nil
        Task { await state.rename(routine.id, to: typed) }
    }

    /// Archives `routine` and closes the confirmation.
    ///
    /// - Parameter routine: The routine being archived.
    private func commitArchive(_ routine: RoutineSummary) {
        archiving = nil
        Task { await state.archive(routine.id) }
    }

    /// A `Bool` binding over an optional, for the two `alert` presentations.
    ///
    /// **It only ever clears**, never sets: an alert is opened by choosing what it is about, and a
    /// setter that could turn one on without a subject would be a prompt with nothing in it.
    ///
    /// - Parameter value: What the alert is open over.
    /// - Returns: Whether it is open.
    private func presentation<Value>(of value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } })
    }
}

/// One routine as the list offers it: the plan to edit, the command that starts a workout from it,
/// and the three that manage it (`FR-15.2.1`, `FR-15.2.3`, `FR-15.2.5`).
///
/// **Everything stacked rather than sharing a row**, and nothing nested in the link. A button
/// inside a `NavigationLink` is the classic SwiftUI trap — the outer link swallows the inner tap —
/// and side by side they are commands sharing a row at `accessibility3`, which is
/// `SessionExerciseCard`'s reason for stacking its own two.
///
/// **The management commands sit below the start**, not between it and the name: `FR-15.2.3` is
/// what this list is for, and a row of secondary controls driven in above it would push the primary
/// action away from the routine it belongs to. They are icon buttons carrying their names to
/// VoiceOver (`G-4.2`), the shape the editor's slot header already uses for the same reason — three
/// spelled-out commands do not fit a row at any Dynamic Type size.
struct RoutineCard: View {
    /// What the card draws.
    let routine: RoutineSummary

    /// Starts a workout from this routine.
    let start: () -> Void

    /// Copies this routine (`FR-15.2.5`). It acts at once — a copy costs nothing to undo, being a
    /// new row the lifter can archive.
    let duplicate: () -> Void

    /// Opens the prompt that retitles it.
    let rename: () -> Void

    /// Opens the confirmation that archives it.
    let archive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            NavigationLink(value: Route.routines(.routineEdit(routineID: routine.id))) {
                RoutineRow(routine: routine)
            }
            .buttonStyle(.plain)
            Button(action: start) {
                Text(RoutinesStrings.listStartAction)
            }
            .buttonStyle(.primaryAction(.fill))
            management
        }
    }

    /// Duplicate, rename, archive — each a 44pt target (`G-4.3`) with a label rather than a bare
    /// glyph (`G-4.2`), and leading-aligned so they read as this card's rather than the list's.
    @ViewBuilder private var management: some View {
        HStack(spacing: Spacing.sm.points) {
            SlotCommandButton(
                symbolName: "plus.square.on.square",
                label: RoutinesStrings.listDuplicate,
                isEnabled: true,
                action: duplicate)
            SlotCommandButton(
                symbolName: "pencil",
                label: RoutinesStrings.listRename,
                isEnabled: true,
                action: rename)
            SlotCommandButton(
                symbolName: "archivebox",
                label: RoutinesStrings.listArchive,
                isEnabled: true,
                action: archive)
            Spacer()
        }
    }
}

/// One routine's row: its name, and how many exercises it prescribes.
struct RoutineRow: View {
    /// What the row draws.
    let routine: RoutineSummary

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    name
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(RoutinesStrings.listExerciseCount(routine.exerciseCount))
                        .font(Typography.metricContext.font)
                        .foregroundStyle(ColorToken.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    // The chevron says "this pushes"; the row's own two lines are what VoiceOver
                    // reads, and a glyph announced beside them is noise (`G-4.2`).
                    .accessibilityHidden(true)
            }
            .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
        }
        // One element, not three: a row is one destination (`G-4.2`).
        .accessibilityElement(children: .combine)
    }

    /// The row's title — the lifter's own name for the routine, or the sentence standing in for
    /// one that is empty.
    ///
    /// **A `Text` rather than a `LocalizedStringResource`**, because only one of the two is copy:
    /// the stored name is the user's words and must never be looked up in a catalogue, while the
    /// stand-in is this module's and must be. The editor refuses to save an empty name, so the
    /// stand-in is what a row written by something else gets rather than a case this app produces.
    private var name: Text {
        routine.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Text(RoutinesStrings.listUnnamed)
            : Text(verbatim: routine.name)
    }
}
