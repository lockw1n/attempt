import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// The export screen's four states (`FR-1.11.1`, `FR-1.13.1`).
@MainActor
@Suite("Data export state")
struct DataExportStateTests {
    /// A state over one fixture's store, writing into a directory the test owns.
    static func state(
        _ log: ExportLog,
        in scratch: ScratchDirectory,
        settings: (any SettingsRepository)? = nil,
        now: Date = ExportLog.epoch
    ) -> DataExportState {
        DataExportState(
            export: log.export,
            settings: settings ?? log.repositories.settings,
            directory: scratch.url,
            now: { now })
    }

    /// The files a ready phase carries, or `nil` from any other phase.
    ///
    /// - Parameter phase: The phase to read.
    /// - Returns: The files.
    static func files(of phase: DataExportState.Phase) -> TrainingLogExportFiles? {
        guard case .ready(let files) = phase else { return nil }
        return files
    }

    @Test("It prepares both files and says what is in them")
    func reachesReady() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        #expect(state.phase == .idle)
        await state.prepare()
        let files = try #require(Self.files(of: state.phase))
        #expect(files.sessionCount == 1)
        #expect(files.setCount == 3)
        #expect(FileManager.default.fileExists(atPath: files.csv.path))
        #expect(FileManager.default.fileExists(atPath: files.json.path))
    }

    @Test("Nothing logged is the empty state, and no file is written for it")
    func reachesEmpty() async throws {
        let log = ExportLog()
        _ = try await log.exercise(named: "Back Squat")
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        await state.prepare()
        #expect(state.phase == .empty)
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path))
    }

    @Test("A failed read is the error state, and the retry runs the same call")
    func reachesFailedAndRecovers() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let stamp = ExportLog.epoch
        let failing = DataExportState(
            export: TrainingLogExport(
                exercises: log.repositories.exercises,
                workouts: FailingWorkoutReads(),
                bodyweight: log.repositories.bodyweight),
            settings: log.repositories.settings,
            directory: scratch.url,
            now: { stamp })
        await failing.prepare()
        #expect(DataExportScreenState.current(failing.phase) == .failed)

        // The screen's retry is `prepare()` again, so a state that could not re-enter its own
        // read would leave a button that does nothing. Same object, working store this time.
        let recovering = Self.state(log, in: scratch)
        await recovering.prepare()
        await recovering.prepare()
        #expect(DataExportScreenState.current(recovering.phase) != .failed)
    }

    @Test("The CSV is written in the unit the preferences are in")
    func honoursTheDisplayUnit() async throws {
        let log = try await ExportLog.populated()
        try await log.setDisplayUnit(.pounds)
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        await state.prepare()
        let files = try #require(Self.files(of: state.phase))
        let csv = try #require(String(data: Data(contentsOf: files.csv), encoding: .utf8))
        #expect(csv.contains("weight_lb"))
        #expect(!csv.contains("weight_kg"))
    }

    @Test("A settings row that cannot be read fails the export rather than guessing a unit")
    func refusesToGuessTheUnit() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch, settings: FailingSettingsReads())
        await state.prepare()
        #expect(DataExportScreenState.current(state.phase) == .failed)
    }

    @Test("Every phase maps to one of the four states the screen draws")
    func mapsEveryPhase() {
        let files = TrainingLogExportFiles(
            csv: URL(filePath: "/tmp/a.csv"),
            json: URL(filePath: "/tmp/a.json"),
            sessionCount: 1,
            setCount: 2)
        #expect(DataExportScreenState.current(.idle) == .preparing)
        #expect(DataExportScreenState.current(.preparing) == .preparing)
        #expect(DataExportScreenState.current(.ready(files)) == .ready(files))
        #expect(DataExportScreenState.current(.empty) == .empty)
        #expect(DataExportScreenState.current(.failed("boom")) == .failed)
    }
}

/// A workout repository whose reads all throw — the store failing under an export.
private struct FailingWorkoutReads: WorkoutRepository {
    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        throw RepositoryError.recordNotFound(id: id)
    }
    func save(_ session: WorkoutSession) async throws {}
    func deleteSession(id: UUID) async throws {}
    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        throw RepositoryError.recordNotFound(id: sessionID)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        throw RepositoryError.recordNotFound(id: id)
    }
    func save(_ entry: ExerciseEntry) async throws {}
    func deleteExerciseEntry(id: UUID) async throws {}
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw RepositoryError.recordNotFound(id: entryID)
    }
    func save(_ set: SetEntry) async throws {}
    func deleteSet(id: UUID) async throws {}
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        throw RepositoryError.recordNotFound(id: exerciseID)
    }
}

/// A settings repository whose read throws.
private struct FailingSettingsReads: SettingsRepository {
    func settings() async throws -> UserSettings {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func save(_ settings: UserSettings) async throws {}
}
