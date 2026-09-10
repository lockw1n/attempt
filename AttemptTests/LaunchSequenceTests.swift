import Foundation
import Persistence
import RepositoryInterface
import Testing

@testable import Attempt

/// The app's own launch sequence, over a store on disk (`TR-1.10`, `TR-1.12`).
///
/// **What this reaches that no package suite can.** `PersistenceTests.FirstLaunchIdentityTests`
/// already holds `TR-1.10` at the `PersistenceStack` level and says so: what it could not reach is
/// `AppDependencies` — the composition root, the sync decision made before anything opens, the seed
/// import and the preference adoption that run on every launch. Those live in the app target, which
/// had no test bundle until this one. The claim here is therefore about the *sequence*, not about
/// the mint: the mint is `Persistence`'s and is tested there.
///
/// **Serialized, and it moves a real preference.** `AppDependencies` reads
/// `AppSyncControl.isEnabled()` against `UserDefaults.standard` before it opens anything, and for a
/// file store the answer decides whether the container mirrors — so a test opening a `.file` store
/// with the shipped default in force would mirror its fixture into the signed-in iCloud account.
/// ``SyncPreferenceGuard`` turns it off for the duration and puts back exactly what was there.
/// Because that is process-wide state, the suite runs one test at a time.
@MainActor
@Suite("Launch sequence (TR-1.10, TR-1.12)", .serialized)
struct LaunchSequenceTests {
    /// The whole of `AttemptApp`'s launch work, minus the window: open, seed, adopt.
    ///
    /// - Parameter url: Where the store file goes.
    /// - Returns: What the launch produced.
    private func launch(at url: URL) async -> AppDependencies {
        let dependencies = AppDependencies(location: .file(url))
        // The same two calls `AttemptApp` attaches to the root view, in the order it attaches them.
        await dependencies.importSeedCatalogue()
        await dependencies.adoptStoredPreferences()
        return dependencies
    }

    /// A cold launch opens the store, seeds it, and mints one identity.
    ///
    /// **The catalogue assertion is here rather than in its own test** because it is the half of
    /// `NFR-1.7` that only a launch can make: `SeedImporter` is tested against a repository, and
    /// what is unproven anywhere else is that the bundled payload is in the *app* bundle at all —
    /// a resource that failed to copy produces an empty catalogue and a launch that reports nothing.
    @Test("A cold launch opens the store, seeds the catalogue and mints an identity")
    func aColdLaunchOpensSeedsAndMints() async throws {
        let guarded = SyncPreferenceGuard()
        defer { guarded.restore() }
        let url = TemporaryStore.makeURL()
        defer { TemporaryStore.remove(at: url) }

        let dependencies = await launch(at: url)

        guard case .open(let repositories, _) = dependencies.state else {
            Issue.record("the store did not open: \(dependencies.state)")
            return
        }
        let settings = try await repositories.settings.settings()
        // The all-zero UUID is `Persistence`'s `SchemaDefaults.unlinkedID` — what an unminted
        // column holds. Spelled out rather than imported: that constant is `internal` to
        // `Persistence`, and a sentinel a test reads from the code under test agrees with
        // whatever that code does.
        #expect(settings.userID != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        // Anchored to a literal rather than to another read of the same column: `count > 0` is
        // satisfied by a store that seeded one row, and the shipped catalogue holds hundreds.
        let catalogue = try await repositories.exercises.exercises(includingDeleted: false)
        #expect(catalogue.count > 100)
    }

    /// A relaunch over the same file finds the identity rather than minting a second one.
    ///
    /// The first launch is scoped so the second reads a store nothing is holding open, which is
    /// what a relaunch is.
    @Test("A relaunch through AppDependencies finds the identity the first launch minted")
    func aRelaunchFindsTheMintedIdentity() async throws {
        let guarded = SyncPreferenceGuard()
        defer { guarded.restore() }
        let url = TemporaryStore.makeURL()
        defer { TemporaryStore.remove(at: url) }

        let minted: UUID
        do {
            let first = await launch(at: url)
            guard case .open(let repositories, _) = first.state else {
                Issue.record("the first launch did not open the store: \(first.state)")
                return
            }
            minted = try await repositories.settings.settings().userID
        }

        let second = await launch(at: url)
        guard case .open(let repositories, _) = second.state else {
            Issue.record("the relaunch did not open the store: \(second.state)")
            return
        }
        #expect(try await repositories.settings.settings().userID == minted)

        // The anchor. `first == second` is also satisfied by a mint that returns a constant, and a
        // constant `userID` is precisely what `TR-1.10` exists to prevent — it is the seam Phase 5's
        // `FR-5.1.2` claims an account against. A second store file must mint something else.
        let other = TemporaryStore.makeURL()
        defer { TemporaryStore.remove(at: other) }
        let elsewhere = await launch(at: other)
        guard case .open(let otherRepositories, _) = elsewhere.state else {
            Issue.record("the second store did not open: \(elsewhere.state)")
            return
        }
        #expect(try await otherRepositories.settings.settings().userID != minted)
    }
}

/// `AppSyncControl`'s preference, turned off for the length of a test and then put back.
///
/// **Restoring the absence matters as much as restoring a value.** `AppSyncControl.isEnabled(in:)`
/// answers `defaultEnabled` for a key that was never written and the stored value otherwise, so a
/// guard that "restored" by writing `true` would leave a device that had never been asked looking
/// like one that had chosen — CLAUDE.md's own `simctl defaults` trap, one layer up.
@MainActor
struct SyncPreferenceGuard {
    /// What the key held before, or `nil` if it was never written.
    private let previous: Any?

    /// Turns sync off for the caller.
    init() {
        previous = UserDefaults.standard.object(forKey: AppSyncControl.defaultsKey)
        UserDefaults.standard.set(false, forKey: AppSyncControl.defaultsKey)
    }

    /// Puts the key back exactly as it was.
    func restore() {
        if let previous {
            UserDefaults.standard.set(previous, forKey: AppSyncControl.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppSyncControl.defaultsKey)
        }
    }
}

/// A store file of its own, under the test process's temporary directory.
enum TemporaryStore {
    /// A path nothing has written to.
    ///
    /// - Returns: The URL a store may be opened at.
    static func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AttemptTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    /// Removes a store and the two files SQLite keeps beside it.
    ///
    /// - Parameter url: The store's own URL.
    static func remove(at url: URL) {
        for suffix in ["", "-shm", "-wal"] {
            let path = url.deletingPathExtension().lastPathComponent
            let sibling = url.deletingLastPathComponent()
                .appendingPathComponent(path)
                .appendingPathExtension("store" + suffix)
            try? FileManager.default.removeItem(at: sibling)
        }
    }
}
