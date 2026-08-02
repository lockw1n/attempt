//
//  Endpoint.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import Foundation

nonisolated enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A single API operation, described independently of how it is sent.
///
/// Define endpoints as static factory methods in a per-feature extension:
///
/// ```swift
/// extension Endpoint {
///     static func item(id: String) -> Endpoint {
///         Endpoint(path: "/items/\(id)")
///     }
/// }
/// ```
nonisolated struct Endpoint: Sendable {
    var path: String
    var method: HTTPMethod = .get
    var queryItems: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?

    func urlRequest(baseURL: URL) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw AppError.unknown("Could not build a URL for \(path).")
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AppError.unknown("Could not build a URL for \(path).")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}
