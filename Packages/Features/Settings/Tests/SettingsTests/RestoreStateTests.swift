import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

// FR-1.11.4's screen, without the screen. The claim this suite makes is the one the Done-when calls
// "cannot be bypassed accidentally": reading a file and writing it are two states with a decision
// between them, and no ordering of the calls collapses them into one.

@MainActor
@Suite("Restore state")
struct RestoreStateTests {
    /// The state over a store, and the store itself.
    ///
    /// - Parameter stack: The fakes to write into. A fresh, empty one by default.
    /// - Returns: The state and its store.
    static func state(
        into stack: InMemoryRepositoryStack = InMemoryRepositoryStack()
    ) -> (RestoreState, InMemoryRepositoryStack) {
        (RestoreState(restore: RestoreTests.restore(into: stack)), stack)
    }

    /// Writes a payload out where the state can pick it up.
    ///
    /// - Parameters:
    ///   - data: The bytes.
    ///   - scratch: Where to put them.
    /// - Returns: The file's URL.
    static func file(_ data: Data, in scratch: ScratchDirectory) throws -> URL {
        try FileManager.default.createDirectory(at: scratch.url, withIntermediateDirectories: true)
        let url = scratch.url.appending(path: "Attempt-backup-2025-07-06.json")
        try data.write(to: url)
        return url
    }

    /// How many exercises the store holds — the cheapest "was anything written?" there is, since
    /// the catalogue is the first thing a restore writes.
    ///
    /// - Parameter stack: The store.
    /// - Returns: The count.
    static func catalogueSize(of stack: InMemoryRepositoryStack) async throws -> Int {
        try await stack.exercises.exercises(includingDeleted: true).count
    }

    @Test("The screen starts with no file and nothing to say about one")
    func startsWaiting() {
        let (state, _) = Self.state()
        #expect(state.phase == .waiting)
        #expect(RestoreScreenState.current(state.phase) == .waiting)
    }

    @Test("A backup file is counted and held, and nothing is written yet")
    func readsIntoTheConfirmation() async throws {
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let (state, target) = Self.state()

        await state.read(url)
        #expect(state.phase == .confirming(BackupSummary(archive)))
        // The half of `FR-1.11.4` a confirmation is for: the counts are on screen and the store is
        // untouched. A read that wrote as it parsed would satisfy the phase and fail this line.
        #expect(try await Self.catalogueSize(of: target) == 0)
    }

    @Test("The reading state is one the screen can actually draw")
    func readingIsObservable() async throws {
        // FR-1.13.1's loading state, as a state and not just as a component reference. This module
        // is `defaultIsolation(MainActor)`, so a read that stayed on this actor would run from
        // `.reading` to `.confirming` inside one main-actor slice: the observation would coalesce,
        // the loading state would never reach the screen, and the whole decode would sit on the
        // main thread. `RestoreState.archive(at:)` is `nonisolated async` so that it does not.
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let (state, _) = Self.state()

        let running = Task { await state.read(url) }
        // Deterministic rather than racy: the yield hands the main actor to the task above, which
        // runs as far as its first suspension — the hop off this actor — and hands it back. Nothing
        // else can touch `phase` before the check, because the check does not await.
        await Task.yield()
        #expect(state.phase == .reading)

        await running.value
        #expect(state.phase == .confirming(BackupSummary(archive)))
    }

    @Test("Confirming writes the file that was counted")
    func confirmingWrites() async throws {
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let (state, target) = Self.state()

        await state.read(url)
        await state.confirmRestore()
        #expect(state.phase == .restored(BackupSummary(archive)))
        #expect(try await Self.catalogueSize(of: target) == archive.exercises.count)
        #expect(!archive.exercises.isEmpty)
    }

    @Test("An export is refused, and nothing is written")
    func refusesAnExport() async throws {
        let log = try await ExportLog.populated()
        let export = try await log.export.archive(exportedAt: ExportLog.epoch)
        let scratch = ScratchDirectory()
        let url = try Self.file(try export.encoded(), in: scratch)
        let (state, target) = Self.state()

        await state.read(url)
        #expect(state.phase == .refused(.notABackup))
        #expect(try await Self.catalogueSize(of: target) == 0)
    }

    @Test("A file that is not there at all reads as unreadable rather than crashing")
    func refusesAMissingFile() async throws {
        let (state, target) = Self.state()
        await state.read(URL(filePath: "/tmp/no-such-attempt-backup-\(UUID().uuidString).json"))
        #expect(state.phase == .refused(.unreadable))
        #expect(try await Self.catalogueSize(of: target) == 0)
    }

    @Test("A confirmation with no file behind it writes nothing")
    func confirmingWithoutAFileDoesNothing() async throws {
        let (state, target) = Self.state()
        await state.confirmRestore()
        #expect(state.phase == .waiting)
        #expect(try await Self.catalogueSize(of: target) == 0)
    }

    @Test("Choosing another file takes the first one back off the table")
    func choosingAnotherClearsThePendingFile() async throws {
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let (state, target) = Self.state()

        await state.read(url)
        state.chooseAnother()
        #expect(state.phase == .waiting)

        // The answer belongs to the question it was asked about. A confirmation arriving after the
        // screen was reset must not write the file the screen has stopped showing.
        await state.confirmRestore()
        #expect(state.phase == .waiting)
        #expect(try await Self.catalogueSize(of: target) == 0)
    }

    @Test("A write that fails part-way is the failed state, not a refusal")
    func reachesFailed() async throws {
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let stack = InMemoryRepositoryStack()
        let state = RestoreState(
            restore: StoreRestore(
                exercises: FailingExerciseSave(),
                workouts: stack.workouts,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                routines: stack.routines,
                settings: stack.settings,
                records: PersonalRecordRecomputer(
                    workouts: stack.workouts,
                    exercises: stack.exercises,
                    cache: stack.personalRecords)))

        await state.read(url)
        await state.confirmRestore()
        #expect(RestoreScreenState.current(state.phase) == .failed)
        // Not a refusal: the two are drawn differently and say different things, and a failure
        // reported as a refusal would tell the lifter nothing had been written when rows had.
        if case .refused = state.phase { Issue.record("a write failure was reported as a refusal") }
    }

    // **The second confirmation is never awaited before the count is read**, for the reason the
    // backup suite writes out at length: a broken guard leaves it suspended on a held continuation,
    // which is not cancellable, so awaiting it would hang the suite instead of failing it.
    @Test("A second confirmation while one is running does not write the file twice")
    func confirmIsSingleFlight() async throws {
        let (archive, _) = try await RestoreTests.backupOfWholeStore()
        let scratch = ScratchDirectory()
        let url = try Self.file(try archive.encoded(), in: scratch)
        let gated = GatedExerciseSaves()
        let stack = InMemoryRepositoryStack()
        let state = RestoreState(
            restore: StoreRestore(
                exercises: gated,
                workouts: stack.workouts,
                bodyweight: stack.bodyweight,
                equipment: stack.equipment,
                routines: stack.routines,
                settings: stack.settings,
                records: PersonalRecordRecomputer(
                    workouts: stack.workouts,
                    exercises: stack.exercises,
                    cache: stack.personalRecords)))
        await state.read(url)

        // A destructive button is a button a nervous thumb hits twice. Without the guard the second
        // press starts a second pass over every table while the first is still writing.
        let running = Task { @MainActor in await state.confirmRestore() }
        let arrived = await gated.waitForASave()
        #expect(arrived, "the restore never wrote an exercise, so the gate never closed")
        let second = Task { @MainActor in await state.confirmRestore() }
        // A wait rather than a signal, because this proves a negative: when the guard holds there
        // is nothing to be notified of.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await gated.saves == 1)

        await gated.releaseHeldSaves()
        await running.value
        await second.value
    }

    @Test("Each refusal gets its own sentence rather than a shared one")
    func refusalsAreDrawnApart() {
        // The three refusals ask the lifter for three different things — a newer app, the other
        // file, another copy — so a mapping that collapsed any two would send someone looking for
        // a file that is fine. Held here rather than in three snapshots: the layout is one error
        // state, and what differs is the copy.
        let refusals: [RestoreRefusal] = [.unreadable, .futureVersion(3), .notABackup]
        let headlines = refusals.map { String(localized: RestoreReading.headline(for: $0)) }
        let messages = refusals.map { String(localized: RestoreReading.message(for: $0)) }
        #expect(Set(headlines).count == 3)
        #expect(Set(messages).count == 3)
        // Anchored to a literal, so the check above is not satisfied by three empty strings that
        // failed to resolve.
        #expect(headlines.allSatisfy { !$0.isEmpty && !$0.hasPrefix("settings.restore") })
        // The claimed version is not drawn: a number naming an internal format is not something a
        // lifter can act on, and it is carried so a test and a diagnostic can tell two refusals
        // apart.
        #expect(!messages.contains { $0.contains("3") })
    }

    @Test("Every phase maps to one of the seven states the screen draws")
    func mapsEveryPhase() {
        let summary = BackupSummary(
            takenAt: ExportLog.epoch, workoutCount: 3, recordCount: 90, deletedCount: 2)
        #expect(RestoreScreenState.current(.waiting) == .waiting)
        #expect(RestoreScreenState.current(.reading) == .reading)
        #expect(RestoreScreenState.current(.confirming(summary)) == .confirming(summary))
        #expect(RestoreScreenState.current(.restoring) == .restoring)
        #expect(RestoreScreenState.current(.restored(summary)) == .restored(summary))
        #expect(RestoreScreenState.current(.refused(.notABackup)) == .refused(.notABackup))
        // The diagnostic is dropped and the refusal is not: one is an error's description and the
        // other is a choice between three sentences written for the lifter (G-3.4).
        #expect(RestoreScreenState.current(.failed("boom")) == .failed)
    }
}

/// An exercise repository whose save throws — the first write a restore makes.
private struct FailingExerciseSave: ExerciseRepository {
    func exercises(includingDeleted: Bool) async throws -> [Exercise] { [] }
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { nil }
    func save(_ exercise: Exercise) async throws {
        throw RepositoryError.recordNotFound(id: exercise.id)
    }
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        nil
    }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] { [] }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}

/// An exercise repository that holds the first save open, so a second can be counted while the
/// first is provably still running.
///
/// The shape ``GatedWorkoutReads`` has, on the write side — see that type for why every held
/// continuation is kept rather than only the latest.
private actor GatedExerciseSaves: ExerciseRepository {
    /// How many saves have begun.
    private(set) var saves = 0

    /// Every save currently being held.
    private var held: [CheckedContinuation<Void, Never>] = []

    /// Whether a save has arrived.
    private var hasArrived = false

    /// Whether the release has been given.
    private var isReleased = false

    /// Waits until a save has begun, or gives up.
    ///
    /// **Bounded, and a continuation would not be.** The gate is an `ExerciseRepository`, so this
    /// wait quietly depends on the catalogue still being the first thing `StoreRestore.restore`
    /// writes — reorder those loops and an unbounded wait is never resumed, which hangs the suite
    /// instead of failing it. That is the shape `T-1.66`'s review already paid for once, one
    /// position over.
    ///
    /// - Returns: Whether a save arrived.
    func waitForASave() async -> Bool {
        for _ in 0..<200 {
            if hasArrived { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return hasArrived
    }

    /// Lets every held save finish.
    func releaseHeldSaves() {
        isReleased = true
        for continuation in held { continuation.resume() }
        held = []
    }

    func exercises(includingDeleted: Bool) async throws -> [Exercise] { [] }
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? { nil }

    func save(_ exercise: Exercise) async {
        saves += 1
        hasArrived = true
        if !isReleased {
            await withCheckedContinuation { held.append($0) }
        }
    }

    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        nil
    }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] { [] }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}
