import Foundation

/// Which leg of the fallback chain produced the bytes a caller is about to use.
public enum ContentOrigin: String, Sendable, CaseIterable {
    /// A payload fetched on an earlier launch and kept on disk.
    case cache

    /// The copy this build ships. Always available — offline, and on first launch after install
    /// (`NFR-1.7`).
    case bundle
}

/// Bytes fit to use, the edition they declare, and where they were found.
public struct ResolvedContent: Sendable, Equatable {
    /// The payload exactly as it was fetched or shipped. Validated, never rewritten: the bytes a
    /// consumer parses are the bytes that were published.
    public let data: Data

    /// The `revision` the payload declares. One or above — a lower one fails validation.
    public let revision: Int

    /// Which leg answered.
    public let origin: ContentOrigin

    /// Creates a resolution.
    public init(data: Data, revision: Int, origin: ContentOrigin) {
        self.data = data
        self.revision = revision
        self.origin = origin
    }
}

/// What one refresh did.
///
/// A refresh never throws. Every case here is a fact about the cache, not an error the caller has to
/// handle: whatever happened, `ContentFetcher.resolve(_:)` still answers (`G-2.3`).
public enum RefreshOutcome: Sendable, Equatable {
    /// A newer edition was fetched, validated and written to the cache.
    case updated(revision: Int)

    /// The endpoint's edition is not newer than the one already in use, so nothing was written.
    case alreadyCurrent(revision: Int)

    /// Nothing was cached, and why.
    case failed(RefreshFailure)
}

/// Why a refresh changed nothing.
public enum RefreshFailure: Sendable, Equatable, CustomStringConvertible {
    /// The base URL and the resource's path did not form a URL. Carries the string that failed.
    case unusableURL(String)

    /// No bytes came back — offline, timed out, or answered with something that is not a payload.
    case transport(String)

    /// Bytes came back that this build will not use, in the payload validator's own words. An
    /// unrecognised `schemaVersion` lands here, which is `G-2.3`'s fall-back trigger.
    case invalidPayload([String])

    /// The payload was fit to use but could not be written, so the next launch will fetch it again.
    case cacheWriteFailed(String)

    /// A line a reader can act on without opening this file.
    public var description: String {
        switch self {
        case .unusableURL(let string):
            "\(string) is not a URL"
        case .transport(let detail):
            "the payload could not be fetched: \(detail)"
        case .invalidPayload(let reasons):
            "the fetched payload was refused: \(reasons.joined(separator: "; "))"
        case .cacheWriteFailed(let detail):
            "the payload could not be cached: \(detail)"
        }
    }
}
