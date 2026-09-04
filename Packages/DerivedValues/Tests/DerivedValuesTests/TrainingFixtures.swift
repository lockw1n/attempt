import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

/// One set as a fixture states it — the four columns the two calculators actually read.
///
/// A type rather than a tuple because the lint ceiling for a tuple is two, and naming the two `G-1.8`
/// flags is the better shape anyway: `(false, true)` at a call site says nothing.
struct LoggedSet {
    /// The load, in grams (`G-1.1`).
    let grams: Int

    /// The repetitions performed.
    let reps: Int

    /// Whether it was a warmup rather than working.
    let isWarmup: Bool

    /// Whether it was completed. `false` is `FR-1.2.5`'s failed set.
    let isCompleted: Bool
}

/// A store with a catalogue and a training history in it, built through the front door.
///
/// **Every row goes in through a repository**, so the fixtures cannot express a state the app could
/// not reach — a set with no entry, an entry with no session. That is also why the seeding is this
/// verbose: `save(_ entry:)` refuses a dangling reference, which is the point.
struct TrainingLog {
    /// The fakes everything here is written to and read from.
    let repositories = InMemoryRepositoryStack()

    /// Turns `FR-16.3`'s filters off, so a feed test asserts on the feed's own mechanics.
    ///
    /// **A fixture, not a default.** `FR-16.3.1` scopes a fresh row to the dashboard lifts and
    /// `FR-16.3.4` hides baselines, so an unconfigured store draws almost nothing here — every
    /// record a short fixture sets is the first of its scheme. A test about grouping, ordering or
    /// subscription says so by calling this; a test about the filters configures them itself.
    func showEveryRecord() async throws {
        var stored = try await repositories.settings.settings()
        stored.recentRecordsScope = .everyExercise
        stored.recentRecordsShowsBaselines = true
        try await repositories.settings.save(stored)
    }

    /// An exercise in the catalogue.
    @discardableResult
    func exercise(
        id: UUID = UUID(), named name: String = "Back Squat", ukrainian: String? = nil
    ) async throws -> UUID {
        try await repositories.exercises.save(
            Exercise(
                id: id,
                createdAt: .distantPast,
                updatedAt: .distantPast,
                deletedAt: nil,
                name: name,
                ukrainianName: ukrainian,
                movement: .squat,
                parentExerciseID: nil,
                equipment: .barbell,
                laterality: .bilateral,
                barType: .standard,
                implementCount: 1,
                isCustom: false,
                isArchived: false,
                notes: "",
                manualE1RM: nil))
        return id
    }

    /// One session, one entry for `exerciseID`, and the sets given — returns the entry's id.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise trained.
    ///   - date: The session's training day, which is what a record is dated by.
    ///   - sets: The sets, in the order they were performed.
    /// - Returns: The entry's id, which is what a set-change trigger is given.
    @discardableResult
    func session(
        of exerciseID: UUID,
        on date: Date,
        sets: [LoggedSet]
    ) async throws -> UUID {
        let sessionID = UUID()
        try await repositories.workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                date: date,
                startedAt: nil,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil))
        let entryID = UUID()
        try await repositories.workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: ""))
        for (order, set) in sets.enumerated() {
            try await repositories.workouts.save(
                setEntry(entryID: entryID, order: order, on: date, set))
        }
        return entryID
    }

    /// One logged set, with only the columns the calculators read varying.
    ///
    /// **The set's own timestamps are deliberately not its session's date**, and that is load-bearing
    /// rather than realism. `TR-0.3.9` dates a record from the session it was set in, and the set's
    /// `completedAt` is only the *fallback* for when that row cannot be read; a fixture that made the
    /// two equal cannot tell the rule from its fallback, and the test asserting the rule passes with
    /// the session dating removed altogether — measured.
    ///
    /// - Parameter rpe: Stored unvalidated, as the column is — which is how a row `SetRecord`
    ///   refuses is written through the front door.
    func setEntry(
        entryID: UUID,
        order: Int,
        on date: Date,
        id: UUID = UUID(),
        rpe: Double? = nil,
        _ set: LoggedSet
    ) -> SetEntry {
        let entered = date.addingTimeInterval(enteredLate)
        return SetEntry(
            id: id,
            createdAt: entered,
            updatedAt: entered,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: Weight(grams: set.grams),
            reps: set.reps,
            rpe: rpe,
            rir: nil,
            isWarmup: set.isWarmup,
            isCompleted: set.isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: entered)
    }
}

/// How long after its session a fixture's set claims to have been entered.
///
/// Any non-zero value works; a day and a half is chosen to be visibly not a rounding difference. See
/// ``TrainingLog/setEntry(entryID:order:on:id:rpe:_:)`` for why it must not be zero.
let enteredLate: TimeInterval = 36 * 3_600

/// A working set: the ordinary case, neither a warmup nor a failure.
func working(_ grams: Int, _ reps: Int) -> LoggedSet {
    LoggedSet(grams: grams, reps: reps, isWarmup: false, isCompleted: true)
}

/// The day every fixture is dated back from, and what a recomputer here is told "now" is.
///
/// A fixed instant rather than `Date.now`, so nothing drifts by run — and injected rather than
/// implied, because `FR-1.7.1`'s window is measured from it: left at the real clock, every fixture
/// date would fall years outside the ninety days and every estimate would be absent.
let fixtureNow = Date(timeIntervalSince1970: 1_700_000_000)

/// A fixed day, `weeks` before ``fixtureNow``.
func weeksAgo(_ weeks: Int) -> Date {
    fixtureNow.addingTimeInterval(-Double(weeks) * 7 * 86_400)
}
