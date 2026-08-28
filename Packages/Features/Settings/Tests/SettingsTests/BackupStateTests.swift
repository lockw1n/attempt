import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// The backup screen's three states (`FR-1.11.3`, `FR-1.13.1`).
@MainActor
@Suite("Backup state")
struct BackupStateTests {
    /// A state over one fixture's store, writing into a directory the test owns.
    static func state(
        _ log: ExportLog,
        in scratch: ScratchDirectory,
        now: Date = ExportLog.epoch
    ) -> BackupState {
        BackupState(backup: log.backup, directory: scratch.url, now: { now })
    }

    /// The file a ready phase carries, or `nil` from any other phase.
    ///
    /// - Parameter phase: The phase to read.
    /// - Returns: The file.
    static func file(of phase: BackupState.Phase) -> BackupFile? {
        guard case .ready(let file) = phase else { return nil }
        return file
    }

    @Test("It writes the file and says what is in it")
    func reachesReady() async throws {
        let log = try await ExportLog.wholeStore()
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        #expect(state.phase == .idle)
        await state.prepare()
        let file = try #require(Self.file(of: state.phase))
        // 2 exercises + 3 sessions + 2 entries + 4 sets + 2 readings + 2 gyms + 2 training maxes
        // + the preferences row.
        #expect(file.recordCount == 18)
        #expect(file.workoutCount == 3)
        // A session, a slot, that slot's set, a reading and a gym.
        #expect(file.deletedCount == 5)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test("The file on disk decodes back as a backup, not merely as JSON")
    func writesAReadableBackup() async throws {
        let log = try await ExportLog.wholeStore()
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        await state.prepare()
        let file = try #require(Self.file(of: state.phase))
        let archive = try TrainingLogArchive.decoded(from: Data(contentsOf: file.url))
        #expect(archive.contents == .fullBackup)
        #expect(archive.equipment.count == 2)
        #expect(archive.settings != nil)
    }

    @Test("A store with nothing logged still produces a file, because there is no empty state")
    func aFreshStoreStillWritesAFile() async throws {
        let log = ExportLog()
        try await log.gym(named: "home gym")
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        await state.prepare()
        let file = try #require(Self.file(of: state.phase))
        #expect(file.workoutCount == 0)
        #expect(file.recordCount == 2)
        #expect(FileManager.default.fileExists(atPath: file.url.path))
    }

    @Test("The name carries the day the backup was taken")
    func namesTheFileByItsDay() async throws {
        let log = try await ExportLog.wholeStore()
        let scratch = ScratchDirectory()
        let state = Self.state(log, in: scratch)
        await state.prepare()
        let file = try #require(Self.file(of: state.phase))
        let expected = BackupWriter.name(for: ExportLog.epoch, timeZone: .current)
        #expect(file.url.lastPathComponent == "\(expected).json")
        #expect(expected.hasPrefix("Attempt-backup-"))
    }

    @Test("A failed read is the error state and writes nothing")
    func reachesFailed() async throws {
        let log = try await ExportLog.wholeStore()
        let scratch = ScratchDirectory()
        let stamp = ExportLog.epoch
        let state = BackupState(
            backup: FullBackup(
                exercises: log.repositories.exercises,
                workouts: log.repositories.workouts,
                bodyweight: log.repositories.bodyweight,
                equipment: log.repositories.equipment,
                settings: FailingSettingsRead()),
            directory: scratch.url,
            now: { stamp })
        await state.prepare()
        #expect(BackupScreenState.current(state.phase) == .failed)
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path))
    }

    @Test("Every phase maps to one of the three states the screen draws")
    func mapsEveryPhase() {
        let file = BackupFile(
            url: URL(filePath: "/tmp/a.json"), workoutCount: 1, recordCount: 9, deletedCount: 0)
        #expect(BackupScreenState.current(.idle) == .preparing)
        #expect(BackupScreenState.current(.preparing) == .preparing)
        #expect(BackupScreenState.current(.ready(file)) == .ready(file))
        #expect(BackupScreenState.current(.failed("boom")) == .failed)
    }
}

/// A settings repository whose read throws — the one table a backup cannot do without.
private struct FailingSettingsRead: SettingsRepository {
    func settings() async throws -> UserSettings {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func save(_ settings: UserSettings) async throws {}
}
