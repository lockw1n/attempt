import Foundation
import Testing

@testable import RemoteFetch

@Suite("ContentFetcher.refresh")
struct ContentFetcherRefreshTests {
    @Test("A newer edition is fetched, cached, and resolved from the cache afterwards")
    func newerEditionIsCached() async throws {
        let temp = TemporaryCache()
        let served = try formulasPayload(revision: bundledFormulasRevision + 1)
        let fetcher = ContentFetcher(
            transport: RoutingTransport(bodies: [.formulas: served]), cache: temp.cache)

        #expect(await fetcher.refresh(.formulas) == .updated(revision: bundledFormulasRevision + 1))
        #expect(temp.cache.data(for: .formulas) == served)

        let resolved = try #require(fetcher.resolve(.formulas))
        #expect(resolved.origin == .cache)
        #expect(resolved.revision == bundledFormulasRevision + 1)
    }

    @Test("An edition no newer than the one in use is not written")
    func sameEditionIsNotWritten() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            transport: RoutingTransport(
                bodies: [.formulas: try formulasPayload(revision: bundledFormulasRevision)]),
            cache: temp.cache)

        #expect(await fetcher.refresh(.formulas) == .alreadyCurrent(revision: bundledFormulasRevision))
        #expect(temp.cache.data(for: .formulas) == nil)
    }

    @Test("An edition older than the bundled one is not written either")
    func olderEditionIsNotWritten() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            baseURL: "https://example.invalid",
            transport: RoutingTransport(bodies: [.formulas: try formulasPayload(revision: 2)]),
            cache: temp.cache
        ) { _ in try formulasPayload(revision: 5) }

        #expect(await fetcher.refresh(.formulas) == .alreadyCurrent(revision: 5))
        #expect(temp.cache.data(for: .formulas) == nil)
    }

    @Test("Offline: the fetch fails and the bundle still answers — G-2.1, NFR-1.7")
    func offlineFallsBackToTheBundle() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            transport: RoutingTransport(failures: [.formulas: URLError(.notConnectedToInternet)]),
            cache: temp.cache)

        let outcome = await fetcher.refresh(.formulas)
        guard case .failed(.transport(let detail)) = outcome else {
            Issue.record("expected a transport failure, got \(outcome)")
            return
        }
        // The underlying error survives into the outcome: -1009 is "not connected", and the timeout
        // test below asserts a different code from the same field.
        #expect(detail.contains("-1009"))
        #expect(temp.cache.data(for: .formulas) == nil)
        #expect(fetcher.resolve(.formulas)?.origin == .bundle)
    }

    @Test("Offline with a cache: the fetch fails and the cache still answers — G-2.1")
    func offlineFallsBackToTheCache() async throws {
        let temp = TemporaryCache()
        let cached = try formulasPayload(revision: bundledFormulasRevision + 2)
        try temp.cache.write(cached, for: .formulas)

        let fetcher = ContentFetcher(
            transport: RoutingTransport(failures: [.formulas: URLError(.notConnectedToInternet)]),
            cache: temp.cache)

        guard case .failed(.transport) = await fetcher.refresh(.formulas) else {
            Issue.record("expected a transport failure")
            return
        }
        #expect(temp.cache.data(for: .formulas) == cached)
        #expect(fetcher.resolve(.formulas)?.origin == .cache)
    }

    @Test("A timeout falls back like any other transport failure")
    func timeoutFallsBack() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            transport: RoutingTransport(failures: [.formulas: URLError(.timedOut)]), cache: temp.cache)

        let outcome = await fetcher.refresh(.formulas)
        guard case .failed(.transport(let detail)) = outcome else {
            Issue.record("expected a transport failure, got \(outcome)")
            return
        }
        #expect(detail.contains("-1001"))
        #expect(fetcher.resolve(.formulas)?.origin == .bundle)
    }

    @Test("A malformed body is refused and leaves a good cached copy exactly as it was")
    func malformedBodyDoesNotCorruptTheCache() async throws {
        let temp = TemporaryCache()
        let cached = try formulasPayload(revision: bundledFormulasRevision + 2)
        try temp.cache.write(cached, for: .formulas)

        let fetcher = ContentFetcher(
            transport: RoutingTransport(bodies: [.formulas: malformedPayload]), cache: temp.cache)

        guard case .failed(.invalidPayload(let reasons)) = await fetcher.refresh(.formulas) else {
            Issue.record("expected the body to be refused")
            return
        }
        #expect(reasons == ["the payload declares no readable revision"])
        #expect(temp.cache.data(for: .formulas) == cached)
        #expect(fetcher.resolve(.formulas)?.revision == bundledFormulasRevision + 2)
    }

    @Test("A shape this build cannot read is refused however new it claims to be — G-2.3")
    func unreadableSchemaVersionIsRefused() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            transport: RoutingTransport(
                bodies: [.formulas: try formulasPayload(revision: 999, schemaVersion: 99)]),
            cache: temp.cache)

        guard case .failed(.invalidPayload(let reasons)) = await fetcher.refresh(.formulas) else {
            Issue.record("expected the body to be refused")
            return
        }
        #expect(reasons.count == 1)
        #expect(reasons[0].contains("99"))
        #expect(temp.cache.data(for: .formulas) == nil)
        #expect(fetcher.resolve(.formulas)?.origin == .bundle)
    }

    @Test("A base URL that is not one fails before anything is requested")
    func unusableBaseURLIsReportedWithoutAFetch() async throws {
        let temp = TemporaryCache()
        let transport = RecordingTransport(body: try formulasPayload(revision: 9))
        // A broken *scheme*, because `URL(string:)` percent-encodes most other junk rather than
        // refusing it: "not a url" comes back as a perfectly good relative URL.
        let fetcher = ContentFetcher(
            baseURL: "ht tps://lockw1n.github.io", transport: transport, cache: temp.cache)

        #expect(
            await fetcher.refresh(.formulas)
                == .failed(.unusableURL("ht tps://lockw1n.github.io/\(RemoteResource.formulas.path)")))
        #expect(await transport.requested.isEmpty)
    }

    @Test("A payload that cannot be written is reported rather than counted as an update")
    func cacheWriteFailureIsReported() async throws {
        let occupied = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteFetchTests-occupied-\(UUID().uuidString)", isDirectory: false)
        try Data("not a directory".utf8).write(to: occupied)
        defer { try? FileManager.default.removeItem(at: occupied) }

        let fetcher = ContentFetcher(
            transport: RoutingTransport(
                bodies: [.formulas: try formulasPayload(revision: bundledFormulasRevision + 1)]),
            cache: ContentCache(directory: occupied))

        guard case .failed(.cacheWriteFailed) = await fetcher.refresh(.formulas) else {
            Issue.record("expected the write to be reported as a failure")
            return
        }
    }

    @Test("The URL fetched is the base URL and the resource's path, nothing else")
    func fetchesThePublishedURL() async throws {
        let temp = TemporaryCache()
        let transport = RecordingTransport(body: try formulasPayload(revision: 9))
        let fetcher = ContentFetcher(
            baseURL: "https://example.invalid/base", transport: transport, cache: temp.cache)

        _ = await fetcher.refresh(.formulas)
        #expect(
            await transport.requested.map(\.absoluteString)
                == ["https://example.invalid/base/content/v1/formulas.json"])
    }

    @Test("Every resource has a URL under the published base", arguments: RemoteResource.allCases)
    func everyResourceHasAPublishedURL(resource: RemoteResource) throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(transport: RoutingTransport(), cache: temp.cache)
        let url = try #require(fetcher.url(for: resource))
        #expect(url.absoluteString == "https://lockw1n.github.io/attempt/\(resource.path)")
    }

    @Test("Refreshing everything reports on every payload, whatever each one did")
    func refreshAllCoversEveryResource() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            transport: RoutingTransport(
                bodies: [.formulas: try formulasPayload(revision: bundledFormulasRevision + 1)],
                failures: [.flags: URLError(.notConnectedToInternet)]),
            cache: temp.cache)

        let outcomes = await fetcher.refreshAll()
        #expect(Set(outcomes.keys) == Set(RemoteResource.allCases))
        #expect(outcomes[.formulas] == .updated(revision: bundledFormulasRevision + 1))
        guard case .failed(.transport) = outcomes[.flags] else {
            Issue.record("expected the flags fetch to fail")
            return
        }
        // Nothing publishes an exercises body to this transport, so it fails too — and the two
        // failures did not stop the third payload from being cached.
        #expect(temp.cache.data(for: .formulas) != nil)
    }
}
