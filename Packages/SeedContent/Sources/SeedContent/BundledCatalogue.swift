import Foundation

/// The `exercises.json` this package ships (`TR-0.5.1`).
///
/// **Every `id` in that file is permanent.** They land in users' logged history, so an id is never
/// regenerated, never derived from a name (`FR-1.1.4` allows renaming a built-in), and never
/// re-minted in bulk — there is deliberately no generator in the repository, because a generator is
/// a machine for doing the one irreversible thing. A new exercise gets a fresh id appended; an
/// existing one keeps the id it was published with.
///
/// The bytes are shipped as authored. `TR-0.5.2` serves the same document from a CDN, and
/// `TR-0.5.3` falls back to this copy, so the two have to be the same file rather than the same
/// content.
public enum BundledCatalogue {
    /// How many entries the shipped catalogue has to carry (`TR-0.5.1`), for a caller validating it.
    public static let minimumExercises = 80

    /// The shipped payload's bytes, ready for ``SeedCatalogueValidator``.
    ///
    /// Validate before importing: a malformed bundled file is a first-launch failure, and `NFR-1.7`
    /// puts first launch in airplane mode with nothing to fall back to.
    public static func data() throws -> Data {
        // At the bundle's root, not under `Resources/`: the manifest processes the directory rather
        // than copying it, because a copied one is a bundle codesign refuses. See Package.swift.
        guard let url = Bundle.module.url(forResource: "exercises", withExtension: "json") else {
            throw PayloadMissing()
        }
        return try Data(contentsOf: url)
    }

    /// The payload is not in the resource bundle — a packaging fault rather than a runtime
    /// condition, since the file ships inside the app.
    public struct PayloadMissing: Error {
        /// Creates the error.
        public init() {}
    }
}
