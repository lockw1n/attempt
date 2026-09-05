import AppNavigation
import DerivedValues
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
/// (`FR-1.2.3`, `FR-1.2.4`, `FR-1.2.6`, `FR-1.2.14`). Completion and editing land in that same
/// card rather than in a new shape beside it.
///
/// **What this screen does to a *set* is in `ActiveSessionSetEditing.swift`**, which is why the
/// state below is internal rather than file-scoped: `private` is file-scoped and this type is two
/// files, the same split — and for the same reason — as the store's own commands.
///
/// **It carries no identifier, and that is why ``ActiveSessionStore`` exists.** `TrainingRoute` has
/// no payload for this screen: the workout in progress is one fact about the app, not a parameter of
/// a push, so a restored navigation stack that opens straight onto this screen shows whichever
/// workout the store found — or says there is none, which is what a stack restored after the workout
/// was finished has to say.
public struct ActiveSessionView: View {
    let store: ActiveSessionStore

    /// The modifier terms the set editor offers (`FR-1.2.8`).
    ///
    /// **Held here rather than made with the sheet**, on `TR-1.2`'s rule: the list outlives every
    /// screen that shows it — the picker, the list editor, and History's own editor when T-1.35
    /// reaches it — and a copy made per sheet would not see a term added in the last one.
    let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on.
    ///
    /// **Held here for ``vocabulary``'s reason** (`TR-1.2`): which gym is active outlives the sheet
    /// the calculator is presented from, and T-1.31 edits it in another tab.
    let equipment: PlateCalculatorStore

    /// The way back to the root once the workout has ended, one way or the other.
    @Environment(\.dismiss) var dismiss

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

    /// Whether `FR-16.4.4`'s question is open — the workout holds sets nobody attempted, and Finish
    /// has been tapped.
    ///
    /// Internal rather than private because the command that opens it lives in
    /// `ActiveSessionViewCommands.swift`; nothing outside `Logging` can reach it.
    ///
    /// **Held here rather than derived from the store**, on ``isConfirmingDiscard``'s rule: a
    /// confirmation that is open is the screen's business, and a workout with pending sets in it is
    /// a normal thing to be looking at without being asked about them.
    @State var isResolvingPendingSets = false

    /// How many sets the workout still holds that nobody has attempted.
    ///
    /// **The store's own count, from the read that refused to finish** — not a projection of the
    /// cards on screen, which would be a second answer to the question the alert is asking. It is
    /// set by the tap that opened the question and cleared by the answer, so the number in the
    /// title is always the one the resolution will act on.
    var pendingSetCount: Int { store.pendingSetCount }

    /// Which cards the user has folded or unfolded by hand, keyed on the entry (`FR-1.2.13`).
    ///
    /// **Stored nowhere, deliberately.** `NFR-1.8` is about logged data surviving a force-quit, and
    /// which card is open is not logged data — a workout reopened tomorrow should follow the rule
    /// (finished exercises collapsed, the rest open) rather than the folds of an earlier sitting.
    /// An entry here is an override of that rule and lasts as long as the screen does.
    @State var expansion: [UUID: Bool] = [:]

    /// Which cards' warmup groups the user has folded by hand (`FR-1.2.14`).
    ///
    /// Stored nowhere, for ``expansion``'s reason, and a second dictionary rather than a second flag
    /// in that one because the two folds are independent — see ``SessionExerciseList``.
    @State var warmupExpansion: [UUID: Bool] = [:]

    /// Which set groups the user has opened (`FR-16.1.3`).
    ///
    /// Stored nowhere, for ``expansion``'s reason, and a set of ids rather than a dictionary —
    /// collapsed is the default a group returns to, and there is no third state to record.
    @State var groupExpansion: Set<UUID> = []

    /// Whether `FR-16.6.1`'s note fold is open.
    ///
    /// Stored nowhere, for ``expansion``'s reason, and folded is where a workout reopened tomorrow
    /// starts: the note is written once, at the end, and the header says its first line meanwhile.
    @State var areNotesExpanded = false

    /// Whether this screen's opening read has finished (`FR-16.6.1`).
    ///
    /// **Once per screen, not once per read** — see ``scrollToExerciseInProgress(_:)`` for what
    /// goes wrong without it.
    @State private var hasScrolledToExerciseInProgress = false

    /// What is in `FR-1.2.9`'s session-note field.
    ///
    /// **The screen's, like every other half-typed thing here**, and the store's own rule for what
    /// it holds: a note being typed is not a fact about the workout until it is saved. It follows
    /// the held session — see ``SessionNoteDraft/follow(_:)`` for what happens to an unsaved edit
    /// when the record is re-read.
    @State var noteDraft = SessionNoteDraft()

    /// Which exercise the set editor is open over, or `nil` (`FR-1.2.3`, `FR-1.2.6`).
    ///
    /// **The screen's, and it carries no route.** A half-filled set is not a place in the app: a
    /// restored navigation stack that reopened this sheet would offer to log a set the user was in
    /// the middle of abandoning when they force-quit, prefilled from a workout that may since have
    /// been discarded.
    @State var editing: SetEditorTarget?

    /// Which locale the set editor parses and renders numbers in (`G-3.4`).
    @Environment(\.locale) var locale

    /// Which calendar and time zone the title's training day is resolved in — the device's own,
    /// bound explicitly for ``Localization/AppFormat/resolved(_:in:)``'s reason.
    @Environment(\.calendar) private var calendar

    /// Builds the screen over the store that holds the workout.
    ///
    /// - Parameters:
    ///   - store: The workout in progress. One per app, built where the repositories are.
    ///   - vocabulary: The modifier terms the set editor offers (`FR-1.2.8`), built there too.
    ///   - equipment: The gym the plate calculator loads against (`FR-1.4.1`), built there too.
    public init(
        store: ActiveSessionStore,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore
    ) {
        self.store = store
        self.vocabulary = vocabulary
        self.equipment = equipment
    }

    /// The workout, or whichever of the screen's other states is current.
    ///
    /// `.task` calls ``ActiveSessionStore/resume()`` for the restored-stack case: this screen can be
    /// the first thing the app draws, and it must not announce that there is no workout while the
    /// read that would find one has not run. The call is idempotent — a workout already held is kept
    /// and nothing is read.
    public var body: some View {
        ScrollViewReader { proxy in
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
            .task {
                // The first two in this order: the exercises belong to whichever workout the
                // resume settled on, and reading them first would read them for the workout held
                // before it. The unit is independent of both and is re-read on every appearance —
                // the preference lives in another tab, and this screen is returned to rather than
                // rebuilt.
                await store.resume()
                await store.loadExercises()
                // Third, because it is read against the workout the resume settled on and the cards
                // it is keyed to. `FR-1.2.10`'s answer cannot move while this workout is being
                // logged, so nothing but an added exercise reads it again.
                await store.loadPreviousPerformances()
                await store.loadDisplayUnit()
                noteDraft.follow(store.session)
                // Last, and after a hop: `scrollTo` can only reach a row the list has laid out, and
                // the cards these reads produced are laid out on a later pass than the one this
                // task is running in. Yielding is what puts the scroll on that pass.
                await Task.yield()
                scrollToExerciseInProgress(proxy)
            }
        }
        .background(ColorToken.background)
        .navigationTitle(title)
        // Inline rather than large, which is `NFR-16.3`'s cheapest 50-odd points: a large title
        // block is a second heading above a screen whose first line already names the workout, and
        // this one now carries the training day, so it is a fact rather than a decoration.
        .inlineNavigationTitle()
        // Every path that replaces the held record, the note's own save among them: the draft gives
        // way to what is stored only where the two already agreed.
        .onChange(of: store.session) { noteDraft.follow(store.session) }
        .sheet(item: $editing) { target in
            SetEditorSheet(
                draft: draft(for: target),
                isEditing: target.editing != nil,
                prescribed: target.prescribed,
                unit: store.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { write($0, target) },
                cancel: { editing = nil },
                delete: { delete(target) }
            )
            // The medium detent is what puts every logging control in the lower two-thirds
            // (`NFR-1.4`); the large one is there because at `accessibility3` the fields no
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
        .pendingSetQuestion(
            count: pendingSetCount,
            isPresented: $isResolvingPendingSets,
            resolve: { resolution in Task { await finish(resolving: resolution) } }
        )
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
                        await store.loadPreviousPerformances()
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
        SessionSummaryLine(session: session, adherence: store.adherence)
        exercises
        SessionNotesFold(
            draft: $noteDraft,
            isExpanded: $areNotesExpanded,
            hasFailed: store.noteWriteFailure != nil,
            save: { Task { await store.saveNote(noteDraft.text) } }
        )
        // The banner describes one attempt to store one piece of text, so the next keystroke ends
        // it — including the one that puts the stored note back. Without this it outlives the edit
        // it belongs to, leaving a retry on screen with nothing left to write.
        .onChange(of: noteDraft.text) { store.noteWriteFailure = nil }
        SessionCommandsSection(
            hasFailed: writeFailed,
            finish: { Task { await finish() } },
            discard: { isConfirmingDiscard = true }
        )
    }

    /// The screen's title: its name, and the training day once there is a workout to name one
    /// (`FR-16.6.1`).
    ///
    /// **The bare name is what the other three states get**, and it is not a placeholder — a screen
    /// that is still reading, or that has nothing to show, has no day to put in its title, and
    /// inventing today's would name a workout that is not there.
    private var title: Text {
        guard let session = store.session else { return Text(LoggingStrings.sessionTitle) }
        return Text(
            LoggingStrings.sessionTitleDay(
                session.date.formatted(
                    AppFormat.resolved(AppFormat.dayAndMonth(locale: locale), in: calendar))))
    }

    /// Scrolls to the exercise in progress, once, when the opening read has finished
    /// (`FR-16.6.1`).
    ///
    /// **Called from `.task` rather than watched for**, and that is the whole of the rule. The
    /// answer changes every time an exercise is checked off, so a screen that scrolled whenever it
    /// *became* non-`nil` would jump mid-workout — measured in the simulator, where marking the
    /// first exercise done dragged the view back to the second. Resuming is a question about
    /// opening the screen, so it is asked once, there.
    ///
    /// **The flag is set even when there is nowhere to go**, for the same reason: what it records
    /// is that the opening read has happened, not that a scroll did.
    ///
    /// - Parameter proxy: The enclosing scroll view's proxy.
    private func scrollToExerciseInProgress(_ proxy: ScrollViewProxy) {
        guard !hasScrolledToExerciseInProgress else { return }
        hasScrolledToExerciseInProgress = true
        guard let target = SessionResumeTarget.exerciseInProgress(in: store.exercises) else {
            return
        }
        proxy.scrollTo(target, anchor: .top)
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
                    // Secondary, and that is `FR-16.6.4` rather than taste: this placeholder is a
                    // section inside a workout that still draws **Finish workout** below it, so a
                    // filled action here would be the screen's second accent.
                    action: StateAction(
                        Text(LoggingStrings.sessionAddExerciseAction), emphasis: .secondary
                    ) {
                        navigation?.navigate(to: .exerciseLibrary(.exercisePicker))
                    }
                )
                writeFailure(writeFailed)
            case .listed(let items, let writeFailed):
                SessionExerciseList(
                    exercises: items,
                    expansion: $expansion,
                    warmupExpansion: $warmupExpansion,
                    groupExpansion: $groupExpansion,
                    move: { id, offset in
                        Task { await store.moveExercise(id: id, by: offset) }
                    },
                    unit: store.displayUnit,
                    previous: store.previous,
                    personalRecords: store.personalRecords,
                    logSet: { editing = $0 },
                    mark: { markSet($0, asWarmup: $1) },
                    markCompleted: { markSet($0, asCompleted: $1) },
                    edit: { editing = Self.target(editing: $0, prescribed: prescription(for: $0)) },
                    markDone: { id, isDone in
                        Task { await store.markExercise(id: id, isDone: isDone) }
                    },
                    logPlanned: { id in
                        Task { await store.logPlannedSet(inEntryID: id) }
                    },
                    logNext: { id, set in
                        Task { await store.logNextSet(inEntryID: id, copying: set.id) }
                    }
                )
                writeFailure(writeFailed)
                previousFailure
                addExerciseLink
            case .readFailed:
                ErrorStateView(
                    headline: Text(LoggingStrings.sessionExercisesErrorHeadline),
                    message: Text(LoggingStrings.sessionExercisesErrorMessage),
                    retry: {
                        Task {
                            await store.loadExercises()
                            await store.loadPreviousPerformances()
                        }
                    }
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

    /// A history that could not be read, where there was one (`FR-1.2.10`).
    ///
    /// **Once, under the cards — not inside each of them.** One walk answers every strip in the
    /// workout, so a failure is one fact; repeated per card it would be the same sentence six times
    /// down a session. The cards keep everything else, so this is not a phase, and the retry is the
    /// exercises' own.
    @ViewBuilder private var previousFailure: some View {
        if store.previous.readFailure != nil {
            ErrorStateView(
                message: Text(LoggingStrings.sessionPreviousErrorMessage),
                retry: { Task { await store.loadPreviousPerformances() } }
            )
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
}
