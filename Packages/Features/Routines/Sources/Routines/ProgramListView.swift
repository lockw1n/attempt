import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import RepositoryInterface
import SwiftUI

/// Every program the lifter has authored, and which one Train is following (`FR-16.8.1`).
///
/// The view half of `TR-1.2`'s pattern, and `RoutineListView`'s shape: a `ScrollView` and a
/// `LazyVStack`, because `TR-1.12`'s harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct ProgramListView: View {
    @State private var state: ProgramListState

    /// Whether the new-program prompt is on screen.
    ///
    /// **The screen's rather than the state's**, on `RoutineListView`'s rule: a name being typed is
    /// not a fact about the library until the command is confirmed.
    @State private var isNaming = false

    /// What is in that prompt's field.
    @State private var newName = ""

    /// The shell's navigation position: a program written here is opened in the editor, which is a
    /// push this screen makes rather than a link the user taps.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the screen over the repository it reads through.
    ///
    /// - Parameter repository: Where programs come from.
    public init(repository: any ProgramRepository) {
        _state = State(initialValue: ProgramListState(repository: repository))
    }

    /// The programs, or whichever of the screen's three other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(RoutinesStrings.programsTitle))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openPrompt()
                } label: {
                    Text(RoutinesStrings.programsNew)
                }
            }
        }
        // Re-read on every appearance: the editor pushed over this screen changes both the day
        // count and which program is current.
        .task { await state.load() }
        .alert(Text(RoutinesStrings.programsNewTitle), isPresented: $isNaming) {
            // An alert rather than a screen, on the rename prompt's argument one file over: one
            // field, two answers, and nothing to come back to.
            TextField(text: $newName) { Text(RoutinesStrings.programsNewPrompt) }
            Button(role: .cancel) {
                isNaming = false
            } label: {
                Text(RoutinesStrings.listCancel)
            }
            Button {
                commitCreate()
            } label: {
                Text(RoutinesStrings.programsCreate)
            }
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state** — the store is local (`G-2.1`, `G-2.3`). **No insufficient-data state**
    /// — a program is what the lifter typed in, not a value derived from history.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.programsErrorHeadline),
                message: Text(RoutinesStrings.programsErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .ready where state.programs.isEmpty:
            refusals
            // FR-1.13.2: the first-launch empty state carries the action that ends it.
            EmptyStateView(
                symbolName: "calendar",
                headline: Text(RoutinesStrings.programsEmptyHeadline),
                message: Text(RoutinesStrings.programsEmptyMessage),
                action: StateAction(Text(RoutinesStrings.programsNew)) { openPrompt() }
            )
        case .ready:
            refusals
            LazyVStack(spacing: Spacing.md.points) {
                ForEach(state.programs) { program in
                    NavigationLink(
                        value: Route.routines(.programEdit(programID: program.id))
                    ) {
                        ProgramRow(program: program)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Why the last **New program** wrote nothing, above the list rather than over it.
    @ViewBuilder private var refusals: some View {
        switch state.commandFailure {
        case .nameRequired:
            ErrorStateView(message: Text(RoutinesStrings.programsNameRequiredMessage))
        case .writeFailed:
            ErrorStateView(message: Text(RoutinesStrings.programsWriteErrorMessage))
        case nil:
            EmptyView()
        }
    }

    /// Opens the prompt on an empty field.
    ///
    /// **Empty rather than seeded**, unlike the rename one file over: there is no name yet to fix.
    private func openPrompt() {
        newName = ""
        isNaming = true
    }

    /// Writes the program and opens it.
    ///
    /// **The field's text is read before the prompt is dismissed**, the alert's own dismissal being
    /// what would otherwise race the read. The push happens only where a row was written — on
    /// `TrainingHomeView`'s rule for a command that navigates.
    private func commitCreate() {
        let typed = newName
        isNaming = false
        Task {
            guard let programID = await state.create(named: typed) else { return }
            navigation?.navigate(to: .routines(.programEdit(programID: programID)))
        }
    }
}

/// One program's row: its name, how many days it is made of, and whether Train is following it.
struct ProgramRow: View {
    /// What the row draws.
    let program: ProgramSummary

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                    name
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(RoutinesStrings.programsDayCount(program.dayCount))
                        .font(Typography.metricContext.font)
                        .foregroundStyle(ColorToken.textSecondary)
                    if program.isCurrent {
                        Text(RoutinesStrings.programsCurrentBadge)
                            .font(Typography.caption.font)
                            .foregroundStyle(ColorToken.brandAccent)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    // The chevron says "this pushes"; the row's own lines are what VoiceOver reads.
                    .accessibilityHidden(true)
            }
            .frame(minHeight: TouchTarget.standard.points, alignment: .leading)
        }
        // One element, not three: a row is one destination (`G-4.2`).
        .accessibilityElement(children: .combine)
    }

    /// The row's title — the lifter's own name, or the sentence standing in for one that is empty.
    ///
    /// A `Text` rather than a `LocalizedStringResource`, on ``RoutineRow``'s rule: only one of the
    /// two is copy.
    private var name: Text {
        program.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Text(RoutinesStrings.programsUnnamed)
            : Text(verbatim: program.name)
    }
}
