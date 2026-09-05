import AppNavigation
import DesignSystem
import Foundation
import Localization
import RepositoryInterface
import SwiftUI

/// Which of the card's five states is current (`FR-1.13.1`).
///
/// **In-progress and finished are separate states rather than a flag**, because they offer different
/// commands: `FR-1.9.2`'s resume and its repeat are not the same action with a different label, and
/// a screen deciding between them from a Boolean on one case would be able to draw neither.
///
/// No offline and no insufficient-data state: the sessions are local (`G-2.1`) and nothing on this
/// card is derived.
enum LastWorkoutScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// A workout is open. `FR-1.9.2`'s resume.
    case inProgress(LastWorkoutSummary)

    /// The most recent finished workout. `FR-1.9.2`'s repeat.
    case finished(LastWorkoutSummary)

    /// Nothing has ever been logged.
    case nothingLogged

    /// The sessions could not be read; a retry may work.
    case failed

    /// Which state a load is in. The failure outranks a card already on screen, on the tiles
    /// section's rule.
    ///
    /// - Parameter state: The card's load.
    /// - Returns: The state to draw.
    static func current(_ state: LastWorkoutState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded else { return .loading }
        guard let summary = state.summary else { return .nothingLogged }
        return summary.isInProgress ? .inProgress(summary) : .finished(summary)
    }
}

/// `FR-1.9.2`'s last-workout summary, with the action that applies to it.
struct LastWorkoutSection: View {
    /// The card's own state.
    @State private var state: LastWorkoutState

    /// The locale the exercise names in this section are resolved in (`FR-1.14.2`), handed to the
    /// state before its read.
    @Environment(\.locale) private var locale

    /// Starts a workout carrying `sessionID`'s exercises, reporting whether one is now in progress.
    ///
    /// **A closure the app target supplies**, for `ExerciseListView`'s reason: writing a session is
    /// `Logging`'s and `TR-1.3` keeps the feature packages off each other, so the target that owns
    /// both composes them.
    private let repeatSession: @MainActor (UUID) async -> Bool

    /// The shell's navigation position — this card's two commands are not `NavigationLink`s, because
    /// both land on the Train tab rather than on this one.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the card.
    ///
    /// - Parameters:
    ///   - workouts: The sessions and what is under them.
    ///   - catalogue: Where the exercise names come from.
    ///   - repeatSession: Starts a fresh workout holding a past one's exercises.
    init(
        workouts: any WorkoutRepository,
        catalogue: any ExerciseRepository,
        repeatSession: @escaping @MainActor (UUID) async -> Bool
    ) {
        self.repeatSession = repeatSession
        _state = State(initialValue: LastWorkoutState(workouts: workouts, catalogue: catalogue))
    }

    /// The card, and the read that fills it. Re-read on every appearance, which is what keeps it
    /// current across a tab switch: a workout started on Train is what this card reports next.
    var body: some View {
        LastWorkoutReading(
            state: LastWorkoutScreenState.current(state),
            hasFailedRepeat: state.repeatDidFail,
            retry: { Task { await state.load() } },
            resume: { navigation?.navigate(to: .training(.activeSession)) },
            repeatWorkout: { sessionID in
                Task {
                    let started = await repeatSession(sessionID)
                    state.repeatDidFinish(started: started)
                    guard started else { return }
                    await state.load()
                    navigation?.navigate(to: .training(.activeSession))
                }
            }
        )
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
    }
}

/// What the last-workout card draws, with no store behind it — `TR-1.12`'s renderable half.
struct LastWorkoutReading: View {
    /// Which of the five states to draw.
    let state: LastWorkoutScreenState

    /// Whether the last repeat could not be started.
    let hasFailedRepeat: Bool

    /// What the error state's retry does.
    let retry: () -> Void

    /// Opens the workout in progress.
    let resume: () -> Void

    /// Starts a fresh workout holding the given session's exercises.
    let repeatWorkout: (UUID) -> Void

    /// Which locale the day is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The heading, the state, and the failed repeat beneath it where there is one.
    var body: some View {
        GroupedSection(Text(DashboardStrings.lastWorkoutTitle)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .nothingLogged:
                EmptyStateView(
                    symbolName: "figure.strengthtraining.traditional",
                    headline: Text(DashboardStrings.lastWorkoutNone),
                    message: Text(DashboardStrings.lastWorkoutNoneMessage))
            case .failed:
                ErrorStateView(message: Text(DashboardStrings.lastWorkoutError), retry: retry)
            case .inProgress(let summary):
                facts(summary, isInProgress: true)
                command(Text(DashboardStrings.lastWorkoutResume), action: resume)
            case .finished(let summary):
                facts(summary, isInProgress: false)
                command(Text(DashboardStrings.lastWorkoutRepeat)) { repeatWorkout(summary.sessionID) }
            }
            if hasFailedRepeat {
                // No retry closure: nothing was written, so trying again is the same button above.
                ErrorStateView(message: Text(DashboardStrings.lastWorkoutRepeatError))
            }
        }
    }

    /// The day, what was trained, and how much of it — the three facts `FR-1.9.2` calls a summary.
    ///
    /// A workout still open says so in place of its set count: a running total presented as a
    /// finished one is the reading a card like this invites.
    @ViewBuilder private func facts(
        _ summary: LastWorkoutSummary, isInProgress: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(summary.date, format: AppFormat.date(locale: locale))
                .font(Typography.cardTitle.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(
                isInProgress
                    ? DashboardStrings.lastWorkoutState(summary.lifecycle)
                    : DashboardStrings.lastWorkoutSets(summary.workingSetCount)
            )
            .font(Typography.metricLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
            if !summary.exerciseNames.isEmpty {
                Text(verbatim: AppFormat.list(summary.exerciseNames, locale: locale))
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// One of the card's two commands, as a full-width row.
    private func command(_ label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .font(Typography.actionLabel.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                .background(
                    ColorToken.surfaceRaised,
                    in: .rect(cornerRadius: CornerRadius.control.points)
                )
        }
        .buttonStyle(.plain)
    }
}
