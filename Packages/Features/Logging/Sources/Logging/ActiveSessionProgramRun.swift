import Foundation
import RepositoryInterface

/// Which pass through a program, which week of it and which day a session was started from
/// (`FR-16.8.3`).
///
/// **Three values that are written together and never apart.** They are `nil` together on every
/// workout started outside a program, and a row carrying one without the others describes a week
/// nothing can be resolved against — so they travel as one value rather than as three parameters a
/// caller could half-fill.
public struct ProgramSessionStamp: Equatable, Sendable {
    /// The ``RepositoryInterface/ProgramRun`` this workout belongs to.
    public let runID: UUID

    /// The week that run was on when the workout was started.
    public let weekNumber: Int

    /// The ``RepositoryInterface/ProgramDay/order`` it was started from.
    public let dayIndex: Int

    /// Builds the stamp.
    public init(runID: UUID, weekNumber: Int, dayIndex: Int) {
        self.runID = runID
        self.weekNumber = weekNumber
        self.dayIndex = dayIndex
    }
}

/// Starting a program's next day, and moving the cursor on when it is over (`FR-16.8.2`,
/// `FR-16.8.4`).
///
/// A file of its own beside `ActiveSessionRoutineStart.swift`, whose shape and reason it follows.
extension ActiveSessionStore {
    /// Starts the program's day and opens it (`FR-16.8.2`, `NFR-15.3`).
    ///
    /// **A routine start with a stamp, and nothing else.** A program day names a routine
    /// (`FR-16.8.1`), so the exercises and their targets arrive by `FR-15.2.3`'s own path — which
    /// is what keeps `TR-15.3`'s copy rule true of a program's workouts as well: the loads are
    /// snapshotted at start, and a program edited tomorrow does not rewrite what was lifted today.
    ///
    /// - Parameters:
    ///   - day: The training day the new workout belongs to.
    ///   - stamp: The run, week and day index it is started from — one value rather than three
    ///     parameters, for ``ProgramSessionStamp``'s reason.
    ///   - routineID: The routine that day names.
    ///   - routines: Where that routine is read from — a parameter, for
    ///     ``start(on:fromRoutineID:in:)``'s reason.
    /// - Returns: Whether a workout is now in progress.
    @discardableResult
    public func start(
        on day: Date,
        in stamp: ProgramSessionStamp,
        fromRoutineID routineID: UUID,
        using routines: any RoutineRepository
    ) async -> Bool {
        await start(on: day, fromRoutineID: routineID, in: routines, stampedWith: stamp)
    }

    /// Moves the run's cursor past the day the workout just finished belonged to (`FR-16.8.4`).
    ///
    /// **`save(_:)`, never `startRun(_:)`.** The second closes every other open run at the incoming
    /// `startedAt`, which is the invariant a *new* pass needs and exactly wrong for one in progress
    /// — see `ProgramRepository`'s own two doc comments.
    ///
    /// **The cursor only ever moves forward, and never past a day the run is already beyond.** A
    /// workout backdated into a week the lifter has since advanced out of, or a second session
    /// logged against a day already finished, would otherwise drag the plan backwards or skip a day
    /// nobody trained. `nextDayIndex` is a ``RepositoryInterface/ProgramDay/order`` rather than a
    /// count, so "past this day" is that order plus one whatever the day's position in the list.
    ///
    /// **A run that has been closed or deleted is not advanced and is not a failure**: the lifter
    /// finished a workout belonging to a pass they have since ended, which is a fact about the
    /// session rather than something the program still has to answer.
    ///
    /// - Parameter session: The workout that has just been finished.
    func advanceProgramRun(after session: WorkoutSession) async {
        guard let runID = session.programRunID, let dayIndex = session.dayIndex else { return }
        do {
            guard let run = try await programs.run(id: runID, includingDeleted: false), run.isOpen,
                run.nextDayIndex <= dayIndex
            else {
                programAdvanceFailure = nil
                return
            }
            try await programs.save(run.movedTo(nextDayIndex: dayIndex + 1))
            programAdvanceFailure = nil
        } catch {
            // The workout is finished and stored either way. What is left undone is the cursor,
            // and the screen that draws the next day is where that is reported and retried.
            programAdvanceFailure = String(describing: error)
        }
    }
}

extension ProgramRun {
    /// This run with its day cursor moved and every other column untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties; the three
    /// timestamps are carried across because the write path is an upsert that stamps `updatedAt`
    /// itself.
    ///
    /// - Parameter nextDayIndex: The ``RepositoryInterface/ProgramDay/order`` to train next.
    /// - Returns: The record to store.
    func movedTo(nextDayIndex: Int) -> ProgramRun {
        ProgramRun(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            startedAt: startedAt,
            endedAt: endedAt,
            weekNumber: weekNumber,
            nextDayIndex: nextDayIndex)
    }

    /// This run advanced to the next week, its day cursor back at the first day (`FR-16.8.4`).
    ///
    /// **The same row rather than a closed run and a fresh one**, which is what
    /// ``RepositoryInterface/ProgramRun/nextDayIndex`` and
    /// ``RepositoryInterface/ProgramRun/weekNumber`` moving independently already says: a run is one
    /// pass through a program and a week is where that pass has got to. What preserves the week a
    /// finished session belonged to is that session's own column (`FR-16.8.3`), written once at
    /// start and never again — not a second run row.
    ///
    /// - Returns: The record to store.
    func advancedToNextWeek() -> ProgramRun {
        ProgramRun(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            startedAt: startedAt,
            endedAt: endedAt,
            weekNumber: weekNumber + 1,
            nextDayIndex: 0)
    }
}

extension WorkoutSession {
    /// Which week and day of a program this session was started from, or `nil` where it was not
    /// started from one (`FR-16.8.3`).
    ///
    /// **Both columns or neither.** They are written together at start and a row carrying one
    /// without the other describes a position nothing can be drawn from — see
    /// ``Logging/ProgramSessionStamp``. The day is returned counted from one, which is how a lifter reads
    /// it and what every caller here wants.
    var programPosition: (week: Int, day: Int)? {
        guard let weekNumber, let dayIndex else { return nil }
        return (weekNumber, dayIndex + 1)
    }
}
