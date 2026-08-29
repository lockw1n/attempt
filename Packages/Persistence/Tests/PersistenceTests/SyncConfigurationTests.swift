import CoreData
import Foundation
import RepositoryInterface
import SwiftData
import Testing

@testable import Persistence

// FR-1.12.1. The three seams activation added, none of which a container has to be built to reach.
//
// WHY A CONFIGURATION AND NOT A CONTAINER. T-0.33 measured what `.private(…)` does to a process with
// no entitlement behind it: CoreData's mirroring delegate traps on its own queue and takes the
// process down. `makeConfiguration(at:sync:)` builds a value and opens nothing, and
// `makeModelContainer(at:sync:)` refuses the in-memory pair before it reaches SwiftData, so both are
// reachable from a test runner that must not mirror.
//
// WHAT `cloudKitContainerIdentifier` IS DOING HERE. `ModelConfiguration.CloudKitDatabase` is not
// `Equatable`, so the choice cannot be compared directly. The identifier is what it resolves to and
// is `nil` for `.none`, which separates the two answers this function exists to give — and separates
// them by the string the entitlement has to match, not merely by "some kind of sync".

@Suite("Sync configuration")
struct SyncConfigurationTests {
    private static let container = "iCloud.example.App"
    private static let url = URL(fileURLWithPath: "/tmp/does-not-need-to-exist.store")

    @Test("The app's own store mirrors to the named container when asked")
    func applicationDefaultMirrors() {
        let configuration = makeConfiguration(
            at: .applicationDefault, sync: .privateDatabase(containerIdentifier: Self.container))

        #expect(configuration.cloudKitContainerIdentifier == "iCloud.example.App")
    }

    @Test("The app's own store names no container when sync is off")
    func applicationDefaultDisabledMirrorsNothing() {
        let configuration = makeConfiguration(at: .applicationDefault, sync: .disabled)

        // Anchored to nil rather than to another configuration's identifier: two disabled
        // configurations would agree by both being empty.
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }

    @Test("A file store mirrors, and still opens the file it was given")
    func fileStoreMirrors() {
        let configuration = makeConfiguration(
            at: .file(Self.url), sync: .privateDatabase(containerIdentifier: Self.container))

        #expect(configuration.cloudKitContainerIdentifier == "iCloud.example.App")
        #expect(configuration.url.lastPathComponent == "does-not-need-to-exist.store")
        #expect(configuration.isStoredInMemoryOnly == false)
    }

    @Test("A file store names no container when sync is off")
    func fileStoreDisabledMirrorsNothing() {
        let configuration = makeConfiguration(at: .file(Self.url), sync: .disabled)

        #expect(configuration.cloudKitContainerIdentifier == nil)
        #expect(configuration.url.lastPathComponent == "does-not-need-to-exist.store")
    }

    @Test("An in-memory store is in memory and mirrors nothing")
    func inMemoryNeverMirrors() {
        let configuration = makeConfiguration(at: .inMemory, sync: .disabled)

        #expect(configuration.isStoredInMemoryOnly == true)
        #expect(configuration.cloudKitContainerIdentifier == nil)
    }

    // THE REFUSAL, AT BOTH DOORS. This is the guard standing between every test and preview in this
    // repo and T-0.33's process-killing trap, so "it refuses" is the whole of its contract — and a
    // contract that is only about refusing is the one a green suite says least about.

    @Test("Asking an in-memory store to mirror is refused rather than quietly downgraded")
    func inMemoryMirroringIsRefused() {
        #expect(throws: StoreConfigurationError.inMemoryStoreCannotSync) {
            try makeModelContainer(
                at: .inMemory, sync: .privateDatabase(containerIdentifier: Self.container))
        }
    }

    @Test("The stack refuses the same pair, which is the door outside this module")
    func theStackRefusesInMemoryMirroring() {
        #expect(throws: StoreConfigurationError.inMemoryStoreCannotSync) {
            try PersistenceStack(
                location: .inMemory, sync: .privateDatabase(containerIdentifier: Self.container))
        }
    }

    @Test("An in-memory store with sync off still opens")
    func inMemoryWithoutSyncStillOpens() throws {
        // The other half of the refusal: a guard that fired on the pair AND on the ordinary case
        // would pass the test above while breaking every preview in the app.
        _ = try PersistenceStack(location: .inMemory)
    }
}

// FR-1.12.2. CoreData's three event types in this app's words. The mapping is what the status line
// reads, so an import/export swap would draw "Sending changes…" while records arrive — and nothing
// downstream of here could tell.

@Suite("CloudKit event vocabulary")
struct CloudKitSyncEventsTests {
    @Test("Setup is not a transfer")
    func setupIsSetup() {
        #expect(CloudKitSyncEvents.activity(for: .setup) == SyncActivity.setup)
    }

    @Test("An import is records arriving, not leaving")
    func importIsDownload() {
        #expect(CloudKitSyncEvents.activity(for: .import) == SyncActivity.download)
    }

    @Test("An export is records leaving, not arriving")
    func exportIsUpload() {
        #expect(CloudKitSyncEvents.activity(for: .export) == SyncActivity.upload)
    }

    @Test("The three types map to three different activities")
    func theMappingIsInjective() {
        // What a per-case test cannot say on its own: a mapping that answered `.setup` for
        // everything satisfies the first case above and is the failure this module's four-way
        // unknown-enum rule makes tempting, since `.setup` is also the `@unknown default`.
        let mapped = [
            NSPersistentCloudKitContainer.EventType.setup, .import, .export,
        ].map(CloudKitSyncEvents.activity(for:))

        #expect(mapped == [.setup, .download, .upload])
    }
}
