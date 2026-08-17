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
        client?.urlProtocol(self, didLoad: Data("<html>not a payload</html>".utf8))
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
