import Foundation
import SwiftData

// THE ONE FILE IN THIS REPO ALLOWED TO ENABLE MIRRORING (FR-1.12.1, OUT-0.2).
//
// `scripts/check-cloudkit.sh` bans the enabling spellings everywhere and names this path as its
// single Swift exception — and its check 5 *requires* the spelling to still be here, so the
// exemption cannot quietly become dead while the guard goes on reporting green.
//
// IT BUILDS THE WHOLE CONFIGURATION RATHER THAN RETURNING A DATABASE, and that is the guard's
// doing rather than a design preference. A function returning `CloudKitDatabase` reads better and
// spells the call `.private(id)` with no `cloudKitDatabase:` label in front of it — which the ban
// regex, being line-based and anchored on the label, cannot see at all. The first version of this
// file was written that way; check 5 failed it within a minute, correctly, for being an exemption
// that excused a construct no longer present. A file exempted from a ban has to contain the thing
// it is exempted for, or the ban has a hole in it that reports green.
//
// It stays a file of its own so the allowlist never has to name PersistenceStack.swift, which is
// the file every store in the app is opened through. An exemption that wide is not an exemption.

/// The store configuration for one location and sync choice.
///
/// - Parameters:
///   - location: Where the store lives.
///   - mode: Whether it mirrors, and to which container.
/// - Returns: The configuration to build the container with.
func makeConfiguration(at location: StoreLocation, sync mode: SyncMode) -> ModelConfiguration {
    switch (location, mode) {
    case (.applicationDefault, .disabled):
        return ModelConfiguration(cloudKitDatabase: .none)
    case (.applicationDefault, .privateDatabase(let containerIdentifier)):
        return ModelConfiguration(cloudKitDatabase: .private(containerIdentifier))
    case (.file(let url), .disabled):
        return ModelConfiguration(url: url, cloudKitDatabase: .none)
    case (.file(let url), .privateDatabase(let containerIdentifier)):
        return ModelConfiguration(url: url, cloudKitDatabase: .private(containerIdentifier))
    case (.inMemory, _):
        // Unreachable with a sync mode: `makeModelContainer(at:sync:)` refuses that pair before it
        // gets here, because an in-memory store has no file for the mirroring delegate to track.
        return ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    }
}
