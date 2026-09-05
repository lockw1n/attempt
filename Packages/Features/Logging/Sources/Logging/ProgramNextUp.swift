import Foundation
import RepositoryInterface

/// The program in force, as Train's root draws it (`FR-16.8.2`).
///
/// **A value the screen can be tested over.** `TR-1.12`'s harness cannot run the read that fills
/// it, so a reference over the card is a reference over whatever this says — which is also what
/// makes the four answers below assertable without a store behind them.
public struct ProgramNextUp: Equatable, Sendable {
    /// The run this describes — what a workout started from here is stamped with (`FR-16.8.3`).
    public let runID: UUID

    /// The program's own name, as the lifter titled it.
    public let programName: String

    /// The week the run is on — the `#N` of a plan file, not an index.
    public let weekNumber: Int

    /// What comes next in that week.
    public let day: Day

    /// Builds the reading.
    public init(runID: UUID, programName: String, weekNumber: Int, day: Day) {
        self.runID = runID
        self.programName = programName
        self.weekNumber = weekNumber
        self.day = day
    }

    /// What the run's cursor is pointing at (`FR-16.8.2`, `FR-16.8.4`).
    ///
    /// **Four answers rather than an optional day, because three of them are different screens.**
    /// A day that can be started, a day whose routine has been archived, a week that is over and a
    /// program with nothing in it each need their own sentence — and collapsed into `nil` the last
    /// three would share the first's **Start**, which would be a button over nothing to train.
    public enum Day: Equatable, Sendable {
        /// The day to train next: its position, the routine it names, and that routine's name.
        case next(index: Int, routineID: UUID, name: String)

        /// The day to train next names a routine that has been archived (`FR-15.2.5`).
        ///
        /// **The resolution of the dangling half a program day is allowed to carry.**
        /// ``RepositoryInterface/ProgramRepository/days(forProgramID:includingDeleted:)`` returns
        /// the row intact rather than dropping it, on the argument that refusing there would cost
        /// the lifter the whole program for one archived routine — so the day arrives here and this
        /// is where it is answered. **Skip day** is what gets past it; the way to fix it is the
        /// editor.
        case archivedRoutine(index: Int)

        /// Every day of the week has been trained or skipped — `FR-16.8.4`'s offer.
        case weekComplete

        /// The program has no days at all, so there is nothing to start.
        case noDays
    }
}

/// Why the program's cursor did not move (`FR-16.8.4`).
///
/// **Two cases rather than one, because they name different commands.** A lifter who skipped a day
/// and a lifter who asked for next week are owed the sentence for the thing they tapped; one shared
/// wording would tell them the other command failed.
public enum ProgramCommandFailure: Sendable, Equatable {
    /// **Skip day** wrote nothing.
    case skipFailed

    /// **Start next week** wrote nothing. Whatever it had already written has been taken back out.
    case nextWeekFailed
}

/// Train's reading of the program in force, and the two commands that move it (`FR-16.8.2`,
/// `FR-16.8.4`).
///
/// **Screen-lifetime, like `RoutineListState`**: nothing here outlives Train's root, and the one
/// thing that does — the workout a **Start** creates — is ``ActiveSessionStore``'s.
@Observable
public final class ProgramNextUpState {
    /// What the card has to show, as one value rather than three flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The read answered, with ``ProgramNextUpState/nextUp`` or without one.
        case ready

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The program in force, or `nil` where the lifter is running none.
    ///
    /// **`nil` is the ordinary case and draws nothing**, unlike every other screen's empty state:
    /// Train's root is a workout surface, and a lifter with no program is not missing one.
    public private(set) var nextUp: ProgramNextUp?

    /// Why the last **Skip day** or **Start next week** changed nothing, or `nil`.
    ///
    /// Cleared by every fresh read, on `RoutineListState.startFailure`'s rule: a read that
    /// succeeds retires a claim about a write that failed.
    ///
    /// Settable across the module rather than only within this file, because `FR-16.8.4`'s command
    /// lives in `ProgramNextWeek.swift` — `private` is file-scoped and this type is two files.
    public internal(set) var commandFailure: ProgramCommandFailure?

    /// The programs, their days and the run in force.
    let programs: any ProgramRepository

    /// The routines a program day names — read for the day's name, and written by
    /// ``startNextWeek()``.
    let routines: any RoutineRepository

    /// The sessions a week's plan is rebuilt from (`FR-16.8.4`).
    let workouts: any WorkoutRepository

    /// Builds the reading over the three repositories a program's next day is assembled from.
    ///
    /// - Parameters:
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routines those days name.
    ///   - workouts: The sessions **Start next week** reads back.
    public init(
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository
    ) {
        self.programs = programs
        self.routines = routines
        self.workouts = workouts
    }

    /// Reads the run in force and what it is pointing at, on every appearance.
    ///
    /// **Re-entrant through ``Phase/ready``**, on `RoutineListState.load()`'s rule: the workout
    /// finished on the screen pushed over this one is what moves the cursor, so the card has to be
    /// right on the way back.
    ///
    /// **The day is found by ``RepositoryInterface/ProgramDay/order``, not by position.** The cursor
    /// is an order and a soft-deleted day leaves a gap in them, so the day to train is the first one
    /// at or past the cursor — which is also what makes a deleted last day read as a finished week
    /// rather than as an index out of range.
    public func load() async {
        if phase == .loading { return }
        phase = .loading
        commandFailure = nil
        do {
            nextUp = try await read()
            phase = .ready
        } catch {
            nextUp = nil
            phase = .failed(String(describing: error))
        }
    }

    /// One read of the run in force. See ``load()``.
    ///
    /// - Returns: What Train draws, or `nil` where no run is open or its program has gone.
    /// - Throws: Whatever the repositories throw.
    private func read() async throws -> ProgramNextUp? {
        guard let run = try await programs.currentRun(),
            let program = try await programs.program(id: run.programID, includingDeleted: false)
        else {
            return nil
        }
        let days = try await programs.days(forProgramID: run.programID, includingDeleted: false)
        return ProgramNextUp(
            runID: run.id,
            programName: program.name,
            weekNumber: run.weekNumber,
            day: try await day(at: run.nextDayIndex, among: days))
    }

    /// Which of the four answers the cursor lands on.
    ///
    /// - Parameters:
    ///   - cursor: ``RepositoryInterface/ProgramRun/nextDayIndex``.
    ///   - days: The program's days, in order.
    /// - Returns: The reading.
    /// - Throws: Whatever the routine read throws.
    private func day(at cursor: Int, among days: [ProgramDay]) async throws -> ProgramNextUp.Day {
        guard !days.isEmpty else { return .noDays }
        guard let day = days.first(where: { $0.order >= cursor }) else { return .weekComplete }
        guard let routine = try await routines.routine(id: day.routineID, includingDeleted: false)
        else {
            return .archivedRoutine(index: day.order)
        }
        return .next(index: day.order, routineID: day.routineID, name: routine.name)
    }

    /// Moves the cursor past `index` without logging anything (`FR-16.8.4`).
    ///
    /// **A day skipped writes no session**, which is what makes it a skip: the week's rebuild reads
    /// the sessions it finds, so a day with none keeps the routine it already has rather than
    /// becoming an empty plan — see ``startNextWeek()``.
    ///
    /// - Parameter index: The ``RepositoryInterface/ProgramDay/order`` being skipped.
    public func skipDay(at index: Int) async {
        do {
            guard let run = try await programs.currentRun(), run.nextDayIndex <= index else {
                await load()
                return
            }
            try await programs.save(run.movedTo(nextDayIndex: index + 1))
        } catch {
            commandFailure = .skipFailed
            return
        }
        await load()
    }
}
