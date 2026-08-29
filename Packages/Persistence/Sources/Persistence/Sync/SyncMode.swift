import Foundation

/// Whether a store mirrors to CloudKit, and to which container (`FR-1.12.1`, `OUT-0.2`).
///
/// **`.disabled` is the default everywhere and that is load-bearing**, not tidiness. Every test,
/// preview and harness in this repo opens a store through the same initializer, and T-0.33 measured
/// what `.private(…)` does to a process that has no entitlement behind it: the container
/// initializes, then CoreData's mirroring delegate traps on `com.apple.coredata.cloudkit.queue` and
/// takes the process down inside 50 ms — whether the schema is valid or not, three runs of three.
/// A default that mirrored would therefore not fail a test; it would kill the runner.
public enum SyncMode: Equatable, Sendable {
    /// No mirroring. The store is local and nothing observes it.
    case disabled

    /// Mirror to the private database of the named CloudKit container.
    ///
    /// - Parameter containerIdentifier: The `iCloud.`-prefixed container the entitlement grants.
    case privateDatabase(containerIdentifier: String)
}

/// A store that was asked to do something it cannot.
public enum StoreConfigurationError: Error, Equatable, Sendable {
    /// An in-memory store was asked to mirror.
    ///
    /// **Refused rather than quietly downgraded.** An in-memory store has no file for the mirroring
    /// delegate to track, so honouring the request is impossible either way — but a silent
    /// downgrade is how a test that believes it is exercising sync passes while exercising nothing,
    /// which is the failure mode `check-cloudkit.sh` exists to prevent one layer up.
    case inMemoryStoreCannotSync
}
