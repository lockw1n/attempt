//
//  APIClient.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import Foundation

/// Anything that can turn an `Endpoint` into a decoded value.
///
/// Depend on this protocol rather than `APIClient` so tests can substitute a
/// stub without touching the network.
protocol APIClientProtocol: Sendable {
    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response
}

/// A thin `URLSession` wrapper: build request, check status, decode, map errors.
///
/// `nonisolated` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor` — without it this type would be pinned to the main actor and
/// every request would hop back there to decode.
nonisolated struct APIClient: APIClientProtocol {
    let baseURL: URL
    let session: URLSession
    let decoder: JSONDecoder

    init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = .apiDefault
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
    }

    func send<Response: Decodable & Sendable>(_ endpoint: Endpoint, as type: Response.Type) async throws -> Response {
        let request = try endpoint.urlRequest(baseURL: baseURL)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet ? AppError.offline : AppError.unknown(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.unknown("The response was not an HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.server(statusCode: http.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw AppError.decoding(String(describing: error))
        }
    }
}

nonisolated extension JSONDecoder {
    /// Matches the conventions most JSON APIs use: snake_case keys, ISO-8601 dates.
    /// Adjust once the real backend is known.
    static var apiDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
