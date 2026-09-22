import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// One day of the week, as a checklist (`FR-17.9.1`, `D-17.6`).
///
/// **The session is implicit and there is no Start.** A lifter opens the day, taps a circle per
/// exercise, and the workout is written underneath them (`FR-17.9.5`); the last answer ends it
/// (`FR-17.9.8`). Backdating, skipping the rest and resetting the day are in an overflow menu
/// rather than on the screen, because none of them is what anyone came here to do.
///
/// **Addressed by the stamp rather than by a session id**, which is the route's own argument: a day
/// nothing has been logged into has no session, so a session id could not name it.
public struct DayView: View {
    /// The day's own state — the plan, the answers, and the commands that write them.
    @State private var day: DayStore

    /// The workout the answers are written into, for the unit its loads read in (`G-3.1`) and for
    /// the editor's own writes.
    private let store: ActiveSessionStore

    /// The modifier terms the Log sheet offers (`FR-1.2.8`).
    private let vocabulary: SetModifierVocabulary

    /// The gym `FR-1.4.1`'s loading is worked out on, for the same sheet.
    private let equipment: PlateCalculatorStore

    /// Opens Edit week at the `ProgramDay` handed over (`FR-18.7.2`).
    ///
    /// **Supplied by the app target rather than done here**, and it is the only command on this
    /// screen that is: which day the week's editor unfolds is that editor's own app-lifetime state,
    /// and `TR-1.3` forbids this module from importing `Routines` to set it. So the app target —
    /// which already composes both — sets the day and makes the push, exactly as it does for the
    /// exercise chooser at the other end of the same wire.
    ///
    /// **Required, with no default** (`T-16.17`): a screen that silently did nothing here would be
    /// a menu item that does nothing, which is the whole of what `F-13` reported.
    private let editPlan: (UUID) -> Void

    /// Builds the screen over the stamp the route carried.
    ///
    /// - Parameters:
    ///   - runID: The program run.
    ///   - week: The week number stamped on the day's session.
    ///   - dayIndex: The `ProgramDay.order` this is.
    ///   - store: The workout the answers are written into.
    ///   - vocabulary: The modifier terms the Log sheet offers (`FR-1.2.8`).
    ///   - equipment: The gym the plate calculator works over (`FR-1.4.1`).
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routine the day names.
    ///   - exercises: The catalogue the plan's slots name.
    ///   - editPlan: Opens Edit week at the `ProgramDay` handed over (`FR-18.7.2`). See
    ///     ``editPlan`` for why it is the app target's.
    public init(
        runID: UUID,
        week: Int,
        dayIndex: Int,
        store: ActiveSessionStore,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        exercises: any ExerciseRepository,
        editPlan: @escaping (UUID) -> Void
    ) {
        self.store = store
        self.vocabulary = vocabulary
        self.equipment = equipment
        self.editPlan = editPlan
        _day = State(
            initialValue: DayStore(
                runID: runID,
                week: week,
                dayIndex: dayIndex,
                store: store,
                programs: programs,
                routines: routines,
                exercises: exercises))
    }

    /// The day, whichever state it is in, with the commands that are true in all of them.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(title))
        .task {
            await store.loadDisplayUnit()
            await day.load()
        }
        .sheet(item: $editing) { target in
            SetEditorSheet(
                sections: SetEditorSections(
                    answering: target.row, unit: store.displayUnit, locale: locale),
                mode: .row(target.row),
                prescribed: target.prescribed,
                unit: store.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { sections in
                    let rows = sections.rows
                    let rowID = target.rowID
                    editing = nil
                    Task { await day.log(rowID: rowID, rows: rows) }
                },
                cancel: { editing = nil },
                skip: {
                    let rowID = target.rowID
                    editing = nil
                    Task { await day.skip(rowID: rowID) }
                }
            )
            // `.large`, and it is measured rather than chosen — see
            // `SetEditorSheet.smallestScreen`. This sheet's heading, Weight, Reps and its pinned
            // commands are 554 pt at the default type size on a 667 pt screen, so `FR-17.1.6`'s
            // "Weight and Reps visible together" rules out `.medium` and every fraction below
            // 0.84. A second detent that could not hold them would be a height this form must
            // never open at.
            .presentationDetents([.large])
        }
        // Leading, beside Back (`FR-18.4.2`): the trailing corner is Done's now.
        .sessionOverflow(
            contents: Self.menuContents(
                date: day.date,
                startsWhenDated: day.hasPlan,
                offersPlanEditing: day.weekDayID != nil,
                progress: day.progress),
            side: .leading,
            changeDate: { chosen in Task { await day.changeDate(to: chosen) } },
            commands: SessionMenuCommands(
                editPlan: openThePlan,
                skipRemaining: { isConfirmingSkipRemaining = true },
                discard: { requestDayReset() })
        )
        .sessionDone(label: LoggingStrings.dayDoneAction)
        .confirmationDialog(
            Text(LoggingStrings.dayLogRemainingConfirmTitle(count: unansweredCount)),
            isPresented: $isConfirmingLogRemaining,
            titleVisibility: .visible
        ) {
            Button {
                Task { await day.logRemainingAsPlanned() }
            } label: {
                Text(LoggingStrings.dayLogRemainingConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.dayRemainingConfirmCancel)
            }
        }
        .confirmationDialog(
            Text(LoggingStrings.daySkipRemainingConfirmTitle(count: unansweredCount)),
            isPresented: $isConfirmingSkipRemaining,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await day.skipRemaining() }
            } label: {
                Text(LoggingStrings.daySkipRemainingConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.dayRemainingConfirmCancel)
            }
        }
        // `FR-18.4.5`: the same write the free workout's **Discard** makes, and a different
        // promise about it — here the plan is on the week and survives.
        .confirmationDialog(
            Text(LoggingStrings.dayResetConfirmTitle),
            isPresented: $isConfirmingReset,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await day.discard() }
            } label: {
                Text(LoggingStrings.dayResetConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.dayResetConfirmCancel)
            }
        } message: {
            Text(LoggingStrings.dayResetConfirmMessage)
        }
        // `FR-18.5.2`: asked only where the row holds completed sets, and it names how many. A
        // bare skip holds none, so ``resetConfirmation(for:)`` sends it straight through.
        .confirmationDialog(
            Text(LoggingStrings.dayRowResetConfirmTitle(count: askedSetCount)),
            isPresented: isConfirmingRowReset,
            titleVisibility: .visible,
            presenting: resetting
        ) { target in
            // The target is handed in rather than read back off the state: the binding is cleared
            // on the way out, and an action that read `resetting` would depend on which of the two
            // SwiftUI does first.
            Button(role: .destructive) {
                Task { await day.reset(rowID: target.rowID) }
            } label: {
                Text(LoggingStrings.dayRowResetConfirmAction)
            }
            Button(role: .cancel) {
            } label: {
                Text(LoggingStrings.dayRowResetConfirmCancel)
            }
        }
    }

    /// Whether a row's reset has to ask first, and what it would say (`FR-18.5.2`).
    ///
    /// **A function rather than a condition inside the command**, on ``menuContents(date:startsWhenDated:offersPlanEditing:progress:)``'s
    /// rule: *which rows ask* is the requirement, and written inline it would be a claim no test can
    /// call. There is no undo of the reset — the sets are soft-deleted and nothing in the app brings
    /// one back — which is why a row carrying work asks at all, and why one carrying none does not.
    ///
    /// - Parameter row: The row whose answer is being taken back.
    /// - Returns: What the question would name, or `nil` where none is owed.
    static func resetConfirmation(for row: DayRow) -> DayRowResetTarget? {
        guard row.loggedSetCount > 0 else { return nil }
        return DayRowResetTarget(rowID: row.id, setCount: row.loggedSetCount)
    }

    /// Whether **Reset day** has to ask first (`FR-18.4.6`, `Q-18.14` at (b)).
    ///
    /// **Four clauses, and the day holds nothing but its date only when all four are quiet.** The
    /// row's rule one function up can be narrow because a row's reset removes that row's sets; this
    /// one removes the whole workout — every mark, every added row and the note — so it asks over
    /// anything the lifter would have to put back by hand. The note is the sharpest of the four: it
    /// is the only thing on a day that no tap can redo.
    ///
    /// **A row with no plan is a row the lifter added** (`FR-1.2.2`), which is ``DayRowCircle``'s
    /// reading of the same emptiness — and this is only ever asked where the day has a workout, the
    /// menu's destructive item being drawn on a date alone (``SessionMenuContents``).
    ///
    /// **That third clause is a proxy, and it over-asks.** A planned exercise whose only target
    /// group was never filled in is stored with no groups at all — the slot is written when the
    /// exercise is picked and its blank group is in no table until it resolves — so on the day it
    /// is indistinguishable from a row the lifter added, and such a day asks although it holds
    /// nothing but its date. Nothing on the entry records which of the two it was, and the fact
    /// that would part them is a stored one (`TR-18.5`). Left as it is on purpose: of the two ways
    /// to be wrong here, asking once too often is the one that costs no work. The same emptiness is
    /// safe in ``DayRowCircle`` for a reason that does not carry here — a row with no target has
    /// nothing "as planned" could mean whoever added it.
    ///
    /// - Parameters:
    ///   - rows: The day's rows.
    ///   - note: The workout's session note — ``DayStore/note``.
    /// - Returns: Whether the confirmation is owed.
    static func dayResetAsks(rows: [DayRow], note: String) -> Bool {
        if rows.contains(where: { $0.loggedSetCount > 0 }) { return true }
        if rows.contains(where: { $0.answer != .unanswered }) { return true }
        if rows.contains(where: { $0.plan.isEmpty }) { return true }
        // Trimmed, on ``SessionNoteDraft/firstLine``'s reading of what a note is: a field holding a
        // space is not prose the lifter would miss.
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// What this screen's `⋯` holds (`FR-17.9.7`, `FR-18.4.4`, `FR-18.4.5`).
    ///
    /// **A function rather than three arguments written inline**, because what a `View`'s body
    /// passes a modifier is readable by nothing — see `sessionOverflow` for the measurements. This
    /// is where *the planned day offers* **Reset day** lives, and it is the only place the claim
    /// is made.
    ///
    /// - Parameters:
    ///   - date: The day's training date, or `nil` before it has a workout.
    ///   - startsWhenDated: Whether a routine stands behind the day, so that dating it creates the
    ///     workout (`FR-18.7.1`) — ``DayStore/hasPlan``.
    ///   - offersPlanEditing: Whether the week still holds this day, so **Edit plan** has somewhere
    ///     to open at (`FR-18.7.2`) — ``DayStore/weekDayID``.
    ///   - progress: How far through the day the lifter is.
    /// - Returns: The commands, in order.
    static func menuContents(
        date: Date?,
        startsWhenDated: Bool,
        offersPlanEditing: Bool,
        progress: DayProgress
    ) -> SessionMenuContents {
        SessionMenuContents(
            date: date,
            startsWhenDated: startsWhenDated,
            offersPlanEditing: offersPlanEditing,
            offersSkipRemaining: progress.offersWholeDayCommands,
            destructive: .resetDay)
    }

    /// Which set editor is open, or `nil`.
    @State private var editing: DayLogTarget?

    /// Whether **Log remaining as planned** is asking (`FR-17.9.9`).
    @State private var isConfirmingLogRemaining = false

    /// Whether **Skip remaining** is asking. Raised from the menu now, not from the foot
    /// (`FR-18.4.4`).
    @State private var isConfirmingSkipRemaining = false

    /// Whether **Reset day** is asking (`FR-18.4.5`, `FR-1.2.12`).
    @State private var isConfirmingReset = false

    /// Which row's **Reset to unanswered** is asking, and how many sets it would remove
    /// (`FR-18.5.1`, `FR-18.5.2`), or `nil`.
    @State private var resetting: DayRowResetTarget?

    /// The count the last question named. Whole sets. Kept apart from ``resetting``, which is `nil`
    /// again while the dialog animates out — the title would re-read as *Remove 0 logged sets?*.
    @State private var askedSetCount = 0

    /// That, as the dialog's own presentation. Dismissing it is the question going away rather than
    /// an answer, so nothing is written.
    private var isConfirmingRowReset: Binding<Bool> {
        Binding(get: { resetting != nil }, set: { if !$0 { resetting = nil } })
    }

    /// Which of the exercise's two names reads, and which locale the editor's numbers are in.
    @Environment(\.locale) private var locale

    /// How many rows the whole-day commands would act on — the foot's and the menu's alike.
    private var unansweredCount: Int { day.progress.total - day.progress.answered }

    /// The day's name where its routine has one, and its position where it has not.
    private var title: String {
        let name = day.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty else { return name }
        return String(localized: LoggingStrings.weekDay(day.dayIndex + 1))
    }

    /// The screen's four states (`FR-1.13.1`). No offline state and no insufficient-data state, for
    /// the root's reasons.
    @ViewBuilder private var content: some View {
        switch day.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(LoggingStrings.dayErrorHeadline),
                message: Text(LoggingStrings.dayErrorMessage),
                retryEmphasis: .primary,
                retry: { Task { await day.load() } }
            )
        case .ready:
            if day.rows.isEmpty {
                empty
            } else {
                checklist
            }
        }
    }

    /// A day with nothing in it — two different facts, and the words say which.
    ///
    /// A day whose routine is gone or whose stamp names a week that has turned has no plan
    /// (`FR-15.2.5`); a day whose session the lifter emptied has one and no rows. The second is
    /// reachable only by deleting every entry, and it offers the picker rather than the week.
    @ViewBuilder private var empty: some View {
        if day.isStarted {
            EmptyStateView(
                symbolName: "list.bullet",
                headline: Text(LoggingStrings.dayNoRowsHeadline),
                message: Text(LoggingStrings.dayNoRowsMessage))
            addExercise
        } else {
            EmptyStateView(
                symbolName: "archivebox",
                headline: Text(LoggingStrings.dayEmptyHeadline),
                message: Text(LoggingStrings.dayEmptyMessage))
        }
    }

    /// The rows, the picker and the whole-day command.
    @ViewBuilder private var checklist: some View {
        DayChecklistSection(
            rows: day.rows,
            progress: day.progress,
            unit: store.displayUnit,
            answer: { rowID in Task { await day.answerAsPlanned(rowID: rowID) } },
            log: { rowID in open(rowID) },
            skip: { rowID in Task { await day.skip(rowID: rowID) } },
            reset: { rowID in requestReset(rowID) })
        // Not on a day that has ended: a finished day is read-only except through **Log**
        // (`FR-17.7.5`), and a row added to it would arrive unanswered under a heading that had
        // already counted every row — `n of m` disagreeing with the **Done** its card reads.
        if !day.isDone {
            addExercise
        }
        if day.progress.offersWholeDayCommands {
            DayFootCommands(logRemaining: { isConfirmingLogRemaining = true })
        }
        if !day.unanswerable.isEmpty {
            // A result, not an error: the command did what it could and is saying what it could
            // not, which is `FR-17.9.9`'s whole reason for reporting anything at all.
            Text(LoggingStrings.dayUnanswerable(exercises: unanswerableNames))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if day.writeFailure != nil {
            ErrorStateView(message: Text(LoggingStrings.sessionWriteErrorMessage))
        }
    }

    /// `FR-1.2.2`'s way of putting an exercise into a day the plan did not name.
    ///
    /// **The session is created before the push, not after the selection.** The picker writes
    /// through the store, which refuses an entry with no workout held — so a day nobody has logged
    /// into has to acquire its session on this tap.
    private var addExercise: some View {
        Button {
            Task {
                guard await day.startIfNeeded() else { return }
                navigation?.navigate(to: .exerciseLibrary(.exercisePicker))
            }
        } label: {
            Text(LoggingStrings.dayAddExerciseAction)
        }
        .buttonStyle(.secondaryAction(.fill))
    }

    /// The shell's navigation position, for the picker. Optional and read rather than required, on
    /// `ExerciseListView`'s rule: a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// The rows the last whole-day command could not answer, as the lifter reads them (`G-3.2`).
    private var unanswerableNames: String {
        day.unanswerable
            .map { $0.exercise?.displayName(for: locale) ?? "" }
            .joined(separator: String(localized: LoggingStrings.dayUnanswerableSeparator))
    }

    /// Takes a row's answer back, asking first where there is work to remove (`FR-18.5.1`).
    ///
    /// A row the day no longer holds resets nothing, on ``open(_:)``'s rule below.
    ///
    /// - Parameter rowID: The row.
    private func requestReset(_ rowID: UUID) {
        guard let row = day.rows.first(where: { $0.id == rowID }) else { return }
        guard let target = Self.resetConfirmation(for: row) else {
            Task { await day.reset(rowID: rowID) }
            return
        }
        askedSetCount = target.setCount
        resetting = target
    }

    /// Throws the day's answers away, asking first where there are any (`FR-18.4.5`, `FR-18.4.6`).
    ///
    /// ``requestReset(_:)``'s shape one function up: the question is owed or the command goes
    /// straight through, and the decision is the plain function rather than a condition written
    /// here.
    private func requestDayReset() {
        guard Self.dayResetAsks(rows: day.rows, note: day.note) else {
            Task { await day.discard() }
            return
        }
        isConfirmingReset = true
    }

    /// Opens the week's plan at this day (`FR-18.7.2`).
    ///
    /// **Nothing happens where the week no longer holds the day**, which is the same guard every
    /// command on this screen carries: the menu item is not drawn then
    /// (``menuContents(date:startsWhenDated:offersPlanEditing:progress:)`` reads the same
    /// property), so reaching this with no identity is a wiring fault rather than a state.
    private func openThePlan() {
        guard let weekDayID = day.weekDayID else { return }
        editPlan(weekDayID)
    }

    /// Opens the Log sheet over one row (`FR-17.9.3`).
    ///
    /// A row the day no longer holds opens nothing: it went away underneath the checklist, which is
    /// every command here's rule.
    ///
    /// - Parameter rowID: The row.
    private func open(_ rowID: UUID) {
        guard let row = day.editorRow(forRow: rowID) else { return }
        editing = DayLogTarget(
            rowID: rowID, row: row, prescribed: day.prescribed(forRow: rowID))
    }
}
