import AppNavigation
import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

/// Train's root: the workout in progress, or the way into one (`FR-1.2.1`, `FR-1.2.11`,
/// `FR-1.13.2`).
///
/// **This screen is the tab's root rather than a pushed destination**, which is what makes the
/// dashboard's "Start workout" (`FR-1.9.4`) land on a workout: that action selects this tab and pops
/// it to its root, so whatever the root is, is what the app's primary action arrives at. The
/// exercise library is a place the user goes *from* here.
///
/// **It reads ``ActiveSessionStore`` rather than owning state of its own**, because the workout in
/// progress outlives this screen — the pushed session, the exercise picker above that, and this root
/// underneath all show the same one. What is local here is the day the user is choosing and has not
/// started on: that belongs to nobody once the screen is gone.
///
/// A `ScrollView` and sections rather than a `List`, for the reason the exercise library's screens
/// give: `TR-1.12`'s harness renders through `ImageRenderer`, which draws a placeholder for anything
/// UIKit-backed.
public struct TrainingHomeView: View {
    private let store: ActiveSessionStore

    /// The shell's navigation position, for the two commands here that are not `NavigationLink`s.
    ///
    /// Optional and read rather than required, for `ExerciseListView`'s reason: a `StateAction` is a
    /// closure, and a preview or a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Whether the failure the store is carrying, if any, came from this screen's start command.
    ///
    /// **The store has one ``ActiveSessionStore/failure`` and this screen issues two kinds of
    /// operation**, so which one is being reported is the screen's own knowledge: it is the thing
    /// that asked. Cleared by every fresh read, so a write failure can never be re-attributed to a
    /// read that happened later.
    @State private var startWasAttempted = false

    /// Which training day a workout started from here would belong to (`FR-1.2.1`).
    ///
    /// Today until the user says otherwise, and reset by nothing: a day chosen and not started on is
    /// discarded with the screen, which is the right lifetime for a choice the store never saw.
    @State private var day = Date.now

    /// The program in force, and the two commands that move it (`FR-16.8.2`, `FR-16.8.4`).
    ///
    /// **Screen-lifetime, unlike ``store``**, which is `TR-1.2`'s split doing its own work: the
    /// workout in progress outlives every screen that shows it, where the program's next day is one
    /// screen's read of three tables and is re-read on every appearance.
    @State private var program: ProgramNextUpState

    /// Builds the screen over the store it reads and the repositories the program is assembled
    /// from.
    ///
    /// - Parameters:
    ///   - store: The workout in progress. One per app, built where the repositories are.
    ///   - programs: The programs, their days and the run in force (`FR-16.8`).
    ///   - routines: The routines those days name — also where **Start next week** writes.
    ///   - workouts: The sessions **Start next week** reads back (`FR-16.8.4`).
    public init(
        store: ActiveSessionStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository
    ) {
        self.store = store
        _program = State(
            initialValue: ProgramNextUpState(
                programs: programs, routines: routines, workouts: workouts))
    }

    /// Whichever of the screen's four states is current, then the two things that are true in all of
    /// them.
    ///
    /// `.task` calls ``ActiveSessionStore/resume()`` — which is `FR-1.2.11`'s whole mechanism: the
    /// app comes back, the root appears, and a workout left unfinished is found and held before
    /// anything offers to start another one.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                nextUp
                content
                libraryLink
                routinesLink
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .task {
            // Before the read, not after: a fresh read retires whatever the last start said, so the
            // failure it may leave behind is attributed to the read that produced it.
            startWasAttempted = false
            await store.resume()
            // After the resume, not beside it: the card is drawn only where no workout is in
            // progress, and a read racing that answer would draw it over one.
            await program.load()
        }
    }

    /// `FR-16.8.2`'s Next-up card, where a program is in force and nothing is being logged.
    ///
    /// **Suppressed while a workout is in progress**, which is the whole of the condition: the
    /// screen already says what is being logged, and a second **Start** beside it would offer a
    /// workout the store would refuse. Suppressed before the store has answered for the same
    /// reason — see ``TrainingHomeState/loading``.
    @ViewBuilder private var nextUp: some View {
        if store.hasCheckedForSession, store.session == nil {
            ProgramNextUpSection(
                state: program,
                advanceFailure: store.programAdvanceFailure,
                start: startProgramDay)
        }
    }

    /// Starts the program's next day and opens it (`FR-16.8.2`, `FR-16.8.3`, `NFR-15.3`).
    ///
    /// **The day the workout belongs to is the one this screen is offering**, not `.now`: a lifter
    /// logging Saturday's session on Sunday backdates it here exactly as they would an unplanned
    /// one, and the program's day index is a position in the week rather than a date.
    ///
    /// The push happens only when the store took a workout, on ``startWorkout()``'s rule.
    ///
    /// - Parameters:
    ///   - index: The `ProgramDay.order` being started.
    ///   - routineID: The routine that day names.
    private func startProgramDay(at index: Int, fromRoutineID routineID: UUID) {
        guard let nextUp = program.nextUp else { return }
        Task {
            startWasAttempted = true
            let started = await store.start(
                on: day,
                in: ProgramSessionStamp(
                    runID: nextUp.runID, weekNumber: nextUp.weekNumber, dayIndex: index),
                fromRoutineID: routineID,
                using: program.routines)
            guard started, store.isActive else { return }
            startWasAttempted = false
            navigation?.navigate(to: .training(.activeSession))
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **The failed read takes the whole screen rather than sitting beside the start control**,
    /// which is the opposite of the rule a failed *write* follows elsewhere. The difference is what
    /// is left to show: a screen whose notes save failed still has its exercise, where this one does
    /// not know whether a workout is in progress — and offering to start a second one on top of a
    /// session it failed to read is the one outcome worth ruling out.
    ///
    /// **No offline state**, for the reason every other Phase 1 screen gives: the store is local, so
    /// there is no fetch to be offline for (`G-2.1`). No insufficient-data state — nothing here is
    /// derived.
    @ViewBuilder private var content: some View {
        switch TrainingHomeState.current(
            hasChecked: store.hasCheckedForSession,
            session: store.session,
            failure: store.failure,
            startWasAttempted: startWasAttempted
        ) {
        case .loading:
            LoadingStateView()
        case .inProgress(let session):
            SessionInProgressSection(session: session)
        case .readFailed:
            ErrorStateView(
                headline: Text(LoggingStrings.trainErrorHeadline),
                message: Text(LoggingStrings.trainErrorMessage),
                retry: { Task { await store.resume() } }
            )
        case .start(let showingStartFailure):
            start(showingStartFailure: showingStartFailure)
        }
    }

    /// Nothing in progress: `FR-1.13.2`'s empty state, and the date the next workout would carry.
    ///
    /// **The empty state carries the command and the date control sits under it**, in that order
    /// deliberately. A first-launch user taps the action and gets today, which is the case
    /// `FR-1.13.2` is about; a user logging Saturday's workout on Sunday sets the day first and then
    /// taps the same button. Putting the picker first would make every first workout a form.
    ///
    /// **A start that could not be written renders between the two**, on the exercise library's rule
    /// for a failed write: it is not a phase, it costs the screen nothing, and it sits beside the
    /// command that issued it so the retry is another tap at the same button. Taking the whole
    /// screen for it — and saying the workouts could not be *read* — would lose both the date the
    /// user picked and the command they were reaching for.
    ///
    /// - Parameter showingStartFailure: Whether the last start failed and has not been retired.
    /// - Returns: The empty state, the failure where there is one, and the date control.
    @ViewBuilder private func start(showingStartFailure: Bool) -> some View {
        EmptyStateView(
            symbolName: "figure.strengthtraining.traditional",
            headline: Text(LoggingStrings.trainEmptyHeadline),
            message: Text(LoggingStrings.trainEmptyMessage),
            action: StateAction(
                Text(LoggingStrings.trainStartAction),
                // FR-16.6.4: one filled accent per screen. Where the program's card is offering a
                // day, that is the screen's primary action and this is the way past it.
                emphasis: program.nextUp?.spendsAccent == true ? .secondary : .primary
            ) {
                Task { await startWorkout() }
            }
        )
        if showingStartFailure {
            ErrorStateView(message: Text(LoggingStrings.trainStartErrorMessage))
        }
        WorkoutDateSection(day: $day)
    }

    /// Starts the workout and opens it.
    ///
    /// The push happens only when the store took one: a failed write leaves the screen where it is,
    /// with the failure beside the start command rather than an empty workout on top.
    private func startWorkout() async {
        startWasAttempted = true
        await store.start(on: day)
        guard store.isActive else { return }
        startWasAttempted = false
        navigation?.navigate(to: .training(.activeSession))
    }

    /// The way into the routines (`FR-15.2.1`).
    ///
    /// **A card beside the library's rather than a tab of its own**, `D-8` having fixed the four:
    /// a routine is a plan for a training day, so the place it is reached from is the screen a
    /// training day starts on. It is a `NavigationLink` on a `Route` this module does not own,
    /// which costs nothing — the route enum is shared and the destination is the app target's.
    private var routinesLink: some View {
        DestinationCard(
            label: LoggingStrings.trainRoutinesAction, value: .routines(.routineList))
    }

    /// The way into the exercise library (`FR-1.1.1`).
    ///
    /// The library's real entry point, and the reason the shell's placeholder link could go: it was
    /// pointed here so the built screen was reachable at all before this screen existed.
    private var libraryLink: some View {
        DestinationCard(
            label: LoggingStrings.trainLibraryAction, value: .exerciseLibrary(.exerciseList))
    }
}

/// A card that pushes one route — the shape both of this screen's two way-out links take.
///
/// Extracted when the second arrived: the two differ in a string and a route, and a second copy of
/// the chrome is a second place to forget a Dynamic Type or accessibility change.
struct DestinationCard: View {
    /// What the card says, which is also what VoiceOver reads.
    let label: LocalizedStringResource

    /// Where it goes.
    let value: Route

    var body: some View {
        NavigationLink(value: value) {
            Card {
                HStack(spacing: Spacing.sm.points) {
                    Text(label)
                        .font(Typography.actionLabel.font)
                        .foregroundStyle(ColorToken.textPrimary)
                    Spacer(minLength: Spacing.sm.points)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(ColorToken.textTertiary)
                        // The chevron says "pushes"; the label already says where to (`G-4.2`).
                        .accessibilityHidden(true)
                }
                .frame(minHeight: TouchTarget.standard.points)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Which of the root's four states is current (`FR-1.13.1`).
///
/// **A value rather than a chain of `if`s, so the decision can be tested.** `TR-1.12`'s harness
/// renders through `ImageRenderer`, which cannot run the `.task` that fills the store — so a
/// reference over this screen is a reference over an empty one, and *which* state a user is shown
/// would otherwise be covered by nothing. It is the part worth covering: two of the four differ only
/// in which failure they are describing.
enum TrainingHomeState: Equatable {
    /// Nothing has looked for a workout yet.
    case loading

    /// A workout is in progress.
    case inProgress(WorkoutSession)

    /// The read failed, so whether a workout is in progress is not known.
    case readFailed

    /// Nothing is in progress, with `showingStartFailure` when the last start could not be written.
    case start(showingStartFailure: Bool)

    /// The state to render.
    ///
    /// **A held workout outranks a failure**, because a failed *write* costs this screen nothing:
    /// the workout is still there and still rendered.
    ///
    /// **A failure outranks the empty state only when it belongs to a read.** The store carries one
    /// diagnostic for both kinds of operation, so a start that could not be written would otherwise
    /// claim the workouts are unreadable — and offer a retry that re-reads instead of re-starting,
    /// which on success would quietly retire the failure and forget the workout the user asked for.
    ///
    /// - Parameters:
    ///   - hasChecked: ``ActiveSessionStore/hasCheckedForSession``.
    ///   - session: ``ActiveSessionStore/session``.
    ///   - failure: ``ActiveSessionStore/failure``.
    ///   - startWasAttempted: Whether a failure, if there is one, came from this screen's start.
    /// - Returns: The current state.
    static func current(
        hasChecked: Bool,
        session: WorkoutSession?,
        failure: String?,
        startWasAttempted: Bool
    ) -> Self {
        if !hasChecked { return .loading }
        if let session { return .inProgress(session) }
        if failure != nil, !startWasAttempted { return .readFailed }
        return .start(showingStartFailure: failure != nil)
    }
}

/// The workout in progress, as the root shows it (`FR-1.2.11`).
///
/// Taking the record rather than the store, for the reason `ExerciseFactsSection` does in the
/// library: this is what the snapshot renders, and a reference over the whole screen would be a
/// reference over a `.task` that reads a store.
struct SessionInProgressSection: View {
    /// The workout being logged.
    let session: WorkoutSession

    /// Which locale the day and the time are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The day, when it was started, and the way back in.
    var body: some View {
        GroupedSection(Text(LoggingStrings.trainInProgressSection)) {
            SessionFactRow(
                label: LoggingStrings.trainInProgressDay,
                value: Text(session.date, format: AppFormat.date(locale: locale))
            )
            if let startedAt = session.startedAt {
                SessionFactRow(
                    label: LoggingStrings.trainInProgressStarted,
                    value: Text(startedAt, format: AppFormat.dateAndTime(locale: locale))
                )
            }
            NavigationLink(value: Route.training(.activeSession)) {
                Text(LoggingStrings.trainInProgressResume)
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
}

/// Which training day the next workout belongs to — `FR-1.2.1`'s backdating.
struct WorkoutDateSection: View {
    /// The day the screen is offering to start on.
    @Binding var day: Date

    /// The picker and the sentence that says what the date is for.
    ///
    /// **Days only, and no future ones.** `FR-1.2.1` is "today, or backdate to any past date": a
    /// time of day would be a second thing to get right for a value that is a day, and a workout
    /// dated next week is a workout nobody has done.
    var body: some View {
        GroupedSection(Text(LoggingStrings.trainDateSection)) {
            DatePicker(
                selection: $day,
                in: ...Date.now,
                displayedComponents: .date
            ) {
                Text(LoggingStrings.trainDatePicker)
                    .font(Typography.body.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            .tint(ColorToken.brandAccent)
            Text(LoggingStrings.trainDateHint)
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
    }
}

/// One fact about a workout: its name, then its value.
///
/// Side by side where both fit and stacked where they do not, and one VoiceOver element rather than
/// two (`G-4.2`, `NFR-1.10`) — the same shape the exercise library's fact row has, kept local
/// because a shared row is a `DesignSystem` component and neither screen has asked for one twice.
struct SessionFactRow: View {
    /// What the fact is called.
    let label: LocalizedStringResource

    /// This workout's value for it, built by the caller — a date renders through `AppFormat`, so it
    /// arrives already formatted for the locale rather than as copy.
    let value: Text

    /// The pair.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md.points) {
                name
                Spacer(minLength: Spacing.sm.points)
                reading
            }
            VStack(alignment: .leading, spacing: Spacing.xxs.points) {
                name
                reading
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The fact's name.
    private var name: some View {
        Text(label)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
    }

    /// The fact's value.
    private var reading: some View {
        value
            .font(Typography.body.font)
            .foregroundStyle(ColorToken.textPrimary)
    }
}
