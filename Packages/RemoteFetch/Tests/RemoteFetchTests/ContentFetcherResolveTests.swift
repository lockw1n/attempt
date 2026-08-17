import Foundation
import Testing

@testable import RemoteFetch

/// `resolve(_:)` — the launch path. Every test here runs with a transport that would answer, and
/// none of them lets it: that is the point of the half.
@Suite("ContentFetcher.resolve")
struct ContentFetcherResolveTests {
    @Test("A fresh install resolves every payload from the bundle", arguments: RemoteResource.allCases)
    func freshInstallResolvesFromTheBundle(resource: RemoteResource) throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(transport: RoutingTransport(), cache: temp.cache)
        let resolved = try #require(fetcher.resolve(resource))
        #expect(resolved.origin == .bundle)
        #expect(resolved.revision >= 1)
        #expect(resolved.data == (try resource.bundledData()))
    }

    @Test("A cache holding a newer edition wins")
    func newerCacheWins() throws {
        let temp = TemporaryCache()
        let cached = try formulasPayload(revision: bundledFormulasRevision + 1)
        try temp.cache.write(cached, for: .formulas)

        let resolved = try #require(
            ContentFetcher(transport: RoutingTransport(), cache: temp.cache).resolve(.formulas))
        #expect(resolved.origin == .cache)
        #expect(resolved.revision == bundledFormulasRevision + 1)
        #expect(resolved.data == cached)
    }

    @Test("A cache holding the same edition loses to the bundle")
    func tieGoesToTheBundle() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: bundledFormulasRevision), for: .formulas)

        let resolved = try #require(
            ContentFetcher(transport: RoutingTransport(), cache: temp.cache).resolve(.formulas))
        #expect(resolved.origin == .bundle)
        #expect(resolved.revision == bundledFormulasRevision)
    }

    @Test("A bundle newer than the cache wins — the app-update case")
    func newerBundleOutranksAStaleCache() throws {
        let temp = TemporaryCache()
        try temp.cache.write(try formulasPayload(revision: 2), for: .formulas)

        let fetcher = ContentFetcher(
            baseURL: "https://example.invalid",
            transport: RoutingTransport(),
            cache: temp.cache
        ) { _ in try formulasPayload(revision: 5) }

        let resolved = try #require(fetcher.resolve(.formulas))
        #expect(resolved.origin == .bundle)
        #expect(resolved.revision == 5)
    }

    @Test("A malformed cached payload falls back to the bundle")
    func malformedCacheFallsBack() throws {
        let temp = TemporaryCache()
        try temp.cache.write(malformedPayload, for: .formulas)

        let resolved = try #require(
            ContentFetcher(transport: RoutingTransport(), cache: temp.cache).resolve(.formulas))
        #expect(resolved.origin == .bundle)
    }

    @Test("A cached payload in a shape this build cannot read falls back to the bundle")
    func unreadableSchemaVersionInCacheFallsBack() throws {
        let temp = TemporaryCache()
        // Newer by revision, so only the schemaVersion refusal can send this back to the bundle.
        try temp.cache.write(
            try formulasPayload(revision: bundledFormulasRevision + 3, schemaVersion: 99), for: .formulas)

        let resolved = try #require(
            ContentFetcher(transport: RoutingTransport(), cache: temp.cache).resolve(.formulas))
        #expect(resolved.origin == .bundle)
        #expect(resolved.revision == bundledFormulasRevision)
    }

    @Test("A cache answers when the bundle cannot be read")
    func cacheAnswersWithoutABundle() throws {
        let temp = TemporaryCache()
        let cached = try formulasPayload(revision: 2)
        try temp.cache.write(cached, for: .formulas)

        let fetcher = ContentFetcher(
            baseURL: "https://example.invalid",
            transport: RoutingTransport(),
            cache: temp.cache
        ) { _ in throw URLError(.fileDoesNotExist) }

        let resolved = try #require(fetcher.resolve(.formulas))
        #expect(resolved.origin == .cache)
        #expect(resolved.revision == 2)
    }

    @Test("Neither leg leaves nothing to resolve")
    func nothingUsableResolvesToNil() {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(
            baseURL: "https://example.invalid",
            transport: RoutingTransport(),
            cache: temp.cache
        ) { _ in throw URLError(.fileDoesNotExist) }

        #expect(fetcher.resolve(.formulas) == nil)
    }

    @Test("Resolving consults no transport at all — G-2.3")
    func resolveNeverReachesTheNetwork() async throws {
        let temp = TemporaryCache()
        let transport = RecordingTransport(body: try formulasPayload(revision: 99))
        let fetcher = ContentFetcher(transport: transport, cache: temp.cache)

        for resource in RemoteResource.allCases {
            _ = fetcher.resolve(resource)
        }
        #expect(await transport.requested.isEmpty)
    }

    @Test("A fetch in flight does not gate what resolve answers — G-2.3, NFR-1.7")
    func resolveIsNotGatedOnAnInFlightFetch() async throws {
        let temp = TemporaryCache()
        let transport = BlockingTransport()
        let fetcher = ContentFetcher(transport: transport, cache: temp.cache)

        let refresh = Task { await fetcher.refresh(.formulas) }
        await transport.waitUntilInFlight()

        // The held fetch has not returned and cannot: `resolve` is synchronous and has nothing to
        // await, so this line either answers now or the test never finishes.
        let resolved = try #require(fetcher.resolve(.formulas))
        #expect(resolved.origin == .bundle)

        await transport.release()
        guard case .failed(.transport) = await refresh.value else {
            Issue.record("expected the released fetch to fail")
            return
        }
    }
}
