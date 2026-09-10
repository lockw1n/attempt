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

/// Starting a program's next day (`FR-16.8.2`).
///
/// A file of its own beside `ActiveSessionRoutineStart.swift`, whose shape and reason it follows.
///
/// **Finishing a workout moves nothing here** (`D-17.10`). The day cursor is retired: a week ends
/// when every one of its days is answered, which is a question about the sessions rather than about
/// a number the finish had to remember to write — see ``WeekState/everyPlannedDayIsDone``.
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
}

extension ProgramRun {
    /// This run advanced to the next week (`FR-17.8.4`).
    ///
    /// **The same row rather than a closed run and a fresh one**: a run is one pass through a
    /// program and a week is where that pass has got to. What preserves the week a finished session
    /// belonged to is that session's own column (`FR-16.8.3`), written once at start and never
    /// again — not a second run row.
    ///
    /// **``RepositoryInterface/ProgramRun/nextDayIndex`` is carried across unchanged, and nothing
    /// writes it any more** (`D-17.10`, `TR-17.4`). The column stays in the schema and in the
    /// archive; writing it — even back to the value it already holds — would restamp `updatedAt`,
    /// which is `G-2.4`'s conflict key, and let a local no-op outrank a real remote edit.
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
            nextDayIndex: nextDayIndex)
    }
}
