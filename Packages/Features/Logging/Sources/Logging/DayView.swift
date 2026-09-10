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
/// (`FR-17.9.8`). Backdating and discarding are in an overflow menu rather than on the screen,
/// because neither is what anyone came here to do.
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
    public init(
        runID: UUID,
        week: Int,
        dayIndex: Int,
        store: ActiveSessionStore,
        vocabulary: SetModifierVocabulary,
        equipment: PlateCalculatorStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        exercises: any ExerciseRepository
    ) {
        self.store = store
        self.vocabulary = vocabulary
        self.equipment = equipment
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
                draft: ActiveSessionView.draft(
                    for: target.editorTarget, unit: store.displayUnit, locale: locale),
                mode: .row(target.row),
                prescribed: target.prescribed,
                unit: store.displayUnit,
                vocabulary: vocabulary,
                equipment: equipment,
                log: { draft in
                    guard let group = draft.resolvedGroup else { return }
                    let rowID = target.rowID
                    editing = nil
                    Task { await day.log(rowID: rowID, group: group) }
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
        .sessionOverflow(
            date: day.date,
            changeDate: { chosen in Task { await day.changeDate(to: chosen) } },
            discard: { isConfirmingDiscard = true }
        )
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
        .confirmationDialog(
            Text(LoggingStrings.sessionDiscardConfirmTitle),
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                Task { await day.discard() }
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

    /// Which set editor is open, or `nil`.
    @State private var editing: DayLogTarget?

    /// Whether **Log remaining as planned** is asking (`FR-17.9.9`).
    @State private var isConfirmingLogRemaining = false

    /// Whether **Skip remaining** is asking.
    @State private var isConfirmingSkipRemaining = false

    /// Whether **Discard** is asking (`FR-1.2.12`).
    @State private var isConfirmingDiscard = false

    /// Which of the exercise's two names reads, and which locale the editor's numbers are in.
    @Environment(\.locale) private var locale

    /// How many rows the two whole-day commands would act on.
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

    /// The rows, the picker and the two whole-day commands.
    @ViewBuilder private var checklist: some View {
        DayChecklistSection(
            rows: day.rows,
            progress: day.progress,
            unit: store.displayUnit,
            answer: { rowID in Task { await day.answerAsPlanned(rowID: rowID) } },
            log: { rowID in open(rowID) },
            skip: { rowID in Task { await day.skip(rowID: rowID) } })
        // Not on a day that has ended: a finished day is read-only except through **Log**
        // (`FR-17.7.5`), and a row added to it would arrive unanswered under a heading that had
        // already counted every row — `n of m` disagreeing with the **Done** its card reads.
        if !day.isDone {
            addExercise
        }
        if day.progress.offersWholeDayCommands {
            DayFootCommands(
                logRemaining: { isConfirmingLogRemaining = true },
                skipRemaining: { isConfirmingSkipRemaining = true })
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

/// Which row the Log sheet is open over (`FR-17.9.3`, `FR-17.9.4`).
///
/// **The row rather than the entry**, because the sheet can be opened on a day that has no session
/// yet: the first answer creates it, and the row is what survives that (see
/// ``DayStore/log(rowID:group:)``).
struct DayLogTarget: Identifiable, Equatable {
    /// The row.
    let rowID: UUID

    /// The plan, what is already logged, and whether the row is answered — what the sheet's row
    /// mode is drawn from.
    let row: SetEditorRow

    /// What the routine prescribed for the next set, drawn above the fields (`FR-15.3.1`).
    let prescribed: PlannedTargetGroup?

    /// The row's identity is the sheet's.
    var id: UUID { rowID }

    /// The same thing in the shape the shared editor takes.
    var editorTarget: SetEditorTarget {
        SetEditorTarget(entryID: rowID, prescribed: prescribed, row: row)
    }
}

/// The day's rows, under the count of how many are answered (`FR-17.9.1`).
///
/// A view rather than a `GroupedSection` built inside the screen, which is `T-16.17`'s finding: the
/// heading, the grouping and what each row offers are the screen's decisions, and a fixture that
/// restates them pictures itself.
struct DayChecklistSection: View {
    /// The day's exercises, in order.
    let rows: [DayRow]

    /// How far through them the lifter is.
    let progress: DayProgress

    /// The unit their loads read in (`G-3.1`).
    let unit: MassUnit

    /// Logs one row exactly as planned (`FR-17.9.2`), or `nil` on a past day (`FR-17.7.6`).
    var answer: ((UUID) -> Void)?

    /// Opens the editor over one row (`FR-17.9.3`). Never absent — see ``DayExerciseRow/log``.
    let log: (UUID) -> Void

    /// Records that the lifter is not doing one row today (`FR-17.9.6`), or `nil` — see ``answer``.
    var skip: ((UUID) -> Void)?

    var body: some View {
        GroupedSection(
            Text(LoggingStrings.dayProgress(done: progress.answered, of: progress.total))
        ) {
            ForEach(rows) { row in
                DayExerciseRow(
                    row: row,
                    unit: unit,
                    // Rebound per row rather than passed through: the row's own commands take no
                    // argument, and an absent one here has to stay absent there.
                    answer: answer.map { command in { command(row.id) } },
                    log: { log(row.id) },
                    skip: skip.map { command in { command(row.id) } })
            }
        }
    }
}

/// The two commands that answer for everything that is left (`FR-17.9.9`).
///
/// **At the foot, under `+ Add exercise`, and both secondary.** They are the exception rather than
/// the way a day is normally answered — the circle is — and a filled pair here would be two primary
/// actions on a screen whose accent belongs to the work.
struct DayFootCommands: View {
    /// Logs everything that is left exactly as planned.
    let logRemaining: () -> Void

    /// Records that the lifter is not doing the rest.
    let skipRemaining: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm.points) {
            Button(action: logRemaining) {
                Text(LoggingStrings.dayLogRemainingAction)
            }
            .buttonStyle(.plain)
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)

            Button(action: skipRemaining) {
                Text(LoggingStrings.daySkipRemainingAction)
            }
            .buttonStyle(.plain)
            .font(Typography.actionLabel.font)
            .foregroundStyle(ColorToken.textSecondary)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
