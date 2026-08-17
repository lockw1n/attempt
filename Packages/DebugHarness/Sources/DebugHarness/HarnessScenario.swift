import Foundation
import PowerliftingCore
import RepositoryInterface
import SeedImport

/// Seeds the catalogue, logs a short history, and reads the records back out (`DOD-0.3`).
///
/// **It writes.** A run puts 116 catalogue rows and eight sets into whatever store it is handed, so
/// hand it a throwaway one — the executable opens an in-memory store for exactly that reason.
/// Running it twice against the same store logs the history twice; the seed half is a merge and
/// writes nothing the second time, which is the difference worth seeing in the output.
public struct HarnessScenario: Sendable {
    /// The catalogue name the fixed log is written against.
    public static let loggedExerciseName = DemonstrationLog.exerciseName

    private let exercises: any ExerciseRepository
    private let workouts: any WorkoutRepository
    private let formula: E1RMFormulaID
    private let exerciseName: String

    /// A run over two repositories.
    ///
    /// - Parameters:
    ///   - exercises: Where the seeded catalogue goes.
    ///   - workouts: Where the logged history goes.
    ///   - formula: The estimator the records are computed under, or `TR-0.2.5`'s default.
    ///   - exerciseName: The catalogue name to log against. A parameter only so a test can ask for
    ///     one that is not there.
    public init(
        exercises: any ExerciseRepository,
        workouts: any WorkoutRepository,
        formula: E1RMFormulaID = .defaultFormula,
        exerciseName: String = HarnessScenario.loggedExerciseName
    ) {
        self.exercises = exercises
        self.workouts = workouts
        self.formula = formula
        self.exerciseName = exerciseName
    }

    /// Runs the whole thing and reports what came back.
    ///
    /// - Parameter now: The instant the newer session is dated at; the older one is seven days
    ///   before it. Passed rather than read so a run is reproducible.
    /// - Returns: The seed's outcome, the sets as stored, and the records computed from them.
    /// - Throws: ``HarnessError/exerciseNotFound(name:)``, `SeedImportError` if the shipped
    ///   catalogue does not validate, a `RepositoryError` from a write, or a
    ///   `RecordProjectionError` if a row read back cannot be projected onto the domain type.
    public func run(at now: Date = Date()) async throws -> HarnessReport {
        let seed = try await SeedImporter(exercises: exercises).importBundledCatalogue(at: now)
        let exercise = try await namedExercise()
        for session in DemonstrationLog.sessions {
            try await log(session, against: exercise.id, at: now)
        }

        // The order this comes back in is the calculators' whole tie-break, so nothing here sorts
        // or filters it: `WorkoutRepository.sets(forExerciseID:includingDeleted:)` says the offsets
        // a `PersonalRecord` reports are offsets into exactly this collection.
        let stored = try await workouts.sets(forExerciseID: exercise.id, includingDeleted: false)
        let records = try stored.map { try $0.setRecord() }
        let calculator = PersonalRecordCalculator(formula)
        return HarnessReport(
            seed: seed,
            exerciseName: exercise.name,
            formula: formula,
            sets: records.map { record in
                HarnessReport.LoggedSet(
                    weight: record.weight,
                    reps: record.reps,
                    rpe: record.rpe,
                    isWarmup: record.isWarmup,
                    isCompleted: record.isCompleted,
                    estimate: calculator.e1rm.estimate(for: record))
            },
            records: calculator.records(in: records))
    }

    /// The seeded exercise the log is written against.
    private func namedExercise() async throws -> Exercise {
        let catalogue = try await exercises.exercises(includingDeleted: false)
        guard let match = catalogue.first(where: { $0.name == exerciseName }) else {
            throw HarnessError.exerciseNotFound(name: exerciseName)
        }
        return match
    }

    /// Writes one session, its single exercise entry, and its sets.
    ///
    /// Session before entry before sets, because a repository refuses an entry naming a session
    /// that does not exist yet and a set naming an entry that does not.
    private func log(
        _ session: DemonstrationSession,
        against exerciseID: UUID,
        at now: Date
    ) async throws {
        let date = Date(timeInterval: -Double(session.daysAgo) * Self.secondsPerDay, since: now)
        let sessionID = UUID()
        let entryID = UUID()

        try await workouts.save(
            WorkoutSession(
                id: sessionID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                date: date,
                startedAt: date,
                endedAt: nil,
                notes: "",
                bodyweight: nil,
                programRunID: nil,
                scheduledWorkoutID: nil))
        try await workouts.save(
            ExerciseEntry(
                id: entryID,
                createdAt: date,
                updatedAt: date,
                deletedAt: nil,
                sessionID: sessionID,
                exerciseID: exerciseID,
                order: 0,
                notes: ""))
        for (order, set) in session.sets.enumerated() {
            try await workouts.save(set.stored(inEntry: entryID, order: order, at: date))
        }
    }

    /// One day, for dating the older session. `Calendar` would be the wrong instrument: the
    /// scenario wants two sessions in a known order, not a wall-clock date a reader will check.
    private static let secondsPerDay: Double = 24 * 60 * 60
}

extension DemonstrationSet {
    /// This set as the storage record for it.
    func stored(inEntry entryID: UUID, order: Int, at date: Date) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: Weight(grams: grams),
            reps: reps,
            rpe: rpe,
            rir: nil,
            isWarmup: isWarmup,
            isCompleted: isCompleted,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: isCompleted ? date : nil)
    }
}
