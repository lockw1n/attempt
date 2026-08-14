import Foundation

/// One reason a `flags.json` payload is not fit to ship.
public enum RemoteFlagsValidationFailure: Equatable, Sendable, CustomStringConvertible {
    /// The bytes are not a payload at all — malformed JSON or a missing key. Carries the decoder's
    /// description.
    case undecodable(String)

    /// A shape this reader cannot read. See ``RemoteFlags/schemaVersion``.
    case unsupportedSchemaVersion(Int)

    /// A ``RemoteFlags/revision`` below one, which no published edition has.
    case nonPositiveRevision(Int)

    /// A ``RemoteFlags/minimumSupportedVersion`` that is empty or only whitespace, which no
    /// version comparison can read.
    case blankMinimumSupportedVersion

    /// A line an author can act on without opening the validator.
    public var description: String {
        switch self {
        case .undecodable(let detail):
            "the payload could not be decoded: \(detail)"
        case .unsupportedSchemaVersion(let found):
            "schemaVersion \(found) is not readable here; this build reads "
                + "\(RemoteFlags.supportedSchemaVersion)"
        case .nonPositiveRevision(let found):
            "revision \(found) is not a published edition; revisions start at 1"
        case .blankMinimumSupportedVersion:
            "minimumSupportedVersion is blank"
        }
    }
}

/// Checks that a `flags.json` payload is fit to ship (`TR-0.5.2`).
public enum RemoteFlagsValidator {
    /// Decodes and validates a payload as it exists on disk or over the wire.
    public static func validate(_ data: Data) -> [RemoteFlagsValidationFailure] {
        do {
            let document = try JSONDecoder().decode(RemoteFlags.self, from: data)
            return validate(document)
        } catch {
            return [.undecodable(String(describing: error))]
        }
    }

    /// Validates an already-decoded payload.
    public static func validate(_ document: RemoteFlags) -> [RemoteFlagsValidationFailure] {
        var failures: [RemoteFlagsValidationFailure] = []
        if document.schemaVersion != RemoteFlags.supportedSchemaVersion {
            failures.append(.unsupportedSchemaVersion(document.schemaVersion))
        }
        if document.revision < 1 {
            failures.append(.nonPositiveRevision(document.revision))
        }
        if document.minimumSupportedVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            failures.append(.blankMinimumSupportedVersion)
        }
        return failures
    }
}
