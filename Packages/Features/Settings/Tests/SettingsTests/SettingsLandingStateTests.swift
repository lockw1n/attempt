import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Settings
import Testing

/// The pattern's own proof: every one of these exercises a screen's logic with no view anywhere in
/// the test (`TR-1.2`).
@Suite("Settings landing state")
struct SettingsLandingStateTests {
    @Test("A first load publishes the stored row")
    func loadPublishesStoredRow() async throws {
        let repository = InMemoryRepositoryStack().settings
        let stored = try await repository.settings()
        let state = landingState(over: repository)

        #expect(state.phase == .idle)
        await state.load()

        #expect(state.phase == .loaded(stored))
    }

    @Test("A second load does not read again")
    func loadIsIdempotent() async {
        let repository = ScriptedSettingsRepository(row: .fixture())
        let state = landingState(over: repository)

        await state.load()
        await state.load()

        #expect(await repository.reads == 1)
    }

    @Test("A load requested while one is in flight does not read again")
    func loadIsNotReentrant() async {
        let repository = ScriptedSettingsRepository(row: .fixture(), gateReads: true)
        let state = landingState(over: repository)

        let first = Task { await state.load() }
        await repository.waitUntilReads(reach: 1)
        #expect(state.phase == .loading)

        // The second load runs in its own task and the gate is opened before anything is awaited:
        // a re-entrant `load` would otherwise park the test itself at the gate, and a broken unit
        // has to fail an expectation rather than hang the suite.
        let second = Task { await state.load() }
        for _ in 0..<50 { await Task.yield() }
        let readsWhileInFlight = await repository.reads

        await repository.openReads()
        await first.value
        await second.value

        #expect(readsWhileInFlight == 1)
        #expect(await repository.reads == 1)
    }

    @Test("A failed read leaves the diagnostic on the phase")
    func failedReadIsReported() async {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let repository = ScriptedSettingsRepository(row: .fixture(), readError: failure)
        let state = landingState(over: repository)

        await state.load()

        #expect(state.phase == .failed(String(describing: failure)))
    }

    @Test("A failed read is retried by loading again, which is the screen's retry")
    func failedReadIsRetryable() async {
        let repository = ScriptedSettingsRepository(
            row: .fixture(), readError: .recordNotFound(id: UUID()))
        let state = landingState(over: repository)
        await state.load()
        #expect(await repository.reads == 1)

        await repository.recoverReads()
        await state.load()

        #expect(state.phase == .loaded(.fixture()))
        #expect(await repository.reads == 2)
    }

    @Test("Switching the display unit writes it through and republishes what the store kept")
    func displayUnitIsPersisted() async throws {
        let repository = InMemoryRepositoryStack().settings
        let state = landingState(over: repository)
        await state.load()

        await state.setDisplayUnit(.pounds)

        let stored = try await repository.settings()
        #expect(stored.displayUnit == .pounds)
        #expect(state.phase == .loaded(stored))
        #expect(state.writeFailure == nil)
    }

    @Test("Switching to the unit already stored writes nothing")
    func unchangedUnitIsNotWritten() async throws {
        let repository = InMemoryRepositoryStack().settings
        let state = landingState(over: repository)
        await state.load()
        let before = try await repository.settings()

        await state.setDisplayUnit(before.displayUnit)

        // `updatedAt` rather than a call count, because the rule is about the column: a save that
        // changed nothing would still restamp G-2.4's conflict key.
        let after = try await repository.settings()
        #expect(after.updatedAt == before.updatedAt)
        #expect(state.phase == .loaded(before))
    }

    @Test("A unit change before the row is loaded writes nothing")
    func mutationBeforeLoadIsRefused() async {
        let repository = ScriptedSettingsRepository(row: .fixture())
        let state = landingState(over: repository)

        await state.setDisplayUnit(.pounds)

        #expect(await repository.writes == 0)
        #expect(state.phase == .idle)
    }

    @Test("A unit change requested while one is in flight decides against the first one's result")
    func writesAreSerialized() async throws {
        let repository = ScriptedSettingsRepository(
            row: .fixture(displayUnit: .kilograms), gateWrites: true)
        let state = landingState(over: repository)
        await state.load()

        // kg → lb, which suspends inside the save.
        let first = Task { await state.setDisplayUnit(.pounds) }
        await repository.waitUntilWrites(reach: 1)

        // The user taps back to kg while that write is still in flight. Deciding against the row
        // the screen is still publishing would compare kg against kg and drop the tap.
        let second = Task { await state.setDisplayUnit(.kilograms) }
        for _ in 0..<50 { await Task.yield() }

        await repository.openWrites()
        await first.value
        await second.value

        #expect(await repository.row.displayUnit == .kilograms)
        #expect(state.phase == .loaded(await repository.row))
    }

    @Test("A failed write is reported without costing the screen its row")
    func failedWriteIsReported() async {
        let failure = RepositoryError.identityAlreadyEstablished(recordID: UUID())
        let repository = ScriptedSettingsRepository(
            row: .fixture(displayUnit: .kilograms), writeError: failure)
        let state = landingState(over: repository)
        await state.load()

        await state.setDisplayUnit(.pounds)

        #expect(state.writeFailure == String(describing: failure))
        // The row survives the failure: the screen is still usable, which is what makes the next
        // attempt a tap rather than a relaunch.
        #expect(state.phase == .loaded(.fixture(displayUnit: .kilograms)))
    }

    @Test("A write that succeeds after one failed clears the diagnostic")
    func successfulWriteClearsTheFailure() async {
        let repository = ScriptedSettingsRepository(
            row: .fixture(displayUnit: .kilograms),
            writeError: .identityAlreadyEstablished(recordID: UUID()))
        let state = landingState(over: repository)
        await state.load()
        await state.setDisplayUnit(.pounds)
        #expect(state.writeFailure != nil)

        await repository.recoverWrites()
        await state.setDisplayUnit(.pounds)

        #expect(state.writeFailure == nil)
        #expect(await repository.row.displayUnit == .pounds)
    }
}

/// A `SettingsRepository` the test drives: it counts its calls, fails where it is told to, and
/// holds a call at a gate so a test can decide what is in flight when.
///
/// The happy paths above run against `RepositoryFakes` instead, whose conformance suite is what
/// says it behaves like the real store. This one exists for the three things a faithful fake cannot
/// be asked for — a call count, a failure, and a suspension the test controls.
actor ScriptedSettingsRepository: SettingsRepository {
    private(set) var row: UserSettings
    private var readError: RepositoryError?
    private var writeError: RepositoryError?
    private(set) var reads = 0
    private(set) var writes = 0

    /// Gates. **Opening one is permanent**, so a test can never hang waiting to open it twice —
    /// which matters most when the behaviour under test is broken and makes an extra call.
    private var gateReads: Bool
    private var gateWrites: Bool
    private var waitingReads: [CheckedContinuation<Void, Never>] = []
    private var waitingWrites: [CheckedContinuation<Void, Never>] = []

    init(
        row: UserSettings,
        readError: RepositoryError? = nil,
        writeError: RepositoryError? = nil,
        gateReads: Bool = false,
        gateWrites: Bool = false
    ) {
        self.row = row
        self.readError = readError
        self.writeError = writeError
        self.gateReads = gateReads
        self.gateWrites = gateWrites
    }

    func settings() async throws -> UserSettings {
        reads += 1
        if gateReads { await withCheckedContinuation { waitingReads.append($0) } }
        if let readError { throw readError }
        return row
    }

    func save(_ settings: UserSettings) async throws {
        writes += 1
        if gateWrites { await withCheckedContinuation { waitingWrites.append($0) } }
        if let writeError { throw writeError }
        row = settings
    }

    /// Stops failing reads, so the next one behaves.
    func recoverReads() { readError = nil }

    /// Stops failing writes, so the next one lands.
    func recoverWrites() { writeError = nil }

    /// Lets every gated read through, now and afterwards.
    func openReads() {
        gateReads = false
        for continuation in waitingReads { continuation.resume() }
        waitingReads.removeAll()
    }

    /// Lets every gated write through, now and afterwards.
    func openWrites() {
        gateWrites = false
        for continuation in waitingWrites { continuation.resume() }
        waitingWrites.removeAll()
    }

    /// Yields until `reads` reaches `count`, or until the budget runs out — bounded so a broken
    /// unit fails an expectation rather than hanging the suite.
    func waitUntilReads(reach count: Int) async {
        for _ in 0..<10_000 where reads < count { await Task.yield() }
    }

    /// Yields until `writes` reaches `count`, or until the budget runs out.
    func waitUntilWrites(reach count: Int) async {
        for _ in 0..<10_000 where writes < count { await Task.yield() }
    }
}

extension UserSettings {
    /// A settings row with every field fixed, so a test asserts on what it set.
    static func fixture(displayUnit: MassUnit = .kilograms) -> UserSettings {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return UserSettings(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID(),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            userID: UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID(),
            displayUnit: displayUnit,
            e1RMFormula: .epley,
            theme: .system,
            defaultRoundingIncrement: Weight(grams: 2500),
            defaultRoundingStrategy: .nearest
        )
    }
}

/// A landing state over `repository`, with a recompute actor over throwaway fakes.
///
/// **Every test that does not touch the formula ignores it**, which is why it is defaulted here
/// rather than threaded through each call: the pipeline is a collaborator of one preference out of
/// the four, and making the other tests name it would say otherwise.
func landingState(
    over repository: any SettingsRepository,
    records: PersonalRecordRecomputer? = nil
) -> SettingsLandingState {
    let fakes = InMemoryRepositoryStack()
    return SettingsLandingState(
        repository: repository,
        records: records
            ?? PersonalRecordRecomputer(
                workouts: fakes.workouts, cache: fakes.personalRecords))
}

/// `FR-1.7.2`'s picker, and the half of `FR-1.7.3` that is not the pipeline's.
@Suite("Settings e1RM formula")
struct SettingsFormulaTests {
    @Test("Choosing a formula stores it and tells the recompute pipeline")
    func choosingAFormulaStoresAndAnnounces() async throws {
        let repository = InMemoryRepositoryStack().settings
        let fakes = InMemoryRepositoryStack()
        let records = PersonalRecordRecomputer(
            workouts: fakes.workouts, cache: fakes.personalRecords)
        let state = landingState(over: repository, records: records)
        await state.load()

        await state.setE1RMFormula(.brzycki)

        #expect(try await repository.settings().e1RMFormula == .brzycki)
        #expect(await records.formulaInForce() == .brzycki)
        #expect(state.writeFailure == nil)
    }

    /// `FR-1.7.3` is not the column moving, it is every estimate moving — so the announcement is
    /// what the test asserts, not just the write.
    @Test("Choosing a formula tells every subscribed screen to read again")
    func choosingAFormulaPublishes() async throws {
        let repository = InMemoryRepositoryStack().settings
        let fakes = InMemoryRepositoryStack()
        let records = PersonalRecordRecomputer(
            workouts: fakes.workouts, cache: fakes.personalRecords)
        let state = landingState(over: repository, records: records)
        await state.load()
        var changes = await records.changes().makeAsyncIterator()

        await state.setE1RMFormula(.wathan)

        #expect(await changes.next() == .everyExercise)
    }

    /// `G-2.4`'s conflict key is `updatedAt`, so a write of the value already stored would let a
    /// local no-op outrank a real remote edit.
    @Test("Choosing the formula already in force writes nothing")
    func anUnchangedFormulaWritesNothing() async throws {
        let repository = InMemoryRepositoryStack().settings
        let state = landingState(over: repository)
        await state.load()
        let before = try await repository.settings()

        await state.setE1RMFormula(before.e1RMFormula)

        #expect(try await repository.settings().updatedAt == before.updatedAt)
    }

    /// A pipeline told about a formula the store refused would draw estimates the settings row does
    /// not agree with, and the next relaunch would silently undo them.
    @Test("A failed write leaves the pipeline on the formula that is actually stored")
    func aFailedWriteDoesNotAnnounce() async throws {
        let repository = ScriptedSettingsRepository(row: .fixture(), writeError: .recordNotFound(id: UUID()))
        let fakes = InMemoryRepositoryStack()
        let records = PersonalRecordRecomputer(
            workouts: fakes.workouts, cache: fakes.personalRecords)
        let state = landingState(over: repository, records: records)
        await state.load()

        await state.setE1RMFormula(.lombardi)

        #expect(state.writeFailure != nil)
        #expect(await records.formulaInForce() == .defaultFormula)
    }
}
