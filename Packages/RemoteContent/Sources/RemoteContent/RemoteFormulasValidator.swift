import Foundation

/// One reason a `formulas.json` payload is not fit to ship.
public enum RemoteFormulasValidationFailure: Equatable, Sendable, CustomStringConvertible {
    /// The bytes are not a payload at all — malformed JSON, a missing key, or an ``PowerliftingCore/RPETable`` whose
    /// entries or rep range fail its own initialiser's guards. Carries the decoder's description.
    case undecodable(String)

    /// A shape this reader cannot read. See ``RemoteFormulas/schemaVersion``.
    case unsupportedSchemaVersion(Int)

    /// A ``RemoteFormulas/revision`` below one, which no published edition has.
    case nonPositiveRevision(Int)

    /// A line an author can act on without opening the validator.
    public var description: String {
        switch self {
        case .undecodable(let detail):
            "the payload could not be decoded: \(detail)"
        case .unsupportedSchemaVersion(let found):
            "schemaVersion \(found) is not readable here; this build reads "
                + "\(RemoteFormulas.supportedSchemaVersion)"
        case .nonPositiveRevision(let found):
            "revision \(found) is not a published edition; revisions start at 1"
        }
    }
}

/// Checks that a `formulas.json` payload is fit to ship (`TR-0.5.2`).
///
/// Lighter than `SeedCatalogueValidator` because there is less to check: an ``PowerliftingCore/RPETable``
/// validates its own entries and rep range on decode, so a malformed chart is already a decode
/// failure by the time this runs, the same way a malformed UUID is for `exercises.json`.
public enum RemoteFormulasValidator {
    /// Decodes and validates a payload as it exists on disk or over the wire.
    public static func validate(_ data: Data) -> [RemoteFormulasValidationFailure] {
        do {
            let document = try JSONDecoder().decode(RemoteFormulas.self, from: data)
            return validate(document)
        } catch {
            return [.undecodable(String(describing: error))]
        }
    }

    /// Validates an already-decoded payload.
    public static func validate(_ document: RemoteFormulas) -> [RemoteFormulasValidationFailure] {
        var failures: [RemoteFormulasValidationFailure] = []
        if document.schemaVersion != RemoteFormulas.supportedSchemaVersion {
            failures.append(.unsupportedSchemaVersion(document.schemaVersion))
        }
        if document.revision < 1 {
            failures.append(.nonPositiveRevision(document.revision))
        }
        return failures
    }
}
