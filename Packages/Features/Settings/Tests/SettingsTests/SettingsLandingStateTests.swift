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
        let state = SettingsLandingState(repository: repository)

        #expect(state.phase == .idle)
        await state.load()

        #expect(state.phase == .loaded(stored))
    }

    @Test("A second load does not read again")
    func loadIsIdempotent() async {
        let repository = ScriptedSettingsRepository(row: .fixture())
        let state = SettingsLandingState(repository: repository)

        await state.load()
        await state.load()

        #expect(await repository.reads == 1)
    }

    @Test("A failed read leaves the diagnostic on the phase")
    func failedReadIsReported() async {
        let failure = RepositoryError.recordNotFound(id: UUID())
        let repository = ScriptedSettingsRepository(row: .fixture(), readError: failure)
        let state = SettingsLandingState(repository: repository)

        await state.load()

        #expect(state.phase == .failed(String(describing: failure)))
    }

    @Test("Switching the display unit writes it through and republishes what the store kept")
    func displayUnitIsPersisted() async throws {
        let repository = InMemoryRepositoryStack().settings
        let state = SettingsLandingState(repository: repository)
        await state.load()

        await state.setDisplayUnit(.pounds)

        let stored = try await repository.settings()
        #expect(stored.displayUnit == .pounds)
        #expect(state.phase == .loaded(stored))
    }

    @Test("Switching to the unit already stored writes nothing")
    func unchangedUnitIsNotWritten() async throws {
        let repository = InMemoryRepositoryStack().settings
        let state = SettingsLandingState(repository: repository)
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
        let state = SettingsLandingState(repository: repository)

        await state.setDisplayUnit(.pounds)

        #expect(await repository.writes == 0)
        #expect(state.phase == .idle)
    }

    @Test("A failed write leaves the diagnostic on the phase")
    func failedWriteIsReported() async {
        let failure = RepositoryError.identityAlreadyEstablished(recordID: UUID())
        let repository = ScriptedSettingsRepository(row: .fixture(displayUnit: .kilograms), writeError: failure)
        let state = SettingsLandingState(repository: repository)
        await state.load()

        await state.setDisplayUnit(.pounds)

        #expect(state.phase == .failed(String(describing: failure)))
    }
}

/// A `SettingsRepository` the test drives: it counts its calls and fails where it is told to.
///
/// The happy paths above run against `RepositoryFakes` instead, whose conformance suite is what
/// says it behaves like the real store. This one exists for the two things a faithful fake cannot
/// be asked for — a call count, and a failure.
actor ScriptedSettingsRepository: SettingsRepository {
    private var row: UserSettings
    private let readError: RepositoryError?
    private let writeError: RepositoryError?
    private(set) var reads = 0
    private(set) var writes = 0

    init(row: UserSettings, readError: RepositoryError? = nil, writeError: RepositoryError? = nil) {
        self.row = row
        self.readError = readError
        self.writeError = writeError
    }

    func settings() async throws -> UserSettings {
        reads += 1
        if let readError { throw readError }
        return row
    }

    func save(_ settings: UserSettings) async throws {
        writes += 1
        if let writeError { throw writeError }
        row = settings
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
