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

    @Test("A failed read is the error state")
    func reachesFailed() async throws {
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
    }

    @Test("The retry is the same call on the same state, and it recovers")
    func recoversOnTheRetry() async throws {
        let log = try await ExportLog.populated()
        let scratch = ScratchDirectory()
        let stamp = ExportLog.epoch
        // The one store refuses its first read and answers the second, so the object that failed
        // is the object that retries — which is what the screen does, `ErrorStateView`'s retry
        // being `prepare()` on the state already on screen.
        let state = DataExportState(
            export: TrainingLogExport(
                exercises: log.repositories.exercises,
                workouts: FailsOnceThenReads(log.repositories.workouts),
                bodyweight: log.repositories.bodyweight),
            settings: log.repositories.settings,
            directory: scratch.url,
            now: { stamp })
        await state.prepare()
        #expect(DataExportScreenState.current(state.phase) == .failed)

        await state.prepare()
        // Anchored to `.ready` and to what is in it, rather than to "not failed": `.empty` is also
        // not failed, and a retry that recovered into the empty state would be the wrong recovery.
        let files = try #require(Self.files(of: state.phase))
        #expect(files.sessionCount == 1)
        #expect(files.setCount == 3)
    }

    // **The second preparation is never awaited before the count is read**, and that is the whole
    // shape of this test rather than a detail of it. A broken guard leaves that second call
    // suspended in the gate, and a held `withCheckedContinuation` is not cancellable — so awaiting
    // it here would hang the suite instead of failing it, and the `.timeLimit` this test used to
    // carry cannot rescue that (measured under a probe: 54 minutes before it was killed by hand).
    // What is asserted instead is that the store was not walked a second time while the first walk
    // was provably still open.
    @Test("A second preparation while one is running is not a second walk of the store")
    func prepareIsSingleFlight() async throws {
        let log = try await ExportLog.populated()
        let gated = GatedWorkoutReads()
        let scratch = ScratchDirectory()
        let stamp = ExportLog.epoch
        let state = DataExportState(
            export: TrainingLogExport(
                exercises: log.repositories.exercises,
                workouts: gated,
                bodyweight: log.repositories.bodyweight),
            settings: log.repositories.settings,
            directory: scratch.url,
            now: { stamp })

        // The screen re-runs `prepare()` every time it appears, so two can overlap. The second has
        // to fall straight through: a second walk would empty and rewrite the directory holding
        // the files the first one is about to hand to a share sheet.
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

/// A workout repository that refuses its first session read and then answers from the real fakes —
/// one store failing under an export and working for the retry.
private actor FailsOnceThenReads: WorkoutRepository {
    /// What answers once the one refusal is spent.
    private let wrapped: any WorkoutRepository

    /// Whether that refusal has been handed out.
    private var hasRefused = false

    /// Wraps the store that answers the retry.
    ///
    /// - Parameter wrapped: The working repository.
    init(_ wrapped: any WorkoutRepository) {
        self.wrapped = wrapped
    }

    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        guard hasRefused else {
            hasRefused = true
            throw RepositoryError.recordNotFound(id: UUID())
        }
        return try await wrapped.sessions(in: range, includingDeleted: includingDeleted)
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? {
        try await wrapped.session(id: id, includingDeleted: includingDeleted)
    }
    func save(_ session: WorkoutSession) async throws { try await wrapped.save(session) }
    func deleteSession(id: UUID) async throws { try await wrapped.deleteSession(id: id) }
    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] {
        try await wrapped.entries(forSessionID: sessionID, includingDeleted: includingDeleted)
    }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? {
        try await wrapped.entry(id: id, includingDeleted: includingDeleted)
    }
    func save(_ entry: ExerciseEntry) async throws { try await wrapped.save(entry) }
    func deleteExerciseEntry(id: UUID) async throws {
        try await wrapped.deleteExerciseEntry(id: id)
    }
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forEntryID: entryID, includingDeleted: includingDeleted)
    }
    func save(_ set: SetEntry) async throws { try await wrapped.save(set) }
    func deleteSet(id: UUID) async throws { try await wrapped.deleteSet(id: id) }
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        try await wrapped.sets(forExerciseID: exerciseID, includingDeleted: includingDeleted)
    }
}

/// A workout repository that holds its session read open until the test lets it go, counting how
/// many reads actually started — which is the only way to see a single-flight guard work.
///
/// Internal rather than private because ``BackupStateTests`` gates the same read to prove the same
/// guard: both screens walk the store behind a `.task` that re-runs on every appearance.
actor GatedWorkoutReads: WorkoutRepository, PlannedTargetRepository {
    /// How many session reads have begun.
    private(set) var reads = 0

    /// Resumed when a read first arrives.
    private var arrival: CheckedContinuation<Void, Never>?

    /// Every read currently being held, resumed together.
    ///
    /// **All of them, not the latest one.** A gate keeping a single continuation would leak the
    /// first read the moment a second arrived, and the leak would outlive the test that caused it.
    private var held: [CheckedContinuation<Void, Never>] = []

    /// Whether a read has arrived, so a waiter arriving after one does not wait for the next.
    private var hasArrived = false

    /// Whether the release has been given, so a read arriving after it is not held forever.
    private var isReleased = false

    /// Waits until a read has begun.
    func waitForARead() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets every held read finish.
    func releaseHeldReads() {
        isReleased = true
        for continuation in held { continuation.resume() }
        held = []
    }

    func sessions(
        in range: ClosedRange<Date>,
        includingDeleted: Bool
    ) async throws -> [WorkoutSession] {
        reads += 1
        hasArrived = true
        arrival?.resume()
        arrival = nil
        if !isReleased {
            await withCheckedContinuation { held.append($0) }
        }
        return []
    }
    func session(id: UUID, includingDeleted: Bool) async throws -> WorkoutSession? { nil }
    func save(_ session: WorkoutSession) async throws {}
    func deleteSession(id: UUID) async throws {}
    func entries(
        forSessionID sessionID: UUID,
        includingDeleted: Bool
    ) async throws -> [ExerciseEntry] { [] }
    func entry(id: UUID, includingDeleted: Bool) async throws -> ExerciseEntry? { nil }
    func save(_ entry: ExerciseEntry) async throws {}
    func deleteExerciseEntry(id: UUID) async throws {}
    func sets(forEntryID entryID: UUID, includingDeleted: Bool) async throws -> [SetEntry] { [] }
    func save(_ set: SetEntry) async throws {}
    func deleteSet(id: UUID) async throws {}
    func sets(forExerciseID exerciseID: UUID, includingDeleted: Bool) async throws -> [SetEntry] {
        []
    }
    func plannedTargets(
        forEntryID entryID: UUID,
        includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup] { [] }
    func save(_ group: PlannedTargetGroup) async throws {}
}

/// A settings repository whose read throws.
private struct FailingSettingsReads: SettingsRepository {
    func settings() async throws -> UserSettings {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func save(_ settings: UserSettings) async throws {}
    func restorePreferences(from backup: UserSettings) async throws {}
}
