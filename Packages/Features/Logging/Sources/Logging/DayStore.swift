import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One day of the week, as a checklist (`FR-17.9.1`, `D-17.6`).
///
/// **The session is implicit.** There is no Start and no Finish: the first answer creates the
/// session — entries, planned rows, the stamp, `startedAt` — and the last answer ends it
/// (`FR-17.9.5`, `FR-17.9.8`). What a lifter does on this screen is tick exercises off, and the
/// workout is the record that keeps.
///
/// **It drives ``ActiveSessionStore`` rather than writing on its own.** The picker that adds an
/// exercise and the editor that logs a set are screens pushed above this one and write through that
/// store; a day that kept its own session would have both of them writing into a different workout.
/// So the store is pointed at this day (``SessionLocator``) and the commands here are its commands,
/// chained.
///
/// **The plan is read here and the week is not** (`NFR-17.4`). Reading the week to get one day's
/// plan would read every started day's entries to answer a question about one — the entry walk
/// `T-17.10`'s review named. This reads the run, the day, its routine and its targets; the entries
/// are read exactly once, by the store, and only where the day has a session at all.
@Observable
public final class DayStore {
    /// What the screen has to show. ``WeekState/Phase``'s four, for the same reason.
    public typealias Phase = WeekState.Phase

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The day's name, or empty where its routine has been archived (`FR-15.2.5`).
    public private(set) var name = ""

    /// The day's exercises, in order — the plan before the first answer, the session's entries
    /// after it.
    ///
    /// **Derived rather than kept**, and that is a correctness rule rather than a style: `+ Add
    /// exercise` pushes the picker above this screen and it writes through ``ActiveSessionStore``
    /// (`FR-1.2.2`), which this screen's `.task` does not re-run to notice — a pushed screen's
    /// `.task` runs once (``ActiveSessionView``'s retry says so in as many words). A stored copy
    /// would therefore be missing the row the lifter had just added until the day was left and
    /// re-entered. Reading through the store instead makes the added row appear the moment the
    /// picker pops, and costs no repository read: the entries are already in memory.
    public var rows: [DayRow] {
        guard store.session != nil else {
            return planLines.map { DayRow(id: $0.id, exercise: $0.exercise, plan: $0.targets) }
        }
        let marks = store.personalRecords
        return store.exercises.map { DayRow.performed($0, marks: marks) }
    }

    /// The training day the session belongs to, or `nil` before there is one (`FR-1.2.1`).
    ///
    /// Read through the store for ``rows``'s reason.
    public var date: Date? { store.session?.date }

    /// The rows the last whole-day command could not answer because their plan named no load
    /// (`FR-15.2.2`, `FR-17.9.9`).
    ///
    /// **A result rather than a silence.** **Log remaining as planned** claims to answer the rest,
    /// and a row it stepped over is a row the lifter is still owed an answer about.
    ///
    /// **The rows rather than their names**, because a store has no locale (`G-3.2`): which of an
    /// exercise's two names reads is the screen's question.
    public private(set) var unanswerable: [DayRow] = []

    /// The `ProgramDay.order` this screen is over.
    public let dayIndex: Int

    /// How far through the day the lifter is (`FR-17.9.1`).
    public var progress: DayProgress { DayProgress(rows) }

    /// Whether the day's session has been ended (`FR-17.9.8`).
    public var isDone: Bool { store.session?.endedAt != nil }

    /// Whether a session exists for this day at all.
    ///
    /// **What it separates is the two empty days**, which is the screen's only use for it: a day
    /// whose routine is gone has no plan to draw, and a day whose session the lifter emptied has a
    /// session and no rows. The overflow menu is gated on ``date`` rather than on this — a menu is
    /// hidden by having no workout to act on, which is the same fact said where it is used.
    public var isStarted: Bool { store.session != nil }

    /// Whether a routine stands behind this day, and therefore whether anything can be started on
    /// it (`FR-18.7.1`).
    ///
    /// **What it gates is a menu item, and the reason is that the command would otherwise do
    /// nothing.** ``startIfNeeded(on:)`` refuses where there is no routine to copy — a run that has
    /// moved on, a week that has turned, a routine archived (`FR-15.2.5`) — so **Change date**
    /// offered there is an item that closes its own sheet and writes nothing.
    ///
    /// **Not the same question as ``weekDayID``**, one line down: a day whose routine is archived
    /// is still in the week, so its plan can be edited and nothing can be logged against it.
    public var hasPlan: Bool { routineID != nil }

    /// The ``RepositoryInterface/ProgramDay`` this screen is over, or `nil` where the run has moved
    /// on, the week has turned or the day is no longer in the program.
    ///
    /// **What Edit week is opened *at*** (`FR-18.7.2`). Which day the week's editor unfolds is
    /// app-lifetime state there (`Routines.WeekEditorState.openDayID`) rather than anything this
    /// module can reach (`TR-1.3`), so what this exposes is the identity and the app target is the
    /// join — the same shape as the exercise chooser two screens over.
    public private(set) var weekDayID: UUID?

    /// The last write against the day that failed, as the error's description, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`). Read off the store, which is where the writes happen.
    public var writeFailure: String? { store.exercisesWriteFailure ?? store.failure }

    /// The run the route carried.
    private let runID: UUID

    /// The week the route carried.
    private let week: Int

    /// The workout the answers are written into.
    /// Internal rather than private so a test can settle the badge:
    /// ``ActiveSessionStore/announceSetChange(inEntryID:)`` publishes behind the answer (`NFR-1.2`),
    /// and an assertion about ``DayRow/records`` taken on the command's own `await` is a race.
    let store: ActiveSessionStore

    /// The programs, their days and the run in force.
    private let programs: any ProgramRepository

    /// The routines the day names — read for its name, and handed to the start that copies it.
    private let routines: any RoutineRepository

    /// What the routine prescribes.
    private let plans: WeekPlanReader

    /// The plan as read, kept so a slot can be mapped onto the entry the copy wrote for it.
    ///
    /// Internal rather than file-scoped because the reads the Log sheet opens over live in
    /// `DayPlanReads.swift`, which `private` would put out of reach — `ActiveSessionView`'s rule
    /// for the same split. Nothing outside `Logging` can see it.
    var planLines: [WeekPlanLine] = []

    /// The routine this day names, or `nil` where the run, the day or the routine has gone.
    private var routineID: UUID?

    /// Builds the day over the store it writes through and the repositories its plan is read from.
    ///
    /// - Parameters:
    ///   - runID: The program run.
    ///   - week: The week number stamped on the day's session.
    ///   - dayIndex: The `ProgramDay.order` this is.
    ///   - store: The workout the answers are written into.
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routine the day names.
    ///   - exercises: The catalogue the plan's slots name.
    public init(
        runID: UUID,
        week: Int,
        dayIndex: Int,
        store: ActiveSessionStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        exercises: any ExerciseRepository
    ) {
        self.runID = runID
        self.week = week
        self.dayIndex = dayIndex
        self.store = store
        self.programs = programs
        self.routines = routines
        self.plans = WeekPlanReader(routines: routines, exercises: exercises)
    }

    /// Reads the day, on every appearance and after every write.
    ///
    /// **The plan first, then the session.** The plan is what a day nobody has logged into draws,
    /// and it is also how a slot is mapped onto the entry that was written for it; the session read
    /// is `TR-17.5`'s one query.
    public func load() async {
        phase = .loading
        do {
            plans.reset()
            try await readPlan()
        } catch {
            phase = .failed(String(describing: error))
            return
        }
        await store.open(.day(runID: runID, week: week, dayIndex: dayIndex))
        if store.session != nil {
            await store.loadExercises()
        }
        phase = .ready
    }

    /// Logs one exercise exactly as planned and marks it done, in one tap (`FR-17.9.2`).
    ///
    /// **It is the first answer that creates the session**, and the two are one chain: the start
    /// copies the routine's slots onto entries, and this then answers the entry that slot became.
    ///
    /// **`NFR-1.2`'s interval, and it starts at the tap rather than at the write.** The budget is
    /// the wait between the circle being tapped and the row having re-read, so it has to contain
    /// ``startIfNeeded()`` — the first answer of the day creates the session, and that is the
    /// slowest one there is — as well as the reload the row is actually redrawn from.
    ///
    /// - Parameter rowID: The row the circle was tapped on.
    public func answerAsPlanned(rowID: UUID) async {
        await PerformanceSignpost.answer.measure { await performAnswerAsPlanned(rowID: rowID) }
    }

    /// ``answerAsPlanned(rowID:)``'s body, split out only so the interval above can bracket it.
    ///
    /// - Parameter rowID: The row the circle was tapped on.
    private func performAnswerAsPlanned(rowID: UUID) async {
        unanswerable = []
        guard await startIfNeeded(), let entryID = entryID(forRow: rowID) else { return }
        await store.answerAsPlanned(inEntryID: entryID)
        await finishIfComplete()
        await reload()
    }

    /// Records that the lifter is not doing this exercise today (`FR-17.9.6`).
    ///
    /// - Parameter rowID: The row.
    public func skip(rowID: UUID) async {
        unanswerable = []
        guard await startIfNeeded(), let entryID = entryID(forRow: rowID) else { return }
        await store.skipExercise(inEntryID: entryID)
        await finishIfComplete()
        await reload()
    }

    /// Takes one exercise's answer back (`FR-18.5.1`).
    ///
    /// **No ``startIfNeeded()``, unlike every other command here.** A day nobody has logged into
    /// has no answer to take back, so a reset that created the session would write a workout from
    /// an undo — and it writes nothing there without a guard of its own, ``entryID(forRow:)``
    /// having no entry to map a plan slot onto until the session exists. (A guard on the session
    /// was written here first and no test could tell it from its absence, which is what a probe is
    /// for.) **And no ``finishIfComplete()``**: a row this has just un-answered is a row the day is
    /// not complete without, so the call could only ever decline — the re-opening the other way is
    /// the store command's (`FR-18.5.3`).
    ///
    /// - Parameter rowID: The row.
    public func reset(rowID: UUID) async {
        unanswerable = []
        guard let entryID = entryID(forRow: rowID) else { return }
        await store.resetExercise(inEntryID: entryID)
        await reload()
    }

    /// Logs every unanswered exercise that has a load exactly as planned (`FR-17.9.9`).
    ///
    /// **One chain, one re-read, and a result.** The rows it cannot answer are the ones whose plan
    /// named no load — they are named in ``unanswerable`` rather than skipped, because nobody said
    /// the lifter was not doing them.
    ///
    /// **A command that can answer nothing does not start the day.** `FR-17.9.5` creates the
    /// session at the *first answer*, and a day whose every remaining row names no load has no
    /// answer to give — starting it anyway would write a workout holding nothing, which the week's
    /// card then reads as in progress forever.
    ///
    /// **`NFR-1.2`'s interval on its largest N.** `NFR-17.3` is the reason this is one chain, and
    /// this is the answer that exercises it hardest — every remaining row of the day at once.
    public func logRemainingAsPlanned() async {
        await PerformanceSignpost.answer.measure { await performLogRemainingAsPlanned() }
    }

    /// ``logRemainingAsPlanned()``'s body, split out only so the interval above can bracket it.
    private func performLogRemainingAsPlanned() async {
        let remaining = rows.filter { $0.answer == .unanswered }
        let answerable = remaining.filter(\.hasCircle)
        // The result is owed either way: the lifter asked for the rest to be answered and is still
        // owed an answer about the rows this stepped over.
        unanswerable = remaining.filter { !$0.hasCircle }
        guard !answerable.isEmpty, await startIfNeeded() else { return }
        let entryIDs = answerable.compactMap { entryID(forRow: $0.id) }
        if !entryIDs.isEmpty {
            await store.answerAsPlanned(inEntryIDs: entryIDs)
            await finishIfComplete()
        }
        await reload()
    }

    /// Records that the lifter is not doing the rest of the day (`FR-17.9.9`, `FR-17.8.8`).
    ///
    /// **On a day never started this is the first answer**, and creates the session like any other:
    /// a day skipped whole is a day that was answered, and the week's card has to be able to say so.
    /// **A day with nothing left to answer does not acquire a session here either**, which is
    /// ``logRemainingAsPlanned()``'s rule: a day whose routine has no slots would otherwise be
    /// given a workout with no entries, and ``finishIfComplete()`` cannot end one of those.
    public func skipRemaining() async {
        unanswerable = []
        let remaining = rows.filter { $0.answer == .unanswered }
        guard !remaining.isEmpty, await startIfNeeded() else { return }
        let entryIDs = remaining.compactMap { entryID(forRow: $0.id) }
        if !entryIDs.isEmpty {
            await store.skipExercises(inEntryIDs: entryIDs)
            await finishIfComplete()
        }
        await reload()
    }

    /// Writes the Log sheet's group and marks the row done (`FR-17.9.3`, `FR-17.9.4`).
    ///
    /// **The answer for a row the circle cannot take** — one whose plan named no load
    /// (`FR-15.2.2`), one the lifter added, or one performed differently from the plan.
    ///
    /// **Save marks the row done**, which is `FR-17.9.3`'s reading of a checklist: a day is a list
    /// of answers, and logging a set against an exercise is answering for it.
    ///
    /// **Every section's sets arrive as one list and are written as one chained command**
    /// (`FR-18.6.3`, `NFR-18.3`). A plan naming several groups is answered in one visit, and a
    /// section the lifter zeroed contributes nothing rather than a gap — see
    /// ``SetEditorSections/rows``.
    ///
    /// **A row already answered is rewritten rather than appended to** (`FR-17.7.5`). Reopening the
    /// sheet over an answer is the *only* way to change one — the circle is inert by then — so a
    /// save that appended would double the work every time a lifter corrected a rep count.
    ///
    /// **`NFR-1.2`'s interval on the sheet's Save as done** — the requirement's other named path,
    /// and the one that writes N rows for a single tap.
    ///
    /// - Parameters:
    ///   - rowID: The row being logged against.
    ///   - rows: Every set the sheet collected, across every section, in the order they are stored
    ///     in (`FR-18.6.3`).
    func log(rowID: UUID, rows: [SetEntryValues]) async {
        await PerformanceSignpost.answer.measure { await performLog(rowID: rowID, rows: rows) }
    }

    /// ``log(rowID:rows:)``'s body, split out only so the interval above can bracket it.
    ///
    /// - Parameters:
    ///   - rowID: The row being logged against.
    ///   - rows: Every set the sheet collected, across every section.
    private func performLog(rowID: UUID, rows: [SetEntryValues]) async {
        unanswerable = []
        guard await startIfNeeded(), let entryID = entryID(forRow: rowID) else { return }
        // Asked about the *entry*, never about `rowID`. A day with no session draws the routine's
        // slots and a day with one draws its entries, so the identity the sheet was opened on is
        // one `rows` no longer holds the moment the first answer creates the session — and a
        // lookup by it finds nothing on the commonest save there is. ``entryID(forRow:)`` is the
        // translation, and after ``startIfNeeded()`` its answer is always an identity `rows` has.
        if isAnswered(rowID: entryID) {
            await store.rewriteGroup(inEntryID: entryID, rows: rows)
        } else {
            await store.logGroup(inEntryID: entryID, rows: rows)
        }
        await finishIfComplete()
        await reload()
    }

    /// Moves the day's session to another training day, creating it where there is none
    /// (`FR-1.2.1`, `FR-17.9.7`, `FR-18.7.1`).
    ///
    /// **It writes on a day nothing has been answered on, and that is the change `F-13` asked
    /// for** (`Q-18.8` at (a)). The guard here used to be `store.session != nil`, so the command
    /// did nothing on the day a lifter backdating last Thursday is actually looking at — and
    /// `DayView` hid it rather than draw a dead item. It is still not a Start: nothing is asked and
    /// nothing is begun, a date is recorded on the only row that can carry one.
    ///
    /// **Created *on* the chosen day rather than created and then moved.** ``startIfNeeded(on:)``
    /// takes the date, so the branch that has no session is one write — a create followed by a
    /// ``ActiveSessionStore/changeDate(to:)`` would restamp `updatedAt`, `G-2.4`'s conflict key,
    /// for a date the row never actually held.
    ///
    /// **A day with no routine to copy writes nothing**, which is ``startIfNeeded(on:)``'s own
    /// answer rather than a guard here: that is the state ``hasPlan`` keeps the command out of the
    /// menu for, and this is what makes the two agree if it ever does not.
    ///
    /// - Parameter day: The training day.
    public func changeDate(to day: Date) async {
        if store.session == nil {
            guard await startIfNeeded(on: day) else { return }
        } else {
            await store.changeDate(to: day)
        }
        await reload()
    }

    /// Throws the day's workout away (`FR-1.2.12`, `FR-17.9.7`).
    ///
    /// Soft, like every deletion here (`G-1.3`). The day goes back to being unstarted, which is what
    /// the re-read below draws.
    public func discard() async {
        await store.discard()
        await reload()
    }

    /// Creates the day's session if there is not one yet (`FR-17.9.5`).
    ///
    /// **Public because `+ Add exercise` needs it and is not an answer.** The picker is pushed above
    /// this screen and writes through the store, which refuses an entry with no workout held — so a
    /// day nobody has logged into has to acquire its session before the push rather than after the
    /// selection.
    ///
    /// - Returns: Whether a session is now held.
    @discardableResult
    public func startIfNeeded() async -> Bool {
        await startIfNeeded(on: .now)
    }

    /// ``startIfNeeded()``, on a training day that is not today (`FR-18.7.1`).
    ///
    /// **An overload rather than a defaulted parameter**, so that the date is never chosen by
    /// omission: every answer on this screen is given today and says so by calling the other one,
    /// and the one command that dates a workout it is creating says *that* by calling this one.
    ///
    /// - Parameter day: The training day the workout is created on. Normalised to its start by
    ///   ``ActiveSessionStore/start(on:)``.
    /// - Returns: Whether a session is now held.
    @discardableResult
    func startIfNeeded(on day: Date) async -> Bool {
        if store.session != nil { return true }
        guard let routineID else { return false }
        await store.start(
            on: day,
            fromRoutineID: routineID,
            in: routines,
            stampedWith: ProgramSessionStamp(runID: runID, weekNumber: week, dayIndex: dayIndex))
        return store.session != nil
    }

    /// Ends the day when its last row has been answered (`FR-17.9.8`).
    private func finishIfComplete() async {
        let entries = store.exercises
        guard !entries.isEmpty, entries.allSatisfy(\.entry.isMarkedDone) else { return }
        await store.endDay()
    }

    /// Re-reads what a command wrote.
    ///
    /// **The store's list, and nothing else** — ``rows`` and ``date`` are read through it, so a
    /// write here has one place to land rather than a second copy of the answer to keep in step.
    private func reload() async {
        await store.loadExercises()
    }

    /// The entry a row names, once the session exists.
    ///
    /// **A row drawn from the plan is mapped by position**, which is exactly what the copy did:
    /// `populate` writes one entry per slot in the routine's order, renumbered from zero. Mapping by
    /// exercise id would be wrong for a day that prescribes the same lift twice.
    ///
    /// - Parameter rowID: The row's identity — an entry's, or a slot's.
    /// - Returns: The entry, or `nil` where the row has none.
    private func entryID(forRow rowID: UUID) -> UUID? {
        if store.exercises.contains(where: { $0.id == rowID }) { return rowID }
        guard let index = planLines.firstIndex(where: { $0.id == rowID }),
            index < store.exercises.count
        else {
            return nil
        }
        return store.exercises[index].id
    }

    /// Reads the run, the day and the routine the route named.
    ///
    /// **The stamp is checked rather than merely carried.** A restored stack decodes a stamp that
    /// was current when it was written (`Route`'s header); without the check a day reopened after
    /// the week turned would draw the new week's plan under the old week's answers.
    ///
    /// - Throws: Whatever the repositories throw.
    private func readPlan() async throws {
        name = ""
        planLines = []
        routineID = nil
        weekDayID = nil
        guard let run = try await programs.currentRun(), run.id == runID, run.weekNumber == week
        else {
            return
        }
        let days = try await programs.days(forProgramID: run.programID, includingDeleted: false)
        guard let day = days.first(where: { $0.order == dayIndex }) else { return }
        // Before the routine, deliberately: a day whose routine has been archived is still a day
        // of the week, and the plan editor is where a lifter repoints it (`FR-18.7.2`).
        weekDayID = day.id
        guard let routine = try await routines.routine(id: day.routineID, includingDeleted: false)
        else {
            return
        }
        routineID = routine.id
        name = routine.name
        planLines = try await plans.plan(forRoutineID: routine.id)
    }
}
