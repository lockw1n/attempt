import Foundation

/// The on-disk copy of the last payload this build accepted (`TR-0.5.3`).
///
/// **An entry never expires.** `G-2.1` and `NFR-1.7` require the app to work with no network at
/// all, indefinitely, so a time-to-live would delete working content to make room for content that
/// may never arrive. An entry is replaced only by a strictly newer edition, and only after the
/// payload's own validator has accepted it — a refused body leaves whatever was already there
/// untouched.
public struct ContentCache: Sendable {
    /// The directory the payloads sit in. Created on the first write, not on construction.
    public let directory: URL

    /// Creates a cache over `directory`.
    public init(directory: URL) {
        self.directory = directory
    }

    /// The default location: a private subdirectory of the app's caches directory.
    ///
    /// Caches rather than Application Support, because every entry is re-fetchable and the bundled
    /// copy sits behind it — the system reclaiming this directory costs a fetch, never a working
    /// app. The `v1` component is the *cache* layout's, not a payload's `schemaVersion`: a build
    /// that changes what it stores here starts a new directory rather than reading the old one.
    public static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RemoteContent", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    /// The cached bytes for `resource`, or `nil` when there are none to be had.
    ///
    /// A miss and an unreadable file answer the same way on purpose: both mean "nothing usable
    /// here", and falling back is the only response either one has.
    public func data(for resource: RemoteResource) -> Data? {
        try? Data(contentsOf: fileURL(for: resource))
    }

    /// Replaces `resource`'s cached copy.
    ///
    /// Atomic: a write interrupted part-way leaves the previous copy in place rather than half of
    /// the new one, which is the difference between falling back and corrupting.
    public func write(_ data: Data, for resource: RemoteResource) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: resource), options: .atomic)
    }

    /// Discards `resource`'s cached copy.
    ///
    /// A missing entry is not a failure and neither is an unremovable one: this asks for a state —
    /// nothing usable cached — and every path that fails to reach it leaves the caller where it
    /// already was, falling back.
    public func remove(_ resource: RemoteResource) {
        try? FileManager.default.removeItem(at: fileURL(for: resource))
    }

    /// Where `resource`'s bytes sit, whether or not anything is there yet.
    public func fileURL(for resource: RemoteResource) -> URL {
        directory.appendingPathComponent(resource.cacheFileName, isDirectory: false)
    }
}
