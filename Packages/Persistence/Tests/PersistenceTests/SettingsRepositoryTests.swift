import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

@Suite("SettingsRepository over SwiftData")
struct SettingsRepositoryTests {
    @Test("The first call creates the row; the second returns the same identity")
    func settingsIsFindOrCreate() async throws {
        let harness = try RepositoryHarness()

        let first = try await harness.stack.settings.settings()
        let second = try await harness.stack.settings.settings()

        #expect(first.userID == second.userID)
        #expect(first.id == second.id)
        #expect(first.userID != SchemaDefaults.unlinkedID)
        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    /// `FR-1.9.1`'s tile selection is the one preference where "never chosen" and "chose none" are
    /// different answers, so the round trip has to keep all three states apart — and this is also
    /// what says SwiftData stores the column at all.
    @Test("The dashboard selection round-trips, empty and absent included")
    func thedashboardSelectionRoundTrips() async throws {
        let harness = try RepositoryHarness()
        let stored = try await harness.stack.settings.settings()
        #expect(stored.dashboardExerciseIDs == nil)

        let chosen = [UUID(), UUID()]
        try await harness.stack.settings.save(stored.tiling(chosen))
        #expect(try await harness.stack.settings.settings().dashboardExerciseIDs == chosen)

        try await harness.stack.settings.save(stored.tiling([]))
        #expect(try await harness.stack.settings.settings().dashboardExerciseIDs == [])
    }

    @Test("A second repository over the same store finds the row rather than minting a second id")
    func aSecondRepositoryDoesNotMintASecondIdentity() async throws {
        let harness = try RepositoryHarness()
        let first = try await harness.stack.settings.settings()

        let other = SwiftDataSettingsRepository(modelContainer: harness.container)
        let second = try await other.settings()

        #expect(first.userID == second.userID)
        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    @Test("Two repositories bootstrapping at once still mint one identity")
    func concurrentBootstrapDoesNotForkTheIdentity() async throws {
        // An actor serialises its own calls and nothing else: two repositories over one container
        // hold two contexts, and unserialised both see an empty store and both insert. Measured at
        // 8 of 8 before the lock, so this is repeated rather than run once.
        for _ in 0..<8 {
            let harness = try RepositoryHarness()
            let first = SwiftDataSettingsRepository(modelContainer: harness.container)
            let second = SwiftDataSettingsRepository(modelContainer: harness.container)

            async let left = try first.settings()
            async let right = try second.settings()
            let (one, two) = try await (left, right)

            #expect(one.userID == two.userID)
            #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
        }
    }

    @Test("A soft-deleted settings row is found, not stepped over")
    func aDeletedRowStillCountsAsFound() async throws {
        let harness = try RepositoryHarness()
        let original = try await harness.stack.settings.settings()

        // This protocol has no delete, so only a foreign row can be in this state. Creating beside
        // it would fork the anonymous identity, which is the failure that cannot be undone.
        let context = harness.store()
        for row in try context.fetch(FetchDescriptor<UserSettingsEntity>()) { row.markDeleted() }
        try context.save()

        let found = try await harness.stack.settings.settings()

        #expect(found.userID == original.userID)
        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    @Test("Two settings rows resolve by the tiebreak and no third is created")
    func twoRowsResolveWithoutCreatingAThird() async throws {
        let harness = try RepositoryHarness()
        let older = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()
        let newer = UUID(uuidString: "33333333-3333-3333-3333-333333333333") ?? UUID()
        try harness.seed([
            settingsRow(userID: older, unit: .kilograms, updatedAt: fixtureCreatedAt),
            settingsRow(userID: newer, unit: .pounds, updatedAt: fixtureUpdatedAt),
        ])

        let read = try await harness.stack.settings.settings()

        #expect(read.userID == newer)
        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 2)
    }

    @Test("A save carrying a different userID is refused")
    func theIdentityCannotBeMoved() async throws {
        let harness = try RepositoryHarness()
        let settings = try await harness.stack.settings.settings()
        let impostor = variant(of: settings, id: settings.id, userID: UUID())

        await #expect(
            throws: RepositoryError.identityAlreadyEstablished(recordID: impostor.id)
        ) { try await harness.stack.settings.save(impostor) }

        #expect(try await harness.stack.settings.settings().displayUnit == .kilograms)
    }

    @Test("A save with a fresh record id writes the existing row rather than adding one")
    func theSingletonSaveDoesNotKeyOnTheRecordID() async throws {
        let harness = try RepositoryHarness()
        let settings = try await harness.stack.settings.settings()
        let rebuilt = variant(of: settings, id: UUID(), userID: settings.userID)

        try await harness.stack.settings.save(rebuilt)

        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
        let read = try await harness.stack.settings.settings()
        #expect(read.displayUnit == .pounds)
        #expect(read.id == settings.id)
        #expect(read.userID == settings.userID)
    }

    /// `FR-1.11.3`'s restore onto a device that has already bootstrapped. The rule itself is a
    /// conformance claim and is made against both implementations in `RepositoryFakes`; what is
    /// store-shaped, and what only the real store can get wrong, is the row COUNT — nothing in the
    /// schema stops a second settings row, and a restore that inserted instead of writing would
    /// fork the identity exactly as a second bootstrap would.
    @Test("A restore over a minted row writes it rather than adding a second")
    func aRestoreDoesNotAddASecondRow() async throws {
        let harness = try RepositoryHarness()
        let minted = try await harness.stack.settings.settings()
        let fromAnotherDevice = variant(of: minted, id: UUID(), userID: UUID())

        try await harness.stack.settings.restorePreferences(from: fromAnotherDevice)

        #expect(try harness.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
        let read = try await harness.stack.settings.settings()
        #expect(read.userID == minted.userID)
        #expect(read.id == minted.id)
        #expect(read.displayUnit == .pounds)
    }

    @Test("A save into an empty store honours the identity the record arrived with")
    func aRestoreKeepsItsIdentity() async throws {
        let harness = try RepositoryHarness()
        let restored = UserSettings(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            userID: UUID(),
            displayUnit: .pounds,
            e1RMFormula: .defaultFormula,
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 5000),
            defaultRoundingStrategy: .down
        )

        try await harness.stack.settings.save(restored)

        let read = try await harness.stack.settings.settings()
        #expect(read.userID == restored.userID)
        #expect(read.createdAt == fixtureCreatedAt)
    }
}

/// A settings row, for the two-rows case the repository cannot produce.
private func settingsRow(userID: UUID, unit: MassUnit, updatedAt: Date) -> UserSettingsEntity {
    UserSettingsEntity(
        userID: userID,
        displayUnit: unit,
        e1RMFormula: .defaultFormula,
        theme: .system,
        defaultRoundingIncrementGrams: 2500,
        defaultRoundingStrategy: .nearest,
        updatedAt: updatedAt
    )
}

/// `settings` with a different id and identity, and the display unit flipped so a save that lands
/// is visible.
private func variant(of settings: UserSettings, id: UUID, userID: UUID) -> UserSettings {
    UserSettings(
        id: id,
        createdAt: settings.createdAt,
        updatedAt: settings.updatedAt,
        deletedAt: nil,
        userID: userID,
        displayUnit: .pounds,
        e1RMFormula: settings.e1RMFormula,
        theme: settings.theme,
        defaultRoundingIncrement: settings.defaultRoundingIncrement,
        defaultRoundingStrategy: settings.defaultRoundingStrategy
    )
}
