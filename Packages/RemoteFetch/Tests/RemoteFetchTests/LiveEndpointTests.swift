import Foundation
import Testing

@testable import RemoteFetch

/// The one suite that talks to the real endpoint.
///
/// **Off unless asked for.** CI has to stay hermetic and a suite that fails when GitHub Pages is
/// slow is a suite people learn to ignore — but a fetcher verified only against its own stubs has
/// never met the thing it was written for. Run it with:
///
///     ATTEMPT_LIVE_CONTENT=1 swift test --package-path Packages/RemoteFetch
@Suite(
    "Live endpoint",
    .enabled(if: ProcessInfo.processInfo.environment["ATTEMPT_LIVE_CONTENT"] == "1")
)
struct LiveEndpointTests {
    @Test("Every published payload fetches and passes this build's own validator", arguments: RemoteResource.allCases)
    func publishedPayloadIsUsable(resource: RemoteResource) async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(transport: URLSessionTransport(), cache: temp.cache)
        let url = try #require(fetcher.url(for: resource))

        let data = try await URLSessionTransport().fetch(url)
        let inspection = resource.inspect(data)
        guard case .usable(let revision) = inspection else {
            Issue.record("\(url) served something this build refuses: \(inspection)")
            return
        }
        #expect(revision >= 1)
    }

    @Test("The served catalogue is the bundled bytes, not a re-authored copy")
    func servedCatalogueMatchesTheBundle() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(transport: URLSessionTransport(), cache: temp.cache)
        let url = try #require(fetcher.url(for: .exercises))

        #expect(try await URLSessionTransport().fetch(url) == (try RemoteResource.exercises.bundledData()))
    }

    @Test("A refresh against the live endpoint leaves the app with something to use")
    func liveRefreshResolves() async throws {
        let temp = TemporaryCache()
        let fetcher = ContentFetcher(transport: URLSessionTransport(), cache: temp.cache)

        for (resource, outcome) in await fetcher.refreshAll() {
            if case .failed(let failure) = outcome {
                Issue.record("live refresh of \(resource) failed: \(failure)")
            }
            #expect(fetcher.resolve(resource) != nil)
        }
    }
}
