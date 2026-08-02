//
//  AppError.swift
//  Attempt
//
//  Created by lockw1n on 01.08.2026.
//

import Foundation

/// The single error type surfaced to the UI layer.
///
/// Lower layers (networking, persistence) map their own failures into this so
/// views never have to reason about `URLError`, `DecodingError`, and friends.
nonisolated enum AppError: LocalizedError, Equatable, Sendable {
    /// The request never reached the server, or the connection dropped.
    case offline
    /// The server answered with a non-2xx status.
    case server(statusCode: Int)
    /// The response arrived but did not match the expected shape.
    case decoding(String)
    /// Anything that does not fit the cases above.
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .offline:
            return String(localized: "You appear to be offline.")
        case .server(let statusCode):
            return String(localized: "The server returned an error (\(statusCode)).")
        case .decoding:
            return String(localized: "We couldn't read the server's response.")
        case .unknown(let message):
            return message
        }
    }

    /// Whether retrying the same operation could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .offline:
            return true
        case .server(let statusCode):
            return statusCode >= 500 || statusCode == 429
        case .decoding, .unknown:
            return false
        }
    }
}
