import Foundation
import PowerliftingCore
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// `TR-1.10`'s "created on first launch" and "generated once", over a store that outlives the
// container that made it.
//
// **Every other identity test in this repo runs against one in-memory container**, which cannot
// express a relaunch: an in-memory store dies with the container, so opening a second one produces
// an empty store and mints again by definition. "Minted once" is a claim about what the second
// launch finds on disk, and until this suite nothing looked. The stores here are real files opened
// through `Persistence`'s own container factory — the same call `PersistenceStack(location:)` makes
// for the app — so what is exercised is the production construction path rather than a test seam.
//
// **What it still cannot reach is the app target's own launch sequence**: `AttemptApp` →
// `AppDependencies.adoptStoredPreferences()` → `settings()`. `Attempt.xcodeproj` declares one
// target and no test target, so nothing under `Attempt/App/` is reachable from any test bundle;
// that half is verified by running the app on a simulator and reading the store back, and the run
// is recorded in this task's file rather than here.
@Suite("First launch identity (TR-1.10)")
struct FirstLaunchIdentityTests {
    /// The mint itself, against a store that was genuinely empty a moment ago.
    ///
    /// The sentinel comparison is the anchor: `first == second` is satisfied by two rows that both
    /// failed to mint, and ``SchemaDefaults/unlinkedID`` is exactly what an unminted column holds.
    @Test("A first launch over an empty store file mints exactly one identity")
    func aFirstLaunchMintsOneIdentity() async throws {
        let url = makeTemporaryStoreURL()
        defer { removeStore(at: url) }

        let launch = try RepositoryHarness(at: .file(url))
        let minted = try await launch.stack.settings.settings()

        #expect(minted.userID != SchemaDefaults.unlinkedID)
        #expect(try launch.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    /// The half no in-memory test can make: the identity is on disk, and the next launch finds it.
    ///
    /// The first container is scoped so that the second reads a store nothing is holding open,
    /// which is what a relaunch is. The outcome does not depend on that — SQLite takes several
    /// connections, and `PersistenceStack`'s own note says an export opens a second container over
    /// the live store — but modelling it makes the test say what it means.
    @Test("A relaunch over the same store file finds the identity the first launch minted")
    func aRelaunchFindsTheMintedIdentity() async throws {
        let url = makeTemporaryStoreURL()
        defer { removeStore(at: url) }

        let minted: UUID
        do {
            let firstLaunch = try RepositoryHarness(at: .file(url))
            minted = try await firstLaunch.stack.settings.settings().userID
        }

        let secondLaunch = try RepositoryHarness(at: .file(url))
        let found = try await secondLaunch.stack.settings.settings()

        #expect(found.userID == minted)
        #expect(found.userID != SchemaDefaults.unlinkedID)
        #expect(try secondLaunch.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    /// The task's "a second *first* launch": a restore arriving after this device has bootstrapped.
    ///
    /// The rule is `SettingsRepository/restorePreferences(from:)`'s and is asserted against both
    /// implementations elsewhere — the identity in force wins, the file's preferences land. What is
    /// only checkable here is that the outcome is **durable**: a restore that inserted a second row
    /// rather than writing the one in force would still answer correctly through the container that
    /// made it, because the tiebreak picks the newer row. It is the relaunch that tells the two
    /// apart, and it is the relaunch that the lifter performs.
    @Test("A restore after a launch leaves one identity, and the relaunch still finds it")
    func aRestoreAfterALaunchDoesNotForkTheIdentity() async throws {
        let url = makeTemporaryStoreURL()
        defer { removeStore(at: url) }

        let minted: UUID
        do {
            let firstLaunch = try RepositoryHarness(at: .file(url))
            minted = try await firstLaunch.stack.settings.settings().userID
            try await firstLaunch.stack.settings.restorePreferences(from: backupFromAnotherDevice())
        }

        let secondLaunch = try RepositoryHarness(at: .file(url))
        let found = try await secondLaunch.stack.settings.settings()

        #expect(found.userID == minted)
        // Anchored against the sentinel as well as against `minted`, because the two are not the
        // same claim: a bootstrap that stopped minting satisfies `found.userID == minted` with both
        // sides unset. Found by probe rather than by reading — this assertion was the equality
        // alone, and a perturbation that made the mint hand back `unlinkedID` left it green.
        #expect(found.userID != SchemaDefaults.unlinkedID)
        #expect(found.displayUnit == .pounds)
        #expect(try secondLaunch.store().fetch(FetchDescriptor<UserSettingsEntity>()).count == 1)
    }

    /// A settings row as a backup file carries one: another device's identity, another device's
    /// preferences. The unit is flipped so a restore that landed is visible.
    private func backupFromAnotherDevice() -> UserSettings {
        UserSettings(
            id: UUID(),
            createdAt: fixtureCreatedAt,
            updatedAt: fixtureUpdatedAt,
            deletedAt: nil,
            userID: UUID(),
            displayUnit: .pounds,
            e1RMFormula: .defaultFormula,
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 2500),
            defaultRoundingStrategy: .nearest
        )
    }
}
