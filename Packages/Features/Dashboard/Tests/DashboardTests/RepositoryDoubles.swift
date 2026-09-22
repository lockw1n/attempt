import Foundation
import PowerliftingCore
import RepositoryInterface

/// A catalogue that refuses every read, for the error state (`FR-1.13.1`).
///
/// A double rather than a fake with a flag: the fakes in `RepositoryFakes` are the *contract*, and a
/// switch that makes one fail would make every test that shares them able to.
struct FailingExerciseRepository: ExerciseRepository {
    /// What every call throws.
    private let failure = RepositoryError.recordNotFound(id: UUID())

    func exercises(includingDeleted: Bool) async throws -> [Exercise] { throw failure }

    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { throw failure }

    func save(_ exercise: Exercise) async throws { throw failure }

    func trainingMax(
        forExerciseID exerciseID: UUID, on date: Date
    ) async throws -> TrainingMaxEntry? {
        throw failure
    }

    func trainingMaxHistory(
        forExerciseID exerciseID: UUID, includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        throw failure
    }

    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws { throw failure }
}

/// Sessions that refuse every read, for `FR-1.9.5`'s error state.
struct FailingWorkoutRepository: WorkoutRepository {
    /// What every call throws.
    private let failure = RepositoryError.recordNotFound(id: UUID())

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw failure
    }
    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw failure
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { throw failure }

    func save(_ session: WorkoutSession) async throws { throw failure }

    func deleteSession(id: UUID) async throws { throw failure }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        throw failure
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { throw failure }

    func save(_ entry: ExerciseEntry) async throws { throw failure }

    func deleteExerciseEntry(id: UUID) async throws { throw failure }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }

    func save(_ set: SetEntry) async throws { throw failure }

    func deleteSet(id: UUID) async throws { throw failure }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw failure
    }
}

/// A settings row that reads but refuses every write, for the failed-toggle diagnostic
/// (`FR-1.9.1`).
///
/// **It delegates the read** rather than answering a fixture of its own: the picker has to get as
/// far as drawing rows before a toggle can fail at all, so a double refusing both would only ever
/// reach the error state and never the one this is for.
struct ReadOnlySettingsRepository: SettingsRepository {
    /// Where the read is answered from.
    let stored: any SettingsRepository

    func settings() async throws -> UserSettings { try await stored.settings() }

    func save(_ settings: UserSettings) async throws {
        throw RepositoryError.recordNotFound(id: settings.id)
    }

    func restorePreferences(from backup: UserSettings) async throws {
        throw RepositoryError.recordNotFound(id: backup.id)
    }
}

/// Sessions that answer until told to stop, counting what was asked — for the stale-weeks case and
/// the one-pass claim.
///
/// An actor wrapping the fakes rather than a fake with a flag, on `SwitchableCache`'s rule: the
/// fakes in `RepositoryFakes` are the *contract*, and a switch that made one fail would make every
/// test that shares them able to.
actor SwitchableWorkouts: WorkoutRepository {
    /// Where a read that is not refusing is answered from.
    private let wrapped: any WorkoutRepository

    /// Whether every later call throws.
    private var isRefusing = false

    /// How many times the sessions were listed.
    private(set) var sessionReads = 0

    /// How many sessions had their entries read.
    private(set) var entryReads = 0

    /// What a refusal throws. The case does not matter — the state under test reports *that* a read
    /// failed, never which error it was.
    private var failure: RepositoryError { .recordNotFound(id: UUID()) }

    init(wrapping wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    /// Makes every later call throw.
    func refuse() {
        isRefusing = true
    }

    func sessions(
        forProgramRunID runID: UUID, week: Int, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sessions(forProgramRunID: runID, week: week, includingDeleted: includingDeleted)
    }
    func sessions(
        in range: ClosedRange<Date>, includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        guard !isRefusing else { throw failure }
        sessionReads += 1
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }

    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        guard !isRefusing else { throw failure }
        return try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }

    func save(_ session: WorkoutSession) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(session)
    }

    func deleteSession(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteSession(id: id)
    }

    func entries(
        forSessionID sessionID: UUID, includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        guard !isRefusing else { throw failure }
        entryReads += 1
        return try await wrapped.entries(
            forSessionID: sessionID, includingDeleted: includingDeleted)
    }

    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        guard !isRefusing else { throw failure }
        return try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }

    func save(_ entry: ExerciseEntry) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(entry)
    }

    func deleteExerciseEntry(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteExerciseEntry(id: id)
    }

    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }

    func save(_ set: SetEntry) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.save(set)
    }

    func deleteSet(id: UUID) async throws {
        guard !isRefusing else { throw failure }
        try await wrapped.deleteSet(id: id)
    }

    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        guard !isRefusing else { throw failure }
        return try await wrapped.sets(
            forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}
