// Writes `formulas.json` and `flags.json` fresh into an output directory — the generated half of
// `TR-0.5.2`'s "scripted, reproducible deploy". `exercises.json` is not written here: its bytes
// are `Packages/SeedContent/Sources/SeedContent/Resources/exercises.json`, unchanged, and
// `scripts/generate-remote-content.sh` copies that file directly rather than asking this tool to
// re-encode a document it did not author.
//
// `revision` is a literal a human bumps in this file when publishing a content edit — the same
// convention `exercises.json`'s hand-authored `revision: 1` uses, not a counter this tool tracks.
//
// `.sortedKeys` on the encoder is deliberate and not cosmetic: `JSONEncoder` on Apple platforms
// backs a keyed container with an unordered collection, so two runs of this tool in different
// processes can emit the same object in a different byte order even though `RemoteFormulas` and
// `RemoteFlags` both hand-write `encode(to:)` in a pinned key order. `CLAUDE.md`'s "still owed"
// table names the general form of this trap (gap §22, Phase 2's golden file); `.sortedKeys` is
// the fix that note already gives, applied here so two runs of this generator produce identical
// bytes rather than merely identical values.

import Foundation
import PowerliftingCore
import RemoteContent

// `@main` rather than top-level statements: a `main.swift`'s top-level scope is implicitly
// `@MainActor`-isolated regardless of the package's `.defaultIsolation(nil)`, which nothing here
// needs and which only complicates a plain synchronous tool. `static func main()` is ordinary
// nonisolated code.
@main
enum GenerateRemoteContent {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: GenerateRemoteContent <output-directory>\n".utf8))
            exit(64)
        }

        let outputRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let fileManager = FileManager.default

        let encoder = JSONEncoder()
        // `.sortedKeys` is deliberate and not cosmetic — see the header comment.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        func write(_ data: Data, to relativePath: String) throws {
            let url = outputRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            print("wrote \(relativePath) (\(data.count) bytes)")
        }

        let formulas = RemoteFormulas(
            schemaVersion: RemoteFormulas.supportedSchemaVersion,
            revision: 1,
            verified: false,
            rpeTable: .standard
        )
        try write(try encoder.encode(formulas), to: "content/v1/formulas.json")

        let flags = RemoteFlags(
            schemaVersion: RemoteFlags.supportedSchemaVersion,
            revision: 1,
            minimumSupportedVersion: "1.0.0"
        )
        try write(try encoder.encode(flags), to: "config/v1/flags.json")
    }
}
