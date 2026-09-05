import DesignSystem
import DesignTokens
import Foundation
import RepositoryInterface
import SwiftUI

/// The editor over one program: its name, its note, the days it is made of, and the command that
/// puts it on Train (`FR-16.8.1`, `FR-16.8.2`).
///
/// **The days are written straight through and the two text fields are not** — see
/// ``ProgramEditorState`` for why the screen is split that way. The consequence here is that there
/// is one **Save**, it is beside the fields, and it is the only control on the screen that commits
/// anything.
public struct ProgramEditorView: View {
    @State private var state: ProgramEditorState

    /// Builds the editor over the program the route named.
    ///
    /// - Parameters:
    ///   - programID: The program to edit.
    ///   - programs: Where programs, days and runs come from.
    ///   - routines: Where the days' routines come from.
    public init(
        programID: UUID, programs: any ProgramRepository, routines: any RoutineRepository
    ) {
        _state = State(
            initialValue: ProgramEditorState(
                programID: programID, repository: programs, routines: routines))
    }

    /// The program, or whichever of the screen's three other states is current.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(RoutinesStrings.programEditorTitle))
        // Re-read on every appearance: a routine archived in another screen changes what the days
        // resolve to.
        .task { await state.load() }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state** and **no insufficient-data state**, on ``ProgramListView``'s reasons. A
    /// failed *write* is not a phase either: it renders where the command is and costs the screen
    /// nothing.
    @ViewBuilder private var content: some View {
        switch state.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(RoutinesStrings.programEditorErrorHeadline),
                message: Text(RoutinesStrings.programEditorErrorMessage),
                retry: { Task { await state.load() } }
            )
        case .missing:
            // No retry: the identifier resolved to nothing, and reading again resolves to nothing.
            ErrorStateView(
                headline: Text(RoutinesStrings.programEditorMissingHeadline),
                message: Text(RoutinesStrings.programEditorMissingMessage)
            )
        case .ready:
            ProgramDetailsSection(state: state)
            writeFailure
            currentCommand
            ProgramDaysSection(
                days: state.days,
                move: { index, offset in Task { await state.moveDay(at: index, by: offset) } },
                remove: { dayID in Task { await state.removeDay(id: dayID) } })
            ProgramAddDaySection(
                choices: state.choices,
                add: { routineID in Task { await state.addDay(routineID: routineID) } })
        }
    }

    /// A write that did not land, said once for every command on the screen.
    ///
    /// **One sentence rather than one per control**, which is ``ProgramEditorState/writeFailed``'s
    /// own argument: every write here fails the same way and asks for the same thing.
    @ViewBuilder private var writeFailure: some View {
        if state.writeFailed {
            ErrorStateView(message: Text(RoutinesStrings.programEditorWriteError))
        }
    }

    /// `FR-16.8.2`'s **Make current**, or the sentence saying it already is.
    ///
    /// **The screen's one filled accent** (`FR-16.6.4`): it is the command that makes this program
    /// mean anything on Train, and **Save** beside the fields is the unfilled companion.
    @ViewBuilder private var currentCommand: some View {
        if state.isCurrent {
            Text(RoutinesStrings.programEditorIsCurrent)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Button {
                Task { await state.makeCurrent() }
            } label: {
                Text(RoutinesStrings.programEditorMakeCurrent)
            }
            .buttonStyle(.primaryAction(.fill))
        }
    }
}

/// The program's name and note, and the one command that stores them (`FR-16.8.1`).
struct ProgramDetailsSection: View {
    /// The draft these fields write into.
    @Bindable var state: ProgramEditorState

    var body: some View {
        GroupedSection(Text(RoutinesStrings.programEditorNameLabel)) {
            field(
                text: $state.name,
                label: RoutinesStrings.programEditorNameLabel,
                prompt: RoutinesStrings.programEditorNamePrompt)
            Text(RoutinesStrings.programEditorNoteLabel)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
            field(
                text: $state.notes,
                label: RoutinesStrings.programEditorNoteLabel,
                prompt: RoutinesStrings.programEditorNotePrompt)
            Button {
                Task { await state.saveDetails() }
            } label: {
                Text(RoutinesStrings.programEditorSave)
            }
            .buttonStyle(.secondaryAction(.fill))
            .disabled(!state.hasUnsavedDetails)
            .opacity(state.hasUnsavedDetails ? Opacity.opaque.value : Opacity.disabled.value)
        }
    }

    /// One of the two fields, drawn the same way the routine editor's name is.
    private func field(
        text: Binding<String>, label: LocalizedStringResource, prompt: LocalizedStringResource
    ) -> some View {
        TextField(text: text, prompt: Text(prompt)) { Text(label) }
            .labelsHidden()
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
            .textFieldStyle(.plain)
            .padding(Spacing.md.points)
            .background(
                ColorToken.surfaceRaised, in: .rect(cornerRadius: CornerRadius.control.points))
    }
}

/// The days the program is made of, in order (`FR-16.8.1`).
///
/// **Values and closures rather than the state**, on ``ProgramDayCard``'s argument.
struct ProgramDaysSection: View {
    /// The days, in order.
    let days: [ProgramDayRow]

    /// Moves the day at an index by an offset — `-1` earlier, `1` later.
    let move: (Int, Int) -> Void

    /// Takes one day out of the program.
    let remove: (UUID) -> Void

    var body: some View {
        GroupedSection(Text(RoutinesStrings.programEditorDaysSection)) {
            if days.isEmpty {
                EmptyStateView(
                    symbolName: "calendar",
                    headline: Text(RoutinesStrings.programEditorDaysEmptyHeadline),
                    message: Text(RoutinesStrings.programEditorDaysEmptyMessage)
                )
            } else {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    ProgramDayCard(
                        day: day,
                        index: index,
                        count: days.count,
                        move: { move(index, $0) },
                        remove: { remove(day.id) })
                }
            }
        }
    }
}

/// One day: which position it is, what is trained on it, and the three commands that move it.
///
/// **Stacked rather than sharing a row**, on `RoutineCard`'s argument: three commands and a name do
/// not fit a row at `accessibility3`.
/// **A value and two closures rather than the state**, on Logging's Next-up card's argument:
/// `TR-1.12`'s harness cannot run a read, so a row that fetched its own facts would render empty.
struct ProgramDayCard: View {
    /// What the card draws.
    let day: ProgramDayRow

    /// Its position in the week, which is what the moves are relative to.
    let index: Int

    /// How many days there are, which is what disables the last one's **down**.
    let count: Int

    /// Moves this day by an offset — `-1` earlier, `1` later.
    let move: (Int) -> Void

    /// Takes it out of the program.
    let remove: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.sm.points) {
                Text(RoutinesStrings.programEditorDayNumber(index + 1))
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textSecondary)
                routine
                commands
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What is trained on this day, or the sentence for a routine that has been archived.
    ///
    /// **The archived case is drawn here and not hidden**, which is
    /// `ProgramRepository.days(forProgramID:includingDeleted:)`'s obligation
    /// arriving at its caller: the row is returned intact, and this is the screen that answers it.
    @ViewBuilder private var routine: some View {
        if let name = day.routineName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            Text(verbatim: name)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
        } else if day.routineName == nil {
            Text(RoutinesStrings.programEditorArchivedRoutine)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textTertiary)
        } else {
            Text(RoutinesStrings.listUnnamed)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textTertiary)
        }
    }

    /// Earlier, later, gone — each a 44pt target with a name for VoiceOver (`G-4.2`, `G-4.3`).
    private var commands: some View {
        HStack(spacing: Spacing.sm.points) {
            SlotCommandButton(
                symbolName: "arrow.up",
                label: RoutinesStrings.programEditorDayUp,
                isEnabled: index > 0,
                action: { move(-1) })
            SlotCommandButton(
                symbolName: "arrow.down",
                label: RoutinesStrings.programEditorDayDown,
                isEnabled: index < count - 1,
                action: { move(1) })
            SlotCommandButton(
                symbolName: "trash",
                label: RoutinesStrings.programEditorRemoveDay,
                isEnabled: true,
                action: remove)
            Spacer()
        }
    }
}

/// The routines a day can be built from (`FR-16.8.1`).
///
/// **A list of buttons rather than a menu or a picker**, which is the shape every chooser in this
/// app takes: `TR-1.12`'s harness renders through `ImageRenderer`, and a UIKit-backed control draws
/// as a placeholder — so a reference over this screen would prove nothing about the one control
/// that adds a day.
struct ProgramAddDaySection: View {
    /// The routines a day can name.
    let choices: [ProgramRoutineChoice]

    /// Appends a day naming the routine that was tapped.
    let add: (UUID) -> Void

    var body: some View {
        GroupedSection(Text(RoutinesStrings.programEditorAddSection)) {
            if choices.isEmpty {
                EmptyStateView(
                    symbolName: "list.bullet.rectangle",
                    headline: Text(RoutinesStrings.programEditorAddEmptyHeadline),
                    message: Text(RoutinesStrings.programEditorAddEmptyMessage)
                )
            } else {
                ForEach(choices) { choice in
                    Button {
                        add(choice.id)
                    } label: {
                        HStack(spacing: Spacing.sm.points) {
                            name(choice)
                                .font(Typography.body.font)
                                .foregroundStyle(ColorToken.textPrimary)
                            Spacer(minLength: Spacing.sm.points)
                            Image(systemName: "plus")
                                .foregroundStyle(ColorToken.brandAccent)
                                // The label already says what is being added (`G-4.2`).
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: TouchTarget.standard.points)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// One choice's title — the lifter's own words, or the stand-in for a routine with no name.
    private func name(_ choice: ProgramRoutineChoice) -> Text {
        choice.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Text(RoutinesStrings.listUnnamed)
            : Text(verbatim: choice.name)
    }
}
