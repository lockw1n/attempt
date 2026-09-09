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
        return store.exercises.map { Self.row($0, marks: marks) }
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

    /// The last write against the day that failed, as the error's description, or `nil`.
    ///
    /// A **diagnostic**, not copy (`G-3.4`). Read off the store, which is where the writes happen.
    public var writeFailure: String? { store.exercisesWriteFailure ?? store.failure }

    /// The run the route carried.
    private let runID: UUID

    /// The week the route carried.
    private let week: Int

    /// The workout the answers are written into.
    private let store: ActiveSessionStore

    /// The programs, their days and the run in force.
    private let programs: any ProgramRepository

    /// The routines the day names — read for its name, and handed to the start that copies it.
    private let routines: any RoutineRepository

    /// What the routine prescribes.
    private let plans: WeekPlanReader

    /// The plan as read, kept so a slot can be mapped onto the entry the copy wrote for it.
    private var planLines: [WeekPlanLine] = []

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
    /// - Parameter rowID: The row the circle was tapped on.
    public func answerAsPlanned(rowID: UUID) async {
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
    public func logRemainingAsPlanned() async {
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
    /// **A row already answered is rewritten rather than appended to** (`FR-17.7.5`). Reopening the
    /// sheet over an answer is the *only* way to change one — the circle is inert by then — so a
    /// save that appended would double the work every time a lifter corrected a rep count.
    ///
    /// - Parameters:
    ///   - rowID: The row being logged against.
    ///   - group: What the sheet collected — the form's answer and the rows it writes.
    func log(rowID: UUID, group: ResolvedSetGroup) async {
        unanswerable = []
        guard await startIfNeeded(), let entryID = entryID(forRow: rowID) else { return }
        // Asked about the *entry*, never about `rowID`. A day with no session draws the routine's
        // slots and a day with one draws its entries, so the identity the sheet was opened on is
        // one `rows` no longer holds the moment the first answer creates the session — and a
        // lookup by it finds nothing on the commonest save there is. ``entryID(forRow:)`` is the
        // translation, and after ``startIfNeeded()`` its answer is always an identity `rows` has.
        if isAnswered(rowID: entryID) {
            await store.rewriteGroup(inEntryID: entryID, rows: group.rows)
        } else {
            await store.logGroup(inEntryID: entryID, rows: group.rows)
        }
        await finishIfComplete()
        await reload()
    }

    /// What the Log sheet opens over `rowID` (`FR-17.9.4`, `FR-17.7.5`).
    ///
    /// **The plan and what is stored** — the two things the sheet needs and the one place they are
    /// read together. Composed here rather than on the screen for ``seed(forRow:)``'s reason: the
    /// mapping from a row to its entry is this store's.
    ///
    /// Whether the row is answered is *not* carried: that decides the write rather than the form,
    /// and it is read at the moment of writing — see ``isAnswered(rowID:)``.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The row, or `nil` where the day has none by that identity.
    func editorRow(forRow rowID: UUID) -> SetEditorRow? {
        guard let row = rows.first(where: { $0.id == rowID }) else { return nil }
        return SetEditorRow(
            plan: row.plan,
            logged: store.exercises.first { $0.id == rowID }?.sets ?? [])
    }

    /// Whether the row has already been answered — what decides between a write and a rewrite.
    ///
    /// **A row the day does not hold is *not* answered**, and the default matters: written as a
    /// comparison against the optional, a missing row reads as answered and the save becomes a
    /// rewrite of a group nobody has logged. Appending is the safe answer to "I cannot tell" —
    /// it is what an unanswered row does, and it is the only one of the two that cannot
    /// soft-delete a set the lifter has.
    ///
    /// **It answers about whatever identity ``rows`` is currently keyed by**, which is the routine's
    /// slots before the day has a session and the entries after — so a caller holding a row id from
    /// before ``startIfNeeded()`` has to translate it through ``entryID(forRow:)`` first. Internal
    /// rather than private so both halves of that can be asserted.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: Whether it carries an answer.
    func isAnswered(rowID: UUID) -> Bool {
        guard let row = rows.first(where: { $0.id == rowID }) else { return false }
        return row.answer != .unanswered
    }

    /// What the editor opens filled in with for `rowID` (`FR-15.2.3`), or `nil` where nothing was
    /// planned for it.
    ///
    /// **The session's own plan once there is one, the routine's before that.** They are the same
    /// numbers on a day nobody has logged into; once sets exist, only the first knows which planned
    /// group the next set falls in.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The seed, or `nil`.
    public func seed(forRow rowID: UUID) -> PlannedSetSeed? {
        if let exercise = store.exercises.first(where: { $0.id == rowID }) {
            return exercise.plannedSeed
        }
        guard let target = planLines.first(where: { $0.id == rowID })?.targets.first else {
            return nil
        }
        return PlannedSetSeed(weight: target.weight, reps: target.reps)
    }

    /// What the routine prescribed for the next set of `rowID`, drawn above the editor's fields
    /// (`FR-15.3.1`), or `nil`.
    ///
    /// Only where the session exists: the line reports a *group*, and a day not yet started has
    /// none of its own to report.
    ///
    /// - Parameter rowID: The row.
    /// - Returns: The group, or `nil`.
    public func prescribed(forRow rowID: UUID) -> PlannedTargetGroup? {
        store.exercises.first { $0.id == rowID }?.nextPlannedGroup
    }

    /// Moves the day's session to another training day (`FR-1.2.1`, `FR-17.9.7`).
    ///
    /// Nothing is written before there is a session: a day nobody has logged into has no date to
    /// change, and inventing one would create the workout from the menu.
    ///
    /// - Parameter day: The training day.
    public func changeDate(to day: Date) async {
        guard store.session != nil else { return }
        await store.changeDate(to: day)
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
        if store.session != nil { return true }
        guard let routineID else { return false }
        await store.start(
            on: .now,
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

    /// One row, from the session's exercise.
    ///
    /// - Parameters:
    ///   - exercise: The entry, its catalogue row, its sets and its planned targets.
    ///   - marks: Which of the workout's sets hold a record (`FR-1.6.3`) — read once per rebuild
    ///     rather than per row, the store having already resolved it inside `loadExercises()`.
    /// - Returns: The row.
    private static func row(_ exercise: SessionExercise, marks: SessionRecordMarks) -> DayRow {
        let performed = DayPerformance.runs(of: exercise.sets)
        return DayRow(
            id: exercise.id,
            exercise: exercise.exercise,
            plan: exercise.planned.map {
                WeekPlanTarget(
                    id: $0.id, weight: $0.targetWeight, reps: $0.targetReps, sets: $0.targetSets)
            },
            performed: performed,
            answer: answer(marked: exercise.entry.isMarkedDone, performed: performed),
            // The runs' own identifiers, which are their first sets' — the identifier the cache
            // names a run by.
            records: performed.flatMap { marks.schemes(forSetID: $0.id) })
    }

    /// What a row has been answered with (`FR-17.9.6`).
    ///
    /// **Skipped is derived** — marked done with no completed working set — which is `TR-17.4`.
    ///
    /// - Parameters:
    ///   - marked: Whether the entry carries the lifter's check-off.
    ///   - performed: The working sets, encoded.
    /// - Returns: The answer.
    private static func answer(marked: Bool, performed: [WeekPlanTarget]) -> DayRowAnswer {
        guard marked else { return .unanswered }
        return performed.isEmpty ? .skipped : .logged
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
        guard let run = try await programs.currentRun(), run.id == runID, run.weekNumber == week
        else {
            return
        }
        let days = try await programs.days(forProgramID: run.programID, includingDeleted: false)
        guard let day = days.first(where: { $0.order == dayIndex }) else { return }
        guard let routine = try await routines.routine(id: day.routineID, includingDeleted: false)
        else {
            return
        }
        routineID = routine.id
        name = routine.name
        planLines = try await plans.plan(forRoutineID: routine.id)
    }
}
