import Foundation
import PowerliftingCore
import RemoteContent

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

/// A cache over a directory of its own, removed when this value goes away.
final class TemporaryCache {
    let cache: ContentCache

    init() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteFetchTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        cache = ContentCache(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: cache.directory)
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
