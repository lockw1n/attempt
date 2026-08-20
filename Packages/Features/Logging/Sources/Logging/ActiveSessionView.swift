import AppNavigation
import DesignSystem
import Foundation
import Localization
import RepositoryInterface
import SwiftUI

/// The workout in progress (`FR-1.2.11`, `FR-1.2.12`).
///
/// **The workout, what is in it, and what is in one exercise.** Here are the workout's own facts —
/// the day it belongs to, when it started, the two ways it ends — `FR-1.2.13`'s vertical list of
/// exercise cards with `FR-1.2.2`'s add and reorder, and the sets logged inside a card
/// (`FR-1.2.3`, `FR-1.2.6`). Warmup marking, completion and editing land in that same card rather
/// than in a new shape beside it.
///
/// **It carries no identifier, and that is why ``ActiveSessionStore`` exists.** `TrainingRoute` has
/// no payload for this screen: the workout in progress is one fact about the app, not a parameter of
/// a push, so a restored navigation stack that opens straight onto this screen shows whichever
/// workout the store found — or says there is none, which is what a stack restored after the workout
/// was finished has to say.
public struct ActiveSessionView: View {
    private let store: ActiveSessionStore

    /// The way back to the root once the workout has ended, one way or the other.
    @Environment(\.dismiss) private var dismiss

    /// The shell's navigation position, for the one command here that is not a `NavigationLink`.
    ///
    /// Optional and read rather than required, for `TrainingHomeView`'s reason: a `StateAction` is a
    /// closure, and a preview or a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Whether `FR-1.2.12`'s confirmation is on screen.
    ///
    /// The screen's and not the store's: a dialogue the user has open is not a fact about the
    /// workout, and it must not survive the screen being left.
    @State private var isConfirmingDiscard = false

    /// Which cards the user has folded or unfolded by hand, keyed on the entry (`FR-1.2.13`).
    ///
    /// **Stored nowhere, deliberately.** `NFR-1.8` is about logged data surviving a force-quit, and
    /// which card is open is not logged data — a workout reopened tomorrow should follow the rule
    /// (finished exercises collapsed, the rest open) rather than the folds of an earlier sitting.
    /// An entry here is an override of that rule and lasts as long as the screen does.
    @State private var expansion: [UUID: Bool] = [:]

    /// Which exercise the set editor is open over, or `nil` (`FR-1.2.3`, `FR-1.2.6`).
    ///
    /// **The screen's, and it carries no route.** A half-filled set is not a place in the app: a
    /// restored navigation stack that reopened this sheet would offer to log a set the user was in
    /// the middle of abandoning when they force-quit, prefilled from a workout that may since have
    /// been discarded.
    @State private var editing: SetEditorTarget?

    /// Which locale the set editor parses and renders numbers in (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Builds the screen over the store that holds the workout.
    ///
    /// - Parameter store: The workout in progress. One per app, built where the repositories are.
    public init(store: ActiveSessionStore) {
        self.store = store
    }

    /// The workout, or whichever of the screen's other states is current.
    ///
    /// `.task` calls ``ActiveSessionStore/resume()`` for the restored-stack case: this screen can be
    /// the first thing the app draws, and it must not announce that there is no workout while the
    /// read that would find one has not run. The call is idempotent — a workout already held is kept
    /// and nothing is read.
    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: .leading, spacing: Spacing.xl.points) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.lg.points)
                } header: {
                    progressHeader
                }
            }
        }
        .background(ColorToken.background)
        .navigationTitle(Text(LoggingStrings.sessionTitle))
        .task {
            // The first two in this order: the exercises belong to whichever workout the resume
            // settled on, and reading them first would read them for the workout held before it.
            // The unit is independent of both and is re-read on every appearance — the preference
            // lives in another tab, and this screen is returned to rather than rebuilt.
            await store.resume()
            await store.loadExercises()
            await store.loadDisplayUnit()
        }
        .sheet(item: $editing) { target in
            SetEditorSheet(
                draft: draft(for: target),
                log: { log($0, into: target.entryID) },
                cancel: { editing = nil }
            )
            // The medium detent is what puts every logging control in the lower two-thirds
            // (`NFR-1.4`); the large one is there because at `accessibility3` the four fields no
            // longer fit the medium one.
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            Text(LoggingStrings.sessionDiscardConfirmTitle),
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await discard() }
            } label: {
                Text(LoggingStrings.sessionDiscardConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.sessionDiscardConfirmCancel)
            }
        } message: {
            Text(LoggingStrings.sessionDiscardConfirmMessage)
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **"No workout in progress" is an error state without a retry**, on the exercise detail
    /// screen's precedent for an identifier that resolves to nothing: reading again resolves to the
    /// same absence, so a retry would be a button that re-answers the same way. It is not an empty
    /// state either — the empty one below belongs to a workout that exists and has nothing in it,
    /// and rendering "no exercises yet" for a workout that is gone would offer to log into nothing.
    ///
    /// **A read that failed is a different state and says a different thing**, with a retry. The two
    /// are the same absence to this screen and opposite facts to the user: one says the workout is
    /// gone, the other says we could not tell. This screen can be the first thing the app draws, so
    /// a transient read failure would otherwise report a workout still in progress as finished or
    /// discarded — and offer no way to ask again.
    ///
    /// No offline and no insufficient-data state, for `TrainingHomeView`'s reasons.
    @ViewBuilder private var content: some View {
        switch ActiveSessionState.current(
            hasChecked: store.hasCheckedForSession,
            session: store.session,
            failure: store.failure
        ) {
        case .loading:
            LoadingStateView()
        case .inProgress(let session, let writeFailed):
            loaded(session, writeFailed: writeFailed)
        case .readFailed:
            ErrorStateView(
                headline: Text(LoggingStrings.sessionErrorHeadline),
                message: Text(LoggingStrings.sessionErrorMessage),
                retry: {
                    Task {
                        // Both, and for the `.task` above's reason: `resume()` drops the exercise
                        // list along with the workout it belonged to, so a retry that re-read only
                        // the workout would leave the cards on a loading state nothing clears —
                        // this screen's `.task` has already run and does not run again.
                        await store.resume()
                        await store.loadExercises()
                    }
                }
            )
        case .ended:
            ErrorStateView(
                headline: Text(LoggingStrings.sessionEndedHeadline),
                message: Text(LoggingStrings.sessionEndedMessage)
            )
        }
    }

    /// A workout that is in progress: what it is, what is in it, and the two ways out.
    ///
    /// - Parameters:
    ///   - session: The workout being logged.
    ///   - writeFailed: Whether the last command against it failed. A workout is held, so the
    ///     failure can only have come from a write — it renders beside the commands.
    /// - Returns: The workout, in full.
    @ViewBuilder private func loaded(_ session: WorkoutSession, writeFailed: Bool) -> some View {
        SessionSummarySection(session: session)
        exercises
        SessionCommandsSection(
            hasFailed: writeFailed,
            finish: { Task { await finish() } },
            discard: { isConfirmingDiscard = true }
        )
    }

    /// The workout's exercises, or whichever of that list's own four states is current
    /// (`FR-1.2.2`, `FR-1.2.13`).
    ///
    /// **Four more states on a screen that already had four**, and they are the exercises' rather
    /// than the workout's: the workout can be on screen while its contents are not, which is exactly
    /// what a failed second read produces. The two sets never overlap — this whole section renders
    /// only inside the workout's own loaded state.
    @ViewBuilder private var exercises: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            // A heading over the cards rather than a `GroupedSection`, which is the one place this
            // screen does not reuse that component: a grouped section puts its content ON a card,
            // and `FR-1.2.13`'s exercises ARE cards — nested, the two surfaces are the same colour
            // and the list reads as one undivided block. Measured in the simulator.
            Text(LoggingStrings.sessionExercisesSection)
                .font(Typography.sectionHeading.font)
                .foregroundStyle(ColorToken.textPrimary)
            switch SessionExercisesState.current(
                hasLoaded: store.hasLoadedExercises,
                exercises: store.exercises,
                readFailure: store.exercisesReadFailure,
                writeFailure: store.exercisesWriteFailure
            ) {
            case .loading:
                LoadingStateView()
            case .empty(let writeFailed):
                EmptyStateView(
                    symbolName: "list.bullet.rectangle",
                    headline: Text(LoggingStrings.sessionEmptyHeadline),
                    message: Text(LoggingStrings.sessionEmptyMessage),
                    action: StateAction(Text(LoggingStrings.sessionAddExerciseAction)) {
                        navigation?.navigate(to: .exerciseLibrary(.exercisePicker))
                    }
                )
                writeFailure(writeFailed)
            case .listed(let items, let writeFailed):
                SessionExerciseList(
                    exercises: items,
                    expansion: $expansion,
                    move: { id, offset in
                        Task { await store.moveExercise(id: id, by: offset) }
                    },
                    unit: store.displayUnit,
                    logSet: { editing = $0 }
                )
                writeFailure(writeFailed)
                addExerciseLink
            case .readFailed:
                ErrorStateView(
                    headline: Text(LoggingStrings.sessionExercisesErrorHeadline),
                    message: Text(LoggingStrings.sessionExercisesErrorMessage),
                    retry: { Task { await store.loadExercises() } }
                )
            }
        }
    }

    /// A failed add or reorder, where there was one.
    ///
    /// Not a phase: the cards are unchanged, so it renders beneath them and the retry is the command
    /// the user reached for.
    @ViewBuilder private func writeFailure(_ hasFailed: Bool) -> some View {
        if hasFailed {
            ErrorStateView(message: Text(LoggingStrings.sessionExercisesWriteErrorMessage))
        }
    }

    /// The way into `FR-1.2.2`'s chooser, under the cards.
    ///
    /// **Under them rather than in the toolbar**, because `FR-1.2.13` appends: the command sits at
    /// the end of the list for the same reason the exercise lands there.
    private var addExerciseLink: some View {
        NavigationLink(value: Route.exerciseLibrary(.exercisePicker)) {
            Text(LoggingStrings.sessionAddExerciseAction)
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

    /// `FR-1.2.13`'s session progress, pinned above the scrolling cards.
    ///
    /// **A pinned section header, which is the requirement's actual claim.** "Visible without
    /// scrolling horizontally" bans a pager; a header that scrolled away would satisfy the letter of
    /// that and lose the fact at the exercise count where it matters — six or eight cards, which is
    /// a normal session and more than one screen. Pinned inside the scroll view rather than inset
    /// above it, because a `safeAreaInset` at the top displaces the navigation bar's own title:
    /// measured in the simulator, where the screen lost its name to it.
    ///
    /// It is drawn only while a workout is being logged and has something in it: over an empty
    /// workout it would say "0 of 0".
    @ViewBuilder private var progressHeader: some View {
        if store.isActive, !store.exercises.isEmpty {
            SessionProgressHeader(progress: store.progress)
        }
    }

    /// The draft the editor opens holding — blank, or `FR-1.2.6`'s copy of the last set.
    ///
    /// - Parameter target: Which exercise the editor is open over.
    /// - Returns: The draft.
    private func draft(for target: SetEditorTarget) -> SetDraft {
        guard let repeated = target.repeating else {
            return SetDraft(unit: store.displayUnit, locale: locale)
        }
        return SetDraft(repeating: repeated, unit: store.displayUnit, locale: locale)
    }

    /// Logs the drafted set and closes the editor (`FR-1.2.3`, `NFR-1.8`).
    ///
    /// **The sheet closes before the write is awaited**, which is what `NFR-1.2` is asking for: the
    /// row appears as the store publishes it, with no spinner and nothing between the tap and the
    /// card. The write is local (`G-2.3`), so there is no window in which the card is visibly behind.
    ///
    /// **The card is pinned open.** Every set logged here is `isCompleted`, so the first one makes
    /// the exercise complete by `FR-1.2.13`'s rule — and the rule collapses completed cards, which
    /// would fold the card the user is logging into at the moment they log into it. An explicit
    /// entry in the fold overrides that for this card only: one the user has not touched still
    /// follows the rule, which is what a workout reopened tomorrow should do.
    ///
    /// A draft that does not resolve is ignored rather than trusted — the confirming command is
    /// disabled in that state, so this is the second reading of a guard the editor already applies.
    ///
    /// - Parameters:
    ///   - draft: What the user entered.
    ///   - entryID: The exercise to log against.
    private func log(_ draft: SetDraft, into entryID: UUID) {
        guard let weight = draft.weight, let reps = draft.reps, draft.isLoggable else { return }
        let rpe = draft.storedRPE
        let notes = draft.notes
        editing = nil
        expansion[entryID] = true
        Task {
            await store.addSet(
                toEntryID: entryID, weight: weight, reps: reps, rpe: rpe, notes: notes)
        }
    }

    /// Finishes the workout and leaves the screen, unless the write failed.
    ///
    /// The screen stays open on a failure, with the workout still on it: nothing was stored, so the
    /// retry is another tap at the same command rather than a workout the user has to find again.
    private func finish() async {
        await store.finish()
        guard !store.isActive else { return }
        dismiss()
    }

    /// Discards the workout and leaves the screen, unless the write failed. See ``finish()``.
    private func discard() async {
        await store.discard()
        guard !store.isActive else { return }
        dismiss()
    }
}

/// Which of the pushed screen's four states is current (`FR-1.13.1`).
///
/// A value rather than a chain of `if`s, for ``TrainingHomeState``'s reason.
enum ActiveSessionState: Equatable {
    /// Nothing has looked for a workout yet.
    case loading

    /// The workout, and whether the last command against it failed.
    case inProgress(WorkoutSession, writeFailed: Bool)

    /// The read failed, so whether the workout is still in progress is not known.
    case readFailed

    /// There is no workout: it was finished or discarded.
    case ended

    /// The state to render.
    ///
    /// **A held workout outranks a failure**, and while one is held the failure can only be a
    /// write's — the screen keeps the workout and renders the failure beside the commands.
    ///
    /// **With no workout held, a failure is a read's, and it is not the same fact as "ended".** The
    /// store answers both with a `nil` session; reporting the first as the second tells a user
    /// whose workout is still in progress that it has been finished or discarded, and leaves them
    /// nothing to retry.
    ///
    /// - Parameters:
    ///   - hasChecked: ``ActiveSessionStore/hasCheckedForSession``.
    ///   - session: ``ActiveSessionStore/session``.
    ///   - failure: ``ActiveSessionStore/failure``.
    /// - Returns: The current state.
    static func current(hasChecked: Bool, session: WorkoutSession?, failure: String?) -> Self {
        if !hasChecked { return .loading }
        if let session { return .inProgress(session, writeFailed: failure != nil) }
        if failure != nil { return .readFailed }
        return .ended
    }
}

/// The workout's own facts.
///
/// Taking the record rather than the store, for `SessionInProgressSection`'s reason.
struct SessionSummarySection: View {
    /// The workout being logged.
    let session: WorkoutSession

    /// Which locale the day and the time are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The training day, and when the workout was started.
    var body: some View {
        GroupedSection(Text(LoggingStrings.sessionSummarySection)) {
            SessionFactRow(
                label: LoggingStrings.sessionDay,
                value: Text(session.date, format: AppFormat.date(locale: locale))
            )
            if let startedAt = session.startedAt {
                SessionFactRow(
                    label: LoggingStrings.sessionStarted,
                    value: Text(startedAt, format: AppFormat.dateAndTime(locale: locale))
                )
            }
        }
    }
}

/// The two ways a workout ends (`FR-1.2.11`, `FR-1.2.12`).
///
/// Taking closures rather than the store, so both commands are picturable without one behind them.
///
/// **Finish is the primary action and discard is not styled as one.** They are not two options: one
/// keeps the workout and one throws it away, and a pair of matching buttons is how the second gets
/// tapped by accident. `FR-1.2.12`'s confirmation is the other half of that, and it is the caller's.
struct SessionCommandsSection: View {
    /// Whether the last write failed. The workout is unchanged when it did, so both commands still
    /// ask for the same thing and the retry is the same tap.
    let hasFailed: Bool

    /// Ends the workout and keeps it.
    let finish: () -> Void

    /// Asks whether to throw it away.
    let discard: () -> Void

    /// Both commands, and a failed write beneath them.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            Button(action: finish) {
                Text(LoggingStrings.sessionFinishAction)
            }
            .buttonStyle(.primaryAction(.fill))

            Button(action: discard) {
                Text(LoggingStrings.sessionDiscardAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.negative)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            }
            .buttonStyle(.plain)

            if hasFailed {
                // The shared error component rather than a local label, and the workout stays on
                // screen beside it — a failed write costs this screen nothing.
                ErrorStateView(message: Text(LoggingStrings.sessionWriteErrorMessage))
            }
        }
    }
}
