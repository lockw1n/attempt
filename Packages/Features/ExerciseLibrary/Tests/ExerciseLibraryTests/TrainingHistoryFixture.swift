import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import ExerciseLibrary

/// A store with a catalogue and a training history in it, written through the real fakes.
///
/// A class rather than a struct so the day arithmetic and the running order counters have one home
/// across a test's several writes.
@MainActor
final class TrainingHistory {
    let stack = InMemoryRepositoryStack()

    var workouts: any WorkoutRepository { stack.workouts }
    var settings: any SettingsRepository { stack.settings }

    /// Day zero, and the base every fixture date is an offset from — a fixed instant, so nothing
    /// here depends on when the suite runs.
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    /// The training day `offset` days after day zero.
    func day(_ offset: Int) -> Date {
        epoch.addingTimeInterval(Double(offset) * 86_400)
    }

    /// The state under test, over this store.
    func history(of exercise: Exercise) -> ExerciseHistoryState {
        ExerciseHistoryState(exerciseID: exercise.id, workouts: workouts, settings: settings)
    }

    /// The recompute actor over this store (`TR-1.6`).
    ///
    /// Built on demand rather than stored, and a test that needs the *same* one twice holds it
    /// itself: two actors over one store compute the same numbers, but only one of them announces to
    /// a given subscriber.
    ///
    /// **"Now" is day zero unless a test says otherwise**, and it has to be pinned: `FR-1.7.1`'s
    /// window is measured from it, and these fixtures are dated from a fixed epoch — left at the
    /// real clock, every one of them would fall outside the ninety days and every estimate would be
    /// absent for a reason no test intended. The window has no ceiling, so a later training day is
    /// still inside it.
    func recomputer(
        cache: (any PersonalRecordCacheRepository)? = nil,
        formula: E1RMFormulaID = .defaultFormula,
        lookback: E1RMLookback = .default,
        now: Date? = nil
    ) -> PersonalRecordRecomputer {
        let instant = now ?? day(0)
        return PersonalRecordRecomputer(
            workouts: workouts,
            cache: cache ?? stack.personalRecords,
            formula: formula,
            lookback: lookback,
            now: { instant })
    }

    /// `FR-1.6.2`'s state, over this store.
    func records(
        of exercise: Exercise, through recomputer: PersonalRecordRecomputer
    ) -> ExerciseRecordsState {
        ExerciseRecordsState(exerciseID: exercise.id, recomputer: recomputer)
    }

    /// A training day whose sets each carry their own load — what a rep-max fixture needs and
    /// ``train(_:onDay:reps:)``, which logs everything at one weight, cannot express.
    ///
    /// - Parameters:
    ///   - exercise: The exercise trained.
    ///   - offset: Which training day.
    ///   - work: The sets, as `(reps, kilos)` in the order performed.
    ///   - isWarmup: Whether the whole day is warmup work — the case that has sets and no records.
    /// - Returns: The session, so a test can assert which one a record links to.
    @discardableResult
    func trainWeighted(
        _ exercise: Exercise,
        onDay offset: Int,
        work: [(reps: Int, kilos: Int)],
        isWarmup: Bool = false
    ) async throws -> WorkoutSession {
        let session = try await session(onDay: offset)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: epoch,
            updatedAt: epoch,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise.id,
            order: 0,
            notes: ""
        )
        try await stack.workouts.save(entry)
        for (position, set) in work.enumerated() {
            try await stack.workouts.save(
                Builder.set(
                    entryID: entry.id,
                    order: position,
                    reps: set.reps,
                    rpe: nil,
                    stamp: epoch,
                    grams: set.kilos * 1000,
                    isWarmup: isWarmup
                )
            )
        }
        return session
    }

    /// Puts one exercise in the catalogue.
    func exercise(named name: String) async throws -> Exercise {
        let exercise = Builder.exercise(name: name, stamp: epoch)
        try await stack.exercises.save(exercise)
        return exercise
    }

    /// Sets the unit loads are shown in.
    func useUnit(_ unit: MassUnit) async throws {
        let current = try await stack.settings.settings()
        try await stack.settings.save(
            UserSettings(
                id: current.id,
                createdAt: current.createdAt,
                updatedAt: current.updatedAt,
                deletedAt: nil,
                userID: current.userID,
                displayUnit: unit,
                e1RMFormula: current.e1RMFormula,
                theme: current.theme,
                defaultRoundingIncrement: current.defaultRoundingIncrement,
                defaultRoundingStrategy: current.defaultRoundingStrategy
            )
        )
    }

    /// An empty workout on a training day.
    ///
    /// The identifier is a parameter because it is the last key the session ordering falls back to,
    /// so a test about that ordering has to control it rather than draw it.
    func session(
        id: UUID = UUID(),
        onDay offset: Int,
        startedAt: Date? = nil
    ) async throws -> WorkoutSession {
        let session = Builder.session(id: id, date: day(offset), startedAt: startedAt)
        try await stack.workouts.save(session)
        return session
    }

    /// One exercise's place in a workout, and the sets logged against it.
    func perform(
        _ exercise: Exercise,
        in session: WorkoutSession,
        order: Int,
        reps: [Int],
        rpe: [Double?]? = nil
    ) async throws {
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: epoch,
            updatedAt: epoch,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exercise.id,
            order: order,
            notes: ""
        )
        try await stack.workouts.save(entry)
        for (position, count) in reps.enumerated() {
            try await stack.workouts.save(
                Builder.set(
                    entryID: entry.id,
                    order: position,
                    reps: count,
                    rpe: rpe?[position],
                    stamp: epoch
                )
            )
        }
    }

    /// A whole training day in one call: a workout, one entry, and its sets.
    func train(_ exercise: Exercise, onDay offset: Int, reps: [Int]) async throws {
        let session = try await session(onDay: offset)
        try await perform(exercise, in: session, order: 0, reps: reps)
    }

    /// Work whose session is soft-deleted while its entry and sets stay live.
    ///
    /// The shape the cascade forbids and a restored backup can still produce (`G-2.5`), so the
    /// writes are in that order deliberately: `deleteSession` cascades into the entries it finds,
    /// and the entry therefore has to arrive after the delete rather than before it.
    func strandedWork(_ exercise: Exercise, onDay offset: Int, reps: [Int]) async throws {
        let session = try await session(onDay: offset)
        try await stack.workouts.deleteSession(id: session.id)
        try await perform(exercise, in: session, order: 0, reps: reps)
    }
}

/// The three records these tests write, built once so a field nobody asserts is not spelled out at
/// every call site.
enum Builder {
    static func exercise(name: String, stamp: Date) -> Exercise {
        Exercise(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            name: name,
            movement: .squat,
            parentExerciseID: nil,
            equipment: .barbell,
            laterality: .bilateral,
            barType: .standard,
            implementCount: 1,
            isCustom: false,
            isArchived: false,
            notes: ""
        )
    }

    /// A workout on `date`.
    ///
    /// **`createdAt` is deliberately not `date`.** A session's date is the training day and
    /// `createdAt` is when the row was written; equal, they make a reader that confused the two
    /// indistinguishable from one that did not.
    static func session(id: UUID, date: Date, startedAt: Date? = nil) -> WorkoutSession {
        let written = date.addingTimeInterval(86_400)
        return WorkoutSession(
            id: id,
            createdAt: written,
            updatedAt: written,
            deletedAt: nil,
            date: date,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
    }

    static func set(
        entryID: UUID,
        order: Int,
        reps: Int,
        rpe: Double?,
        stamp: Date,
        grams: Int = 100_000,
        isWarmup: Bool = false
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: Weight(grams: grams),
            reps: reps,
            rpe: rpe,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: nil
        )
    }
}
