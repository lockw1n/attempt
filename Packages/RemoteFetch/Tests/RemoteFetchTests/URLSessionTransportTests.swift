import Foundation
import Testing

@testable import RemoteFetch

/// A URL protocol that answers every request the same way, so a test can produce an answer the
/// network would give but a stub transport cannot: one that arrives successfully and is not a
/// payload.
class CannedURLProtocol: URLProtocol {
    /// What to answer with, or `nil` to fail the request.
    class func response(for url: URL) -> URLResponse? {
        nil
    }

    /// The body served alongside that response.
    class func body(for url: URL) -> Data {
        Data("<html>not a payload</html>".utf8)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let response = Self.response(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body(for: url))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The 404 a renamed repository would serve, HTML body and all.
class NotFoundURLProtocol: CannedURLProtocol {
    override class func response(for url: URL) -> URLResponse? {
        HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)
    }
}

/// The answer the endpoint actually gives: 200, with the payload.
class ServedPayloadURLProtocol: CannedURLProtocol {
    /// Bytes distinct enough that handing back *anything* else — including nothing — fails.
    static let payload = Data(#"{"schemaVersion":1,"revision":3}"#.utf8)

    override class func response(for url: URL) -> URLResponse? {
        HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
    }

    override class func body(for url: URL) -> Data {
        payload
    }
}

/// An answer that is not HTTP at all.
class NonHTTPURLProtocol: CannedURLProtocol {
    override class func response(for url: URL) -> URLResponse? {
        URLResponse(url: url, mimeType: "text/html", expectedContentLength: 0, textEncodingName: nil)
    }
}

@Suite("URLSessionTransport")
struct URLSessionTransportTests {
    private func transport(stubbing protocolClass: AnyClass) -> URLSessionTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [protocolClass]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    @Test("A 200 hands back exactly the bytes that were served")
    func servedBytesArriveUnchanged() async throws {
        let url = try #require(URL(string: "https://example.invalid/content/v1/formulas.json"))
        let fetched = try await transport(stubbing: ServedPayloadURLProtocol.self).fetch(url)
        #expect(fetched == ServedPayloadURLProtocol.payload)
    }

    @Test("Requests are given the timeout they were built with, not the system's")
    func timeoutsReachTheSession() {
        // The default matters as much as the custom one: `URLSession`'s own is sixty seconds, which
        // is a minute of a launch-time check hanging on a captive portal (`G-2.3`).
        #expect(URLSessionTransport().configuredTimeouts == (request: 10, resource: 10))
        #expect(URLSessionTransport(timeout: 2.5).configuredTimeouts == (request: 2.5, resource: 2.5))
    }

    @Test("A 404 is a failure rather than a body handed on to the validator")
    func notFoundIsRefused() async throws {
        let url = try #require(URL(string: "https://example.invalid/content/v1/formulas.json"))
        await #expect(throws: URLSessionTransport.UnexpectedResponse(statusCode: 404)) {
            try await transport(stubbing: NotFoundURLProtocol.self).fetch(url)
        }
    }

    @Test("A response that is not HTTP is a failure too")
    func nonHTTPResponseIsRefused() async throws {
        let url = try #require(URL(string: "https://example.invalid/content/v1/formulas.json"))
        await #expect(throws: URLSessionTransport.UnexpectedResponse(statusCode: nil)) {
            try await transport(stubbing: NonHTTPURLProtocol.self).fetch(url)
        }
    }

    @Test("Each failure says which one it was")
    func failuresDescribeThemselves() {
        #expect(URLSessionTransport.UnexpectedResponse(statusCode: 404).description == "the endpoint answered 404")
        #expect(URLSessionTransport.UnexpectedResponse(statusCode: nil).description == "the response was not HTTP")
    }
}
