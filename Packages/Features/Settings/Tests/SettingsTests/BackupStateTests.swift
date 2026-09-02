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
        // 2 exercises + 4 sessions + 3 entries + 5 sets + 2 readings + 2 gyms + 2 training maxes
        // + 2 routines + 2 routine slots + 4 target groups + 2 planned targets + the preferences
        // row.
        #expect(file.recordCount == 31)
        #expect(file.workoutCount == 4)
        // A session, a slot, that slot's set, a reading, a gym, and the archived routine with its
        // slot and that slot's two target groups.
        #expect(file.deletedCount == 9)
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
                routines: log.repositories.routines,
                settings: FailingSettingsRead()),
            directory: scratch.url,
            now: { stamp })
        await state.prepare()
        #expect(BackupScreenState.current(state.phase) == .failed)
        #expect(!FileManager.default.fileExists(atPath: scratch.url.path))
    }

    @Test("A backup taken on a later day replaces the one before it")
    func doesNotHandOnYesterdaysFile() async throws {
        let log = try await ExportLog.wholeStore()
        let scratch = ScratchDirectory()
        let stale = try BackupWriter.write(
            try await log.backup.archive(takenAt: ExportLog.epoch),
            into: scratch.url,
            timeZone: .gmt)

        // A day later, and a gym lighter — the names differ, so without emptying the directory the
        // share sheet would still be offered a file describing a store that has moved on.
        let gym = try #require(
            try await log.repositories.equipment.profiles(includingDeleted: false).first)
        try await log.repositories.equipment.deleteProfile(id: gym.id)
        let fresh = try BackupWriter.write(
            try await log.backup.archive(takenAt: ExportLog.epoch.addingTimeInterval(86_400)),
            into: scratch.url,
            timeZone: .gmt)

        #expect(fresh.deletedCount == stale.deletedCount + 1)
        #expect(!FileManager.default.fileExists(atPath: stale.url.path))
        #expect(FileManager.default.fileExists(atPath: fresh.url.path))
        #expect(fresh.url.lastPathComponent == "Attempt-backup-2025-07-07.json")
    }

    // **The second preparation is never awaited before the count is read**, and that is the whole
    // shape of this test rather than a detail of it. A broken guard leaves that second call
    // suspended in the gate, and a held `withCheckedContinuation` is not cancellable — so awaiting
    // it here would hang the suite instead of failing it, and a `.timeLimit` cannot rescue that
    // (measured: a run in that shape sat for 54 minutes before it was killed by hand). What is
    // asserted instead is that the store was not walked a second time while the first walk was
    // provably still open.
    @Test("A second preparation while one is running is not a second walk of the store")
    func prepareIsSingleFlight() async throws {
        let log = try await ExportLog.wholeStore()
        let gated = GatedWorkoutReads()
        let scratch = ScratchDirectory()
        let stamp = ExportLog.epoch
        let state = BackupState(
            backup: FullBackup(
                exercises: log.repositories.exercises,
                workouts: gated,
                bodyweight: log.repositories.bodyweight,
                equipment: log.repositories.equipment,
                routines: log.repositories.routines,
                settings: log.repositories.settings),
            directory: scratch.url,
            now: { stamp })

        // The screen re-runs `prepare()` every time it appears, so two can overlap. The second has
        // to fall straight through: a second walk empties and rewrites the directory holding the
        // file the first one is about to hand to a share sheet.
        let running = Task { @MainActor in await state.prepare() }
        await gated.waitForARead()

        // A wait rather than a signal, because this proves a negative: when the guard holds there
        // is nothing to be notified of, and the pause is only long enough for a guardless second
        // walk to reach the gated read and be counted.
        let second = Task { @MainActor in await state.prepare() }
        try await Task.sleep(for: .milliseconds(200))
        // Counted while the first read is provably still held open — the one moment the two
        // preparations are certainly overlapping. After the release the first has finished and a
        // second walk would be allowed on its own terms.
        #expect(await gated.reads == 1)

        await gated.releaseHeldReads()
        await running.value
        await second.value
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
