import Foundation

/// How the fetcher reaches the network, as a single call.
///
/// A protocol because the failure paths are the interesting ones here: offline, timed out and
/// answered-with-rubbish are what `G-2.3` and `NFR-1.7` are about, and none of them is reproducible
/// against a live endpoint.
public protocol ContentTransport: Sendable {
    /// The bytes at `url`.
    ///
    /// Any thrown error is a fetch failure and nothing more — the caller falls back rather than
    /// surfacing it, so the error type is deliberately unconstrained.
    func fetch(_ url: URL) async throws -> Data
}

/// The real transport: one `URLSession` request per payload, with a timeout.
public struct URLSessionTransport: ContentTransport {
    private let session: URLSession

    /// Creates a transport whose requests give up after `timeout` seconds.
    ///
    /// Ephemeral rather than the shared session: ``ContentCache`` is the durable cache and it is
    /// keyed on `revision`, so a second cache on disk with its own expiry policy would answer the
    /// freshness question a different way. The in-memory cache still honours the endpoint's
    /// `Cache-Control` within one launch, which is why a repeated check costs nothing.
    ///
    /// - Parameter timeout: Seconds a request may take before it fails, applied to both the request
    ///   and the resource. Any positive value; the default is ten.
    public init(timeout: TimeInterval = 10) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        session = URLSession(configuration: configuration)
    }

    /// The seconds this transport's session gives a request and a resource, in that order.
    ///
    /// Internal, and it exists because configuring the session is the whole of what
    /// ``init(timeout:)`` does — a timeout that is never applied is indistinguishable from one that
    /// is, until a request hangs in front of a user.
    var configuredTimeouts: (request: TimeInterval, resource: TimeInterval) {
        (
            session.configuration.timeoutIntervalForRequest,
            session.configuration.timeoutIntervalForResource
        )
    }

    /// Creates a transport over a supplied session.
    ///
    /// Internal: an app has no reason to configure the session, and the answers that are not a
    /// payload — a 404, a response that is not HTTP at all — can only be produced by a stubbed URL
    /// protocol.
    init(session: URLSession) {
        self.session = session
    }

    /// Fetches `url`, treating any status outside 2xx as a failure.
    public func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw UnexpectedResponse(statusCode: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UnexpectedResponse(statusCode: http.statusCode)
        }
        return data
    }

    /// Something answered, but not with a payload — a 404 after a repository rename, or a captive
    /// portal's login page, both of which decode as cheerfully as they arrive if nobody looks at the
    /// status.
    public struct UnexpectedResponse: Error, Equatable, CustomStringConvertible {
        /// The HTTP status that came back, or `nil` when the response was not HTTP at all.
        public let statusCode: Int?

        /// Creates the error.
        public init(statusCode: Int?) {
            self.statusCode = statusCode
        }

        /// A line naming what came back instead of a payload.
        public var description: String {
            if let statusCode {
                "the endpoint answered \(statusCode)"
            } else {
                "the response was not HTTP"
            }
        }
    }
}
