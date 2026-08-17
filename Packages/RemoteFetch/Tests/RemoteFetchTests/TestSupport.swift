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

/// A `flags.json` payload carrying a chosen minimum — the kill switch's input, at whatever edition
/// the test needs it to outrank the bundled copy at.
func flagsPayload(
    revision: Int,
    minimumSupportedVersion: String,
    schemaVersion: Int = RemoteFlags.supportedSchemaVersion
) throws -> Data {
    try PublishedContent.makeEncoder().encode(
        RemoteFlags(
            schemaVersion: schemaVersion,
            revision: revision,
            minimumSupportedVersion: minimumSupportedVersion
        )
    )
}

/// A real `Bundle` on disk declaring whatever `info` says.
///
/// The `Bundle` overload of `RunningBuild.shortVersionString(in:)` is the one line joining the kill
/// switch to an actual build, and an info dictionary cannot reach it — only a bundle can.
func fixtureBundle(declaring info: [String: Any]) throws -> Bundle {
    let container = temporaryCacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let root = container.appendingPathComponent("Fixture.bundle", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try PropertyListSerialization
        .data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: root.appendingPathComponent("Info.plist"))
    return try #require(Bundle(url: root))
}

/// A resolution over arbitrary bytes, for the gate tests that do not go through a fetcher.
func resolved(_ data: Data, revision: Int = 1) -> ResolvedContent {
    ResolvedContent(data: data, revision: revision, origin: .cache)
}

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
