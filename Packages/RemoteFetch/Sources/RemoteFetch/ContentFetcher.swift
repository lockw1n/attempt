import Foundation
import RemoteContent

/// The `TR-0.5.3` fetcher: what to use *now*, and — separately — a check for something newer.
///
/// **The two halves are deliberately different shapes.** ``resolve(_:)`` is synchronous and holds no
/// transport, so no launch path can await a network call through it; that is `G-2.3` and `NFR-1.7`
/// enforced by the signature rather than by a convention anyone has to keep. ``refresh(_:)`` is the
/// async half and never throws: every failure means "keep using what ``resolve(_:)`` already
/// answered".
///
/// **The freshness policy `TR-0.5.2` leaves open.** Check once per launch, off the launch path;
/// nothing polls, and no screen waits. A cached entry has no expiry — see ``ContentCache``. The
/// endpoint fixes `Cache-Control` at around ten minutes, so a second check inside one launch could
/// not see anything the first did not.
public struct ContentFetcher: Sendable {
    private let baseURL: String
    private let transport: any ContentTransport
    private let cache: ContentCache
    private let bundledData: @Sendable (RemoteResource) throws -> Data

    /// Creates a fetcher against the published endpoint.
    ///
    /// - Parameters:
    ///   - baseURL: Where the payloads are served, with no trailing slash. Defaults to the one home
    ///     for it, `PublishedContent.baseURL`.
    ///   - transport: How to reach the network.
    ///   - cache: Where an accepted payload is kept.
    public init(
        baseURL: String = PublishedContent.baseURL,
        transport: any ContentTransport,
        cache: ContentCache
    ) {
        self.init(baseURL: baseURL, transport: transport, cache: cache) { try $0.bundledData() }
    }

    /// Creates a fetcher whose bundled leg is supplied rather than read from the app bundle.
    ///
    /// Internal, and it exists for one reason: a broken app bundle is a real resolution path — it is
    /// what makes ``resolve(_:)`` optional — and there is no other way to produce one from inside a
    /// test.
    init(
        baseURL: String,
        transport: any ContentTransport,
        cache: ContentCache,
        bundledData: @escaping @Sendable (RemoteResource) throws -> Data
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.cache = cache
        self.bundledData = bundledData
    }

    /// The best bytes available without touching the network, or `nil` when there are none at all.
    ///
    /// Cache and bundle are both validated, and the **higher `revision` wins** rather than the cache
    /// winning on rank: an app update ships a newer bundled catalogue than a cache filled before it,
    /// and a stale cache preferred unconditionally would shadow that for the life of the install. A
    /// tie goes to the bundle, which is two identical editions and the cheaper claim.
    public func resolve(_ resource: RemoteResource) -> ResolvedContent? {
        let cached = usable(cache.data(for: resource), from: .cache, as: resource)
        let bundled = usable(try? bundledData(resource), from: .bundle, as: resource)
        return switch (cached, bundled) {
        case (let cached?, let bundled?): cached.revision > bundled.revision ? cached : bundled
        case (let cached?, nil): cached
        case (nil, let bundled?): bundled
        case (nil, nil): nil
        }
    }

    /// Fetches `resource` and caches it, but only if it is both valid and newer than what
    /// ``resolve(_:)`` already answers with.
    ///
    /// Validation happens before the write, so a malformed or refused body cannot replace a good
    /// cached copy — the fallback is what the caller gets, and it is still there next launch.
    public func refresh(_ resource: RemoteResource) async -> RefreshOutcome {
        guard let url = url(for: resource) else {
            return .failed(.unusableURL(absoluteString(for: resource)))
        }

        let fetched: Data
        do {
            fetched = try await transport.fetch(url)
        } catch {
            return .failed(.transport(String(describing: error)))
        }

        let revision: Int
        switch resource.inspect(fetched) {
        case .usable(let fetchedRevision): revision = fetchedRevision
        case .unusable(let reasons): return .failed(.invalidPayload(reasons))
        }

        if let current = resolve(resource), current.revision >= revision {
            return .alreadyCurrent(revision: current.revision)
        }

        do {
            try cache.write(fetched, for: resource)
        } catch {
            return .failed(.cacheWriteFailed(String(describing: error)))
        }
        return .updated(revision: revision)
    }

    /// Refreshes all three payloads concurrently, one outcome each.
    ///
    /// This is the whole of what a launch schedules, and it is scheduled *beside* the launch rather
    /// than inside it: nothing here is awaited before a screen appears.
    public func refreshAll() async -> [RemoteResource: RefreshOutcome] {
        await withTaskGroup(of: (RemoteResource, RefreshOutcome).self) { group in
            for resource in RemoteResource.allCases {
                group.addTask {
                    let outcome = await refresh(resource)
                    return (resource, outcome)
                }
            }
            var outcomes: [RemoteResource: RefreshOutcome] = [:]
            for await (resource, outcome) in group {
                outcomes[resource] = outcome
            }
            return outcomes
        }
    }

    /// Where `resource` is served, or `nil` when the base URL is not one.
    func url(for resource: RemoteResource) -> URL? {
        URL(string: absoluteString(for: resource))
    }

    /// The address `resource` would be fetched from, URL or not.
    private func absoluteString(for resource: RemoteResource) -> String {
        "\(baseURL)/\(resource.path)"
    }

    /// `data` as a resolution, or `nil` when there is nothing there or what is there is refused.
    private func usable(
        _ data: Data?,
        from origin: ContentOrigin,
        as resource: RemoteResource
    ) -> ResolvedContent? {
        guard let data, case .usable(let revision) = resource.inspect(data) else { return nil }
        return ResolvedContent(data: data, revision: revision, origin: origin)
    }
}
