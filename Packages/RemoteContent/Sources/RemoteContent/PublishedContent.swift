import Foundation
import PowerliftingCore

/// Where the three `TR-0.5.2` payloads are served, and the encoder that produces their bytes.
///
/// One home for facts that otherwise drift between the generator, the deploy script and
/// `TR-0.5.3`'s fetcher: the base URL, the three paths under it, and the encoder configuration.
public enum PublishedContent {
    /// The site the three payloads are served from, with no trailing slash.
    ///
    /// A GitHub Pages **project** site, so the repository name is part of every URL and the paths
    /// below are relative to this base rather than to the host. Renaming the repository moves all
    /// three URLs; a committed `CNAME` pointing a domain here is the escape hatch when the project
    /// has one, and until then the repository name is load-bearing.
    public static let baseURL = "https://lockw1n.github.io/attempt"

    /// The seed catalogue's path under ``baseURL``.
    ///
    /// Not written by this package: `SeedContent/SCHEMA.md` requires the served copy to be the
    /// bundled bytes, so the deploy script copies that file and `GenerateRemoteContent` validates
    /// what it finds here.
    public static let exercisesPath = "content/v1/exercises.json"

    /// ``RemoteFormulas``' path under ``baseURL``.
    public static let formulasPath = "content/v1/formulas.json"

    /// ``RemoteFlags``' path under ``baseURL``.
    public static let flagsPath = "config/v1/flags.json"

    /// The encoder the published bytes are produced with.
    ///
    /// `.sortedKeys` is load-bearing rather than cosmetic. `JSONEncoder` does not promise that two
    /// processes serialise the same keyed container in the same order, so without it a republish
    /// that changed nothing can still emit different bytes. It also means the published key order
    /// is alphabetical and **not** the order the payload types' `encode(to:)` methods write in —
    /// those pin key *spelling*, not position.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
}

// MARK: - The documents that are published

extension RemoteFormulas {
    /// The document served at ``PublishedContent/formulasPath``.
    ///
    /// ``revision`` is a literal a human bumps when publishing a content edit — the same
    /// convention `exercises.json`'s hand-authored `revision` uses, not a counter anything tracks.
    /// Because the deploy republishes whenever ``RPETable/standard`` changes, a test pins that
    /// chart against this literal and fails when the chart moves without it, which is also where
    /// ``verified`` gets reconsidered.
    public static let published = RemoteFormulas(
        schemaVersion: RemoteFormulas.supportedSchemaVersion,
        revision: 1,
        verified: false,
        rpeTable: .standard
    )
}

extension RemoteFlags {
    /// The document served at ``PublishedContent/flagsPath``.
    ///
    /// ``minimumSupportedVersion`` is `1.0.0` because nothing has shipped yet, so no build can be
    /// locked out. Raising it is `TR-0.5.4`'s kill switch being used, and takes a ``revision`` bump
    /// with it.
    public static let published = RemoteFlags(
        schemaVersion: RemoteFlags.supportedSchemaVersion,
        revision: 1,
        minimumSupportedVersion: "1.0.0"
    )
}
