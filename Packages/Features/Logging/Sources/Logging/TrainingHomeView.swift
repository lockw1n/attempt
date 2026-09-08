import AppNavigation
import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

/// Train's root: **this week** (`FR-17.8.1`, `D-17.5`).
///
/// **The root is the plan, not the session.** A lifter opens this tab to see what is left of the
/// week and to tick one exercise off; the workout is a thing the day owns. That is the whole of
/// `D-17.5` and the reason the Next-up card, Start workout, the date picker, Resume, Skip day,
/// Browse exercises and the Routines card are gone from here (`FR-17.8.7`).
///
/// **It reads ``ActiveSessionStore`` for one fact only** — whether a free workout is open — which
/// is `FR-17.8.3`'s card. Everything else on the screen is ``WeekState``'s, because a week outlives
/// no screen and a workout in progress outlives every one.
///
/// A `ScrollView` and sections rather than a `List`, for the reason the exercise library's screens
/// give: `TR-1.12`'s harness renders through `ImageRenderer`, which draws a placeholder for anything
/// UIKit-backed.
public struct TrainingHomeView: View {
    private let store: ActiveSessionStore

    /// The week — the program in force, its days and what has been logged into them.
    ///
    /// **Screen-lifetime**, which is `TR-1.2`'s split doing its own work: the week is one screen's
    /// read of five tables and is re-read on every appearance, where the workout being logged is
    /// the app's.
    @State private var week: WeekState

    /// Builds the screen over the store it reads and the repositories the week is assembled from.
    ///
    /// - Parameters:
    ///   - store: The workout in progress. One per app, built where the repositories are.
    ///   - programs: The programs, their days and the run in force (`FR-16.8`).
    ///   - routines: The routines those days name.
    ///   - workouts: The sessions the week's state is read from (`TR-17.5`).
    ///   - exercises: The catalogue the plan's slots name.
    public init(
        store: ActiveSessionStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository
    ) {
        self.store = store
        _week = State(
            initialValue: WeekState(
                programs: programs, routines: routines, workouts: workouts, exercises: exercises))
    }

    /// The week, whichever state it is in, with the commands that are true in all of them.
    ///
    /// `.task` resumes first and reads second, which is `FR-1.2.11`'s mechanism as this screen now
    /// uses it: the store finds the workout left unfinished, and the week is then told whether one
    /// of them is a free workout it owes a card.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                content
                freeWorkout
                freeWorkoutCommand
                if startWasAttempted, store.failure != nil {
                    // Beside the command that issued it, on the retired root's rule for a failed
                    // *write*: it costs the screen nothing, and the retry is another tap at the
                    // same button.
                    ErrorStateView(message: Text(LoggingStrings.trainStartErrorMessage))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .toolbar { commands }
        .task {
            // Before the read, not after: a fresh read retires whatever the last command said.
            startWasAttempted = false
            await store.resume()
            // The unit is re-read on every appearance for ``ActiveSessionStore/loadDisplayUnit()``'s
            // reason: the preference is changed in a different tab.
            await store.loadDisplayUnit()
            await week.load(openSession: store.session)
        }
    }

    /// The week's own commands, in a menu rather than on the screen (`FR-17.8.3`, `Q-17.7`).
    ///
    /// **Edit week and the library are both rare and deliberate**, which is what a toolbar menu is
    /// for: one is opened when the plan changes, the other when a lift is renamed or invented. The
    /// screen's own accent is spent on a day (`FR-16.6.4`), and neither of these takes it.
    @ToolbarContentBuilder private var commands: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                NavigationLink(value: Route.routines(.editWeek)) {
                    Text(LoggingStrings.weekEditAction)
                }
                NavigationLink(value: Route.exerciseLibrary(.exerciseList)) {
                    Text(LoggingStrings.weekLibraryAction)
                }
            } label: {
                Label(String(localized: LoggingStrings.weekEditAction), systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state**, for the reason every other Phase 1 screen gives: the store is local, so
    /// there is no fetch to be offline for (`G-2.1`). No insufficient-data state — nothing here is
    /// derived.
    @ViewBuilder private var content: some View {
        switch week.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(LoggingStrings.weekErrorHeadline),
                message: Text(LoggingStrings.weekErrorMessage),
                // The screen's accent: nothing else is offering anything, so the retry is the one
                // thing to do (`FR-16.6.4`).
                retryEmphasis: .primary,
                retry: { Task { await week.load(openSession: store.session) } }
            )
        case .ready:
            switch week.reading {
            case .empty:
                empty
            case .week(let runID, let programName, let weekNumber, let days):
                WeekSection(
                    runID: runID,
                    programName: programName,
                    weekNumber: weekNumber,
                    days: days,
                    unit: store.displayUnit)
            }
        }
    }

    /// `FR-17.8.5`'s root for a lifter running no program, which is also `FR-1.13.2`'s first launch.
    ///
    /// **One action, and it is the plan.** Free workout sits under it as the screen's own second
    /// command rather than inside the state, so a lifter who wants to log something now is one tap
    /// from it without the empty state offering two primaries.
    private var empty: some View {
        EmptyStateView(
            symbolName: "calendar",
            headline: Text(LoggingStrings.weekEmptyHeadline),
            message: Text(LoggingStrings.weekEmptyMessage),
            action: StateAction(Text(LoggingStrings.weekPlanAction), emphasis: .primary) {
                navigation?.navigate(to: .routines(.editWeek))
            }
        )
    }

    /// The free workout in progress, as a card after the plan's days (`FR-17.8.3`, `Q-17.5`).
    @ViewBuilder private var freeWorkout: some View {
        if let card = week.freeWorkout {
            FreeWorkoutSection(card: card)
        }
    }

    /// The way into a workout no program planned (`FR-17.8.3`).
    ///
    /// **At the foot, and `.secondary` whatever else is on screen.** The week is what the lifter
    /// came for; an unplanned workout is the exception, and `T-17.13`'s **Start next week** card
    /// arrives below this one.
    private var freeWorkoutCommand: some View {
        Button {
            Task { await startFreeWorkout() }
        } label: {
            Text(LoggingStrings.weekFreeWorkoutAction)
        }
        .buttonStyle(.secondaryAction(.fill))
        // A second Free workout while one is open would ask the store for a workout it refuses;
        // the card above is the way back into that one.
        .disabled(week.freeWorkout != nil)
    }

    /// The shell's navigation position, for the two commands here that are not `NavigationLink`s.
    ///
    /// Optional and read rather than required, for `ExerciseListView`'s reason: a `StateAction` is
    /// a closure, and a preview or a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Whether the failure the store is carrying, if any, came from this screen's own command.
    ///
    /// The store has one ``ActiveSessionStore/failure`` and this screen issues two kinds of
    /// operation, so which one is being reported is the screen's own knowledge.
    @State private var startWasAttempted = false

    /// Starts a workout for today outside the plan, and opens it (`FR-17.8.3`).
    ///
    /// The push happens only when the store took one, on the rule the retired start had: a failed
    /// write leaves the screen where it is rather than an empty workout on top of it.
    private func startFreeWorkout() async {
        startWasAttempted = true
        await store.start(on: .now)
        guard store.isActive else { return }
        startWasAttempted = false
        navigation?.navigate(to: .training(.activeSession))
    }
}
