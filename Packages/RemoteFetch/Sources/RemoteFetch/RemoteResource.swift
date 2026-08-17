import Foundation
import RemoteContent
import SeedContent

/// One of the three documents `TR-0.5.2` publishes, named by what it holds rather than where it is.
///
/// Every case answers the same three questions — where it is served, what makes a copy of it fit to
/// use, and what this build falls back to when no fetched copy is — which is what lets `TR-0.5.3`'s
/// chain be one piece of code over three payloads rather than three pipelines.
public enum RemoteResource: String, CaseIterable, Sendable {
    /// The seed catalogue. The only one of the three with a *file* in the app bundle, and the
    /// bundled and served copies are the same bytes rather than the same content.
    case exercises

    /// The RPE/RIR chart wrapper.
    case formulas

    /// The remote configuration `TR-0.5.4`'s kill switch reads.
    case flags

    /// This resource's path under `PublishedContent/baseURL`.
    public var path: String {
        switch self {
        case .exercises: PublishedContent.exercisesPath
        case .formulas: PublishedContent.formulasPath
        case .flags: PublishedContent.flagsPath
        }
    }

    /// The file a fetched copy is cached under, inside ``ContentCache``'s directory.
    ///
    /// Derived from the case name and not from ``path``, so moving a payload on the server
    /// invalidates nothing that is already cached.
    public var cacheFileName: String { "\(rawValue).json" }
}

// MARK: - What makes a copy usable

/// What inspecting a payload's bytes found.
enum ContentInspection: Equatable {
    /// Fit to use, declaring this edition.
    case usable(revision: Int)

    /// Not fit to use, for these reasons — the validator's own wording.
    case unusable(reasons: [String])
}

extension RemoteResource {
    /// The edition these bytes declare, or every reason they are not fit to use.
    ///
    /// The revision is read first and on its own: bytes that are not a JSON document at all fail
    /// here rather than inside a validator, which keeps "unreadable" and "readable but refused"
    /// distinguishable. Refusal is the `G-2.3` trigger — an unrecognised `schemaVersion` lands in
    /// ``ContentInspection/unusable(reasons:)`` and the caller falls back.
    func inspect(_ data: Data) -> ContentInspection {
        guard let envelope = try? JSONDecoder().decode(ContentEnvelope.self, from: data) else {
            return .unusable(reasons: ["the payload declares no readable revision"])
        }
        let failures = validationFailures(in: data)
        return failures.isEmpty ? .usable(revision: envelope.revision) : .unusable(reasons: failures)
    }

    /// What the payload's own validator says — the same call the deploy tooling makes before
    /// publishing these bytes, so a body this build refuses is a body that should never have been
    /// served.
    private func validationFailures(in data: Data) -> [String] {
        switch self {
        case .exercises:
            SeedCatalogueValidator
                .validate(data, minimumExercises: BundledCatalogue.minimumExercises)
                .map(\.description)
        case .formulas:
            RemoteFormulasValidator.validate(data).map(\.description)
        case .flags:
            RemoteFlagsValidator.validate(data).map(\.description)
        }
    }

    /// The copy this build ships, as bytes.
    ///
    /// `exercises.json` is a file in the resource bundle; the other two are Swift literals, encoded
    /// here with the encoder that produced the published bytes, so all three legs of the fallback
    /// chain have the same shape and pass through the same validator.
    func bundledData() throws -> Data {
        switch self {
        case .exercises: try BundledCatalogue.data()
        case .formulas: try PublishedContent.makeEncoder().encode(RemoteFormulas.published)
        case .flags: try PublishedContent.makeEncoder().encode(RemoteFlags.published)
        }
    }
}

/// The one field every published payload carries that this layer compares on, read without
/// decoding the rest of the document.
struct ContentEnvelope: Decodable {
    /// Which edition of the content it is.
    let revision: Int
}
