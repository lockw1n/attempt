import Foundation
import PowerliftingCore
import RepositoryInterface

/// One target group of a day's plan, as the week's card draws it (`FR-17.8.1`).
///
/// A value rather than the record, for ``SessionExercise``'s reason: the card is what a snapshot
/// renders, and a card that read its own rows would render as whatever it held before the read.
public struct WeekPlanTarget: Identifiable, Equatable, Sendable {
    /// The ``RepositoryInterface/RoutineTargetGroup`` this describes.
    public let id: UUID

    /// The load on one implement, or `nil` where the plan named none (`FR-15.2.2`).
    public let weight: Weight?

    /// Reps prescribed per set.
    public let reps: Int

    /// Sets prescribed.
    public let sets: Int

    /// Builds the target.
    public init(id: UUID, weight: Weight?, reps: Int, sets: Int) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.sets = sets
    }
}

/// One exercise of a day's plan, with what the routine prescribes for it.
public struct WeekPlanLine: Identifiable, Equatable, Sendable {
    /// The ``RepositoryInterface/RoutineExercise`` slot this describes.
    public let id: UUID

    /// The catalogue row the slot names, or `nil` where it no longer has one.
    ///
    /// **Carried whole rather than as a name**, on ``SessionExercise/exercise``'s rule: which of an
    /// exercise's two names reads is the locale's question, and a state has no locale.
    public let exercise: Exercise?

    /// What the routine prescribes, in ``RepositoryInterface/RoutineTargetGroup/order``.
    public let targets: [WeekPlanTarget]

    /// Builds the line.
    public init(id: UUID, exercise: Exercise?, targets: [WeekPlanTarget]) {
        self.id = id
        self.exercise = exercise
        self.targets = targets
    }
}

/// Where one day of the week has got to (`FR-17.8.1`, `FR-17.8.2`).
///
/// **Three answers, and the third carries a date rather than a flag**: a done card collapses to
/// `Done · Mon 7 Sep`, so the day it was trained on is the only thing left of it on the screen.
public enum WeekDayProgress: Equatable, Sendable {
    /// No session carries this day's index. Nothing has been written and nothing will be until the
    /// day is opened.
    case notStarted

    /// A session exists and not every exercise in it is answered.
    case inProgress(done: Int, of: Int)

    /// Every exercise in the day's session is answered, on the training day it was logged for.
    case done(on: Date)
}

/// One day of the current week, as the root draws it (`FR-17.8.1`).
public struct WeekDayCard: Identifiable, Equatable, Sendable {
    /// The ``RepositoryInterface/ProgramDay/order`` this card is for — the day's own index, and
    /// half of what ``AppNavigation/TrainingRoute/day(runID:week:dayIndex:)`` carries.
    ///
    /// **The order, not the position in the list.** A soft-deleted day leaves a gap in the orders,
    /// and a session is stamped with the order it was started from (`FR-16.8.3`).
    public let dayIndex: Int

    /// The routine's name, or empty where that routine has been archived (`FR-15.2.5`).
    ///
    /// **A nameless card is still a card.** The day is part of the week whether or not the routine
    /// behind it survives, and sweeping it would silently shorten the plan.
    public let name: String

    /// The day's exercises with their plan. Empty where the routine is gone.
    public let plan: [WeekPlanLine]

    /// Where the day has got to.
    public let progress: WeekDayProgress

    /// The day's index is its identity within a week.
    public var id: Int { dayIndex }

    /// Builds the card.
    public init(dayIndex: Int, name: String, plan: [WeekPlanLine], progress: WeekDayProgress) {
        self.dayIndex = dayIndex
        self.name = name
        self.plan = plan
        self.progress = progress
    }
}

/// The workout in progress that no program started, as a card after the plan's days (`FR-17.8.3`).
///
/// **Only an in-progress one, which is `Q-17.5`'s refinement.** Resume has left the root and a
/// lifter mid-workout needs a way back; a finished free workout belongs to History, and the week
/// has no dates to file it under (`FR-16.8.5`).
public struct FreeWorkoutCard: Equatable, Sendable {
    /// The training day it belongs to.
    public let date: Date

    /// Builds the card.
    public init(date: Date) {
        self.date = date
    }
}

/// The current week, or the absence of one (`FR-17.8.1`, `FR-17.8.5`).
public enum WeekReading: Equatable, Sendable {
    /// No run is open, so there is no week — `FR-1.13.2`'s empty state.
    case empty

    /// The run in force: the program's name, the week it is on, and its days in order.
    case week(runID: UUID, programName: String, weekNumber: Int, days: [WeekDayCard])
}

/// Train's root: this week (`FR-17.8.1`, `TR-17.5`).
///
/// **Screen-lifetime**, like the reading it replaces: nothing here outlives the root, and the one
/// thing that does — the workout being logged — is ``ActiveSessionStore``'s.
///
/// **It walks no set history** (`NFR-17.4`). A day's state is the sessions stamped with its index
/// and their entries' done marks, so the launch tab costs the plan plus one query however many
/// years of training are behind it.
@Observable
public final class WeekState {
    /// What the screen has to show, as one value rather than three flags.
    public enum Phase: Sendable, Equatable {
        /// Nothing has been read yet.
        case idle

        /// A read is in flight.
        case loading

        /// The read answered, with ``WeekState/reading``.
        case ready

        /// The read failed, carrying the error's description — a diagnostic, not copy (`G-3.4`).
        case failed(String)
    }

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The week, or ``WeekReading/empty`` where no run is open.
    public private(set) var reading: WeekReading = .empty

    /// The exercises each started day has marked done, keyed by
    /// ``RepositoryInterface/ProgramDay/order`` (`FR-15.3.4`).
    ///
    /// **Recorded on the way past rather than read again.** The entries a day's progress is counted
    /// from are the entries a day's own screen ticks its rows off, so reading them twice would be
    /// one question with two answers as well as one query paid for twice.
    public private(set) var answered: [Int: Set<UUID>] = [:]

    /// Whether the last **Start next week** changed nothing (`FR-17.8.4`).
    ///
    /// **A flag rather than a diagnostic**, on the store's own split: the rollback means nothing
    /// was written, so what the lifter is owed is a sentence and another tap — the error itself is
    /// not theirs to read (`G-3.4`). Cleared by every fresh read.
    ///
    /// Settable across the module rather than only within this file, because the command lives in
    /// `ProgramNextWeek.swift` — `private` is file-scoped and this type is two files.
    public internal(set) var nextWeekFailed = false

    /// Whether the week is over, and therefore whether the root offers **Start next week**
    /// (`FR-17.8.4`, `D-17.8`).
    ///
    /// **Every planned day done, and at least one of them.** A day skipped whole counts as done —
    /// `FR-17.8.8`'s **Skip remaining** answers for its rows, which is what makes it done rather
    /// than a fourth state — and a day nothing has been logged into does not: the way past that one
    /// is to skip it from its own card, which is one confirmation (`Q-17.8`). A program with no
    /// days satisfies "every day is done" vacuously and is offered nothing.
    public var everyPlannedDayIsDone: Bool {
        guard case .week(_, _, _, let days) = reading, !days.isEmpty else { return false }
        return days.allSatisfy { if case .done = $0.progress { return true } else { return false } }
    }

    /// The free workout in progress, or `nil`.
    ///
    /// **Beside the reading rather than inside it**, because it is true of both: a lifter running
    /// no program can still have a workout open, and an empty state that hid it would strand them.
    public private(set) var freeWorkout: FreeWorkoutCard?

    /// The programs, their days and the run in force.
    let programs: any ProgramRepository

    /// The routines those days name, and the targets they prescribe.
    let routines: any RoutineRepository

    /// The sessions the week's state is read from (`TR-17.5`), and the targets their entries were
    /// planned against.
    ///
    /// **Both protocols, because `FR-17.8.6`'s copy needs the plan.** A skipped exercise carries
    /// its planned rows into next week (``SessionAsRoutine``), and those live in a table of their
    /// own — the cards themselves need only the sessions.
    let workouts: any WorkoutRepository & PlannedTargetRepository

    /// What a routine prescribes — shared with ``DayStore``, which reads the plan and nothing else.
    private let plans: WeekPlanReader

    /// Builds the reading over the four repositories a week is assembled from.
    ///
    /// - Parameters:
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routines those days name.
    ///   - workouts: The sessions stamped with the run and the week, and their planned targets.
    ///   - exercises: The catalogue the plan's slots name.
    public init(
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository & PlannedTargetRepository,
        exercises: any ExerciseRepository
    ) {
        self.programs = programs
        self.routines = routines
        self.workouts = workouts
        self.plans = WeekPlanReader(routines: routines, exercises: exercises)
    }

    /// Reads the week, on every appearance.
    ///
    /// **Re-entrant through ``Phase/ready``**: the day pushed over this one is what changes a
    /// card's state, so the week has to be right on the way back.
    ///
    /// - Parameter openSession: The workout in progress, or `nil` — ``ActiveSessionStore/session``.
    ///   **Passed in rather than read**, because the app has exactly one and the store already
    ///   holds it: a second query for it would be a second answer to a question `TR-1.2` gave the
    ///   store.
    public func load(openSession: WorkoutSession?) async {
        if phase == .loading { return }
        phase = .loading
        // FR-17.8.3, Q-17.5: only a workout no program started, and only while it is open.
        freeWorkout =
            openSession.flatMap {
                $0.programRunID == nil && $0.endedAt == nil ? FreeWorkoutCard(date: $0.date) : nil
            }
        do {
            plans.reset()
            answered = [:]
            nextWeekFailed = false
            reading = try await read()
            phase = .ready
        } catch {
            reading = .empty
            phase = .failed(String(describing: error))
        }
    }

    /// One read of the week. See ``load(openSession:)``.
    ///
    /// - Returns: The week, or ``WeekReading/empty``.
    /// - Throws: Whatever the repositories throw.
    private func read() async throws -> WeekReading {
        guard let run = try await programs.currentRun(),
            let program = try await programs.program(id: run.programID, includingDeleted: false)
        else {
            return .empty
        }
        let days = try await programs.days(forProgramID: run.programID, includingDeleted: false)
        // One query for the whole week, not one per day: the days are read off the sessions it
        // returns, which is what keeps the cost `NFR-17.4` describes independent of the plan's
        // length.
        let sessions = try await workouts.sessions(
            forProgramRunID: run.id, week: run.weekNumber, includingDeleted: false)
        var cards: [WeekDayCard] = []
        for day in days {
            cards.append(try await card(for: day, among: sessions))
        }
        return .week(
            runID: run.id,
            programName: program.name,
            weekNumber: run.weekNumber,
            days: cards)
    }

    /// One day's card: its name, its plan and where it has got to.
    ///
    /// - Parameters:
    ///   - day: The program day.
    ///   - sessions: Every session the week's query returned.
    /// - Returns: The card.
    /// - Throws: Whatever the repositories throw.
    private func card(
        for day: ProgramDay, among sessions: [WorkoutSession]
    ) async throws -> WeekDayCard {
        let routine = try await routines.routine(id: day.routineID, includingDeleted: false)
        // The query orders newest first, so the first row is the most recent workout stamped with
        // this day. One day is one session — a second is a row the app did not write — and the
        // newest is the one a lifter would open.
        let session = sessions.first { $0.dayIndex == day.order }
        return WeekDayCard(
            dayIndex: day.order,
            name: routine?.name ?? "",
            plan: routine == nil ? [] : try await plans.plan(forRoutineID: day.routineID),
            progress: try await progress(of: session, on: day.order))
    }

    /// Where a day has got to, from the session stamped with it (`FR-17.8.2`).
    ///
    /// **Done means every exercise in the session is answered, and an empty session is not done.**
    /// `FR-1.2.11` reads "when every exercise is answered", which a session with no entries
    /// satisfies vacuously — and a day drawn `Done` the instant it was opened would be a claim
    /// about a workout nobody logged. It reads `0 of 0` instead, which is the state it is in.
    ///
    /// - Parameters:
    ///   - session: The day's session, or `nil`.
    ///   - dayIndex: The day's order, which is the key ``answered`` files its exercises under.
    /// - Returns: The day's state.
    /// - Throws: Whatever the entry read throws.
    private func progress(
        of session: WorkoutSession?, on dayIndex: Int
    ) async throws -> WeekDayProgress {
        guard let session else { return .notStarted }
        let entries = try await workouts.entries(
            forSessionID: session.id, includingDeleted: false)
        let done = entries.filter(\.isMarkedDone)
        answered[dayIndex] = Set(done.map(\.exerciseID))
        guard !entries.isEmpty, done.count == entries.count else {
            return .inProgress(done: done.count, of: entries.count)
        }
        return .done(on: session.date)
    }

}
