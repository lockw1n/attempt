import Foundation
import PowerliftingCore
import RemoteContent
import Testing

@testable import RemoteFetch

// MARK: - Transports

/// A transport that answers per resource, matched on the path the fetcher asked for.
///
/// One stub for every case in the suite: a body, a thrown `URLError`, or neither — which is itself
/// the "asked for something nobody publishes" case.
struct RoutingTransport: ContentTransport {
    var bodies: [RemoteResource: Data] = [:]
    var failures: [RemoteResource: URLError] = [:]

    func fetch(_ url: URL) async throws -> Data {
        guard
            let resource = RemoteResource.allCases.first(where: { url.absoluteString.hasSuffix($0.path) })
        else {
            throw URLError(.unsupportedURL)
        }
        if let failure = failures[resource] { throw failure }
        guard let body = bodies[resource] else { throw URLError(.fileDoesNotExist) }
        return body
    }
}

/// A transport that records every URL it is handed. An actor because a test reads the record from
/// outside the task that wrote it.
actor RecordingTransport: ContentTransport {
    private(set) var requested: [URL] = []
    private let body: Data

    init(body: Data) {
        self.body = body
    }

    func fetch(_ url: URL) async throws -> Data {
        requested.append(url)
        return body
    }
}

/// A transport whose fetch suspends until the test lets it finish.
///
/// This is what makes "launch is not gated on the fetch" a deterministic assertion rather than a
/// race: the test holds a fetch open and calls `resolve(_:)` while it is in flight.
actor BlockingTransport: ContentTransport {
    private var isInFlight = false
    private var isReleased = false
    private var waitingForCall: CheckedContinuation<Void, Never>?
    private var waitingForRelease: CheckedContinuation<Void, Never>?

    func fetch(_ url: URL) async throws -> Data {
        isInFlight = true
        waitingForCall?.resume()
        waitingForCall = nil
        if !isReleased {
            await withCheckedContinuation { waitingForRelease = $0 }
        }
        throw URLError(.cancelled)
    }

    /// Returns once a fetch is in flight.
    func waitUntilInFlight() async {
        if isInFlight { return }
        await withCheckedContinuation { waitingForCall = $0 }
    }

    /// Lets the held fetch finish.
    func release() {
        isReleased = true
        waitingForRelease?.resume()
        waitingForRelease = nil
    }
}

// MARK: - Fixtures

/// The root every temporary cache in this suite sits under, cleared once when the run starts.
///
/// Clearing it *here* rather than in a `deinit` per cache is deliberate. ARC may release a local as
/// soon as its last mention, and in several tests below that comes before the `resolve` calls that
/// need the directory to still be there — so a `deinit` is a lifetime the optimiser is free to
/// shorten, and the tests would pass in debug and fail in release. A run cleans up after the
/// previous one instead, which needs no lifetime guarantee at all.
let temporaryCacheRoot: URL = {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RemoteFetchTests", isDirectory: true)
    try? FileManager.default.removeItem(at: root)
    return root
}()

/// A cache over a directory of its own.
struct TemporaryCache {
    let cache: ContentCache

    init() {
        cache = ContentCache(
            directory: temporaryCacheRoot.appendingPathComponent(
                UUID().uuidString, isDirectory: true))
    }
}

/// A `formulas.json` payload at a chosen edition — the resource every fetcher test uses, because it
/// is the one whose bytes a test can produce at any revision without authoring a catalogue.
func formulasPayload(
    revision: Int,
    schemaVersion: Int = RemoteFormulas.supportedSchemaVersion
) throws -> Data {
    try PublishedContent.makeEncoder().encode(
        RemoteFormulas(
            schemaVersion: schemaVersion,
            revision: revision,
            verified: false,
            rpeTable: .standard
        )
    )
}

/// The edition `formulas.json` ships compiled into this build.
let bundledFormulasRevision = RemoteFormulas.published.revision

/// Bytes that are not a JSON document at all.
let malformedPayload = Data("{ this is not a payload".utf8)

extension Data {
    /// The first key in this JSON document, whatever whitespace the encoder used.
    ///
    /// Key *order* is how a sorted encoder is told from a plain one from the outside: a plain
    /// `JSONEncoder` emits declaration order, which puts `schemaVersion` first in both payloads
    /// this build encodes.
    var firstJSONKey: String? {
        guard
            let text = String(bytes: self, encoding: .utf8),
            let open = text.firstIndex(of: "\""),
            let close = text[text.index(after: open)...].firstIndex(of: "\"")
        else { return nil }
        return String(text[text.index(after: open)..<close])
    }
}

/// The file's identity on disk, which is what changes when a write replaces a file rather than
/// rewriting it in place.
func inodeNumber(of url: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
}
