import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// The program in force, on Train's root (`FR-16.8.2`, `FR-16.8.4`).
///
/// **The first thing on the screen when there is a run, and nothing at all when there is not.** A
/// lifter following a plan opens Train to be told which day is next and to tap once; a lifter
/// running no program is not missing one, so this draws no empty state of its own — which is why it
/// sits above `FR-1.13.2`'s, rather than replacing it.
///
/// Taking the state rather than reading a store, for `SessionInProgressSection`'s reason: this is
/// what the snapshot renders, and `TR-1.12`'s harness cannot run the `.task` behind it.
struct ProgramNextUpSection: View {
    /// The run in force, and the two commands that move it.
    let state: ProgramNextUpState

    /// Why the program's cursor did not move when the last workout was finished, or `nil` — see
    /// ``ActiveSessionStore/programAdvanceFailure``.
    let advanceFailure: String?

    /// Starts the program's next day: its `ProgramDay.order`, and the routine it names.
    let start: (Int, UUID) -> Void

    /// Whichever of the card's states is current, or nothing.
    ///
    /// **A read that failed says so and a read that has not happened says nothing.** The loading
    /// case is deliberately silent rather than a spinner: this section is one card on a screen that
    /// has its own state below it, and a placeholder that appears for a frame and then vanishes on
    /// every appearance is worse than a card that arrives.
    var body: some View {
        switch state.phase {
        case .idle, .loading:
            EmptyView()
        case .failed:
            ErrorStateView(
                message: Text(LoggingStrings.programErrorMessage),
                retry: { Task { await state.load() } })
        case .ready:
            if let nextUp = state.nextUp {
                diagnostics
                ProgramNextUpCard(
                    nextUp: nextUp,
                    start: start,
                    skip: { index in Task { await state.skipDay(at: index) } },
                    startNextWeek: { Task { await state.startNextWeek() } })
            }
        }
    }

    /// Whichever write refusals are current, drawn above the card rather than over it.
    ///
    /// **The finish's own failure is here rather than on the session screen**, because that screen
    /// is gone by the time it is known: the workout was stored and the screen dismissed, and this is
    /// the surface the lifter arrives at — the one drawing the day that did not move.
    @ViewBuilder private var diagnostics: some View {
        if advanceFailure != nil {
            ErrorStateView(message: Text(LoggingStrings.programAdvanceErrorMessage))
        }
        switch state.commandFailure {
        case .skipFailed:
            ErrorStateView(message: Text(LoggingStrings.programSkipErrorMessage))
        case .nextWeekFailed:
            ErrorStateView(message: Text(LoggingStrings.programNextWeekErrorMessage))
        case nil:
            EmptyView()
        }
    }
}

/// The card itself: which program, where it has got to, and what to do about it (`FR-16.8.2`).
///
/// **A value and three closures rather than the state**, which is what makes it snapshottable:
/// `TR-1.12`'s harness cannot run a read, so a card that fetched its own facts would render as the
/// state it has before one — see ``SessionInProgressSection`` for the same split one screen over.
struct ProgramNextUpCard: View {
    /// The run in force.
    let nextUp: ProgramNextUp

    /// Starts the program's next day: its `ProgramDay.order`, and the routine it names.
    let start: (Int, UUID) -> Void

    /// Moves the cursor past a day without logging anything (`FR-16.8.4`).
    let skip: (Int) -> Void

    /// Rebuilds the week's days from what was lifted and advances the run (`FR-16.8.4`).
    let startNextWeek: () -> Void

    var body: some View {
        GroupedSection(Text(LoggingStrings.programSection)) {
            // The lifter's own words, so never looked up in a catalogue (`G-3.4`).
            Text(verbatim: nextUp.programName)
                .font(Typography.cardTitle.font)
                .foregroundStyle(ColorToken.textPrimary)
            switch nextUp.day {
            case .next(let index, let routineID, let name):
                nextDay(index: index, routineID: routineID, name: name)
            case .archivedRoutine(let index):
                position(day: index)
                EmptyStateView(
                    symbolName: "archivebox",
                    headline: Text(LoggingStrings.programArchivedHeadline),
                    message: Text(LoggingStrings.programArchivedMessage),
                    action: StateAction(
                        Text(LoggingStrings.programSkipAction),
                        emphasis: .secondary,
                        handler: { skip(index) }))
            case .weekComplete:
                weekComplete
            case .noDays:
                EmptyStateView(
                    symbolName: "calendar",
                    headline: Text(LoggingStrings.programNoDaysHeadline),
                    message: Text(LoggingStrings.programNoDaysMessage))
            }
        }
    }

    /// The day to train, and `NFR-15.3`'s first tap.
    ///
    /// **Start is Train's one filled accent while it is drawn** (`FR-16.6.4`) — see
    /// ``TrainingHomeView`` for the other half, which steps down to make room for it.
    @ViewBuilder private func nextDay(index: Int, routineID: UUID, name: String) -> some View {
        position(day: index)
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(verbatim: name)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textPrimary)
        }
        Button {
            start(index, routineID)
        } label: {
            Text(LoggingStrings.programStartAction)
        }
        .buttonStyle(.primaryAction(.fill))
        Button {
            skip(index)
        } label: {
            Text(LoggingStrings.programSkipAction)
        }
        .buttonStyle(.secondaryAction(.fill))
    }

    /// `FR-16.8.4`'s offer, once every day of the week has been trained or skipped.
    private var weekComplete: some View {
        EmptyStateView(
            symbolName: "checkmark.seal",
            headline: Text(LoggingStrings.programWeekCompleteHeadline(week: nextUp.weekNumber)),
            message: Text(LoggingStrings.programWeekCompleteMessage),
            action: StateAction(Text(LoggingStrings.programNextWeekAction), handler: startNextWeek))
    }

    /// Where the run has got to — `Week 3 · Day 2`, the day counted from one.
    ///
    /// **The order plus one, not the position in the list.** A `ProgramDay.order` is the cursor's
    /// own unit (`FR-16.8.3`), and a lifter counts days from one.
    private func position(day index: Int) -> some View {
        Text(LoggingStrings.programWeekAndDay(week: nextUp.weekNumber, day: index + 1))
            .font(Typography.metricContext.font)
            .foregroundStyle(ColorToken.textSecondary)
    }
}

extension ProgramNextUp {
    /// Whether this reading draws a filled accent of its own (`FR-16.6.4`).
    ///
    /// What `TrainingHomeView` steps its own action down for — two filled accents on one screen are
    /// two primary actions and therefore none.
    var spendsAccent: Bool {
        switch day {
        case .next, .weekComplete: true
        case .archivedRoutine, .noDays: false
        }
    }
}
