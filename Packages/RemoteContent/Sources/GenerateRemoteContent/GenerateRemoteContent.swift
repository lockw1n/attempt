// Writes `formulas.json` and `flags.json` fresh into an output directory and validates all three
// published payloads — the generated half of `TR-0.5.2`'s "scripted, reproducible deploy".
//
// What is published, where, and with which encoder are `RemoteContent.PublishedContent`'s and the
// two `published` documents'; this tool encodes, checks and writes, and holds none of those facts
// itself.
//
// `exercises.json` is not written here: its bytes are
// `Packages/SeedContent/Sources/SeedContent/Resources/exercises.json`, unchanged, and
// `scripts/generate-remote-content.sh` copies that file directly rather than asking this tool to
// re-encode a document it did not author. It is still *validated* here, with the same call
// `SeedContent`'s own tests use — this tool is the only step a local run and the deploy workflow
// share, and that workflow does not wait for `ci.yml`, so nothing else stands between a broken
// catalogue on `main` and a published one.
//
// Every payload is validated before the run is allowed to succeed, and a failure exits non-zero:
// `generate-remote-content.sh` fails on this tool's exit code, and the CI workflow uploads only
// what that script produced.

import Foundation
import PowerliftingCore
import RemoteContent
import SeedContent

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
        let encoder = PublishedContent.makeEncoder()

        func write(_ data: Data, to relativePath: String) throws {
            let url = outputRoot.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            print("wrote \(relativePath) (\(data.count) bytes)")
        }

        // Fails the run rather than publishing a payload its own validator would refuse.
        func fail<Failure>(_ relativePath: String, _ failures: [Failure]) -> Never {
            for failure in failures {
                FileHandle.standardError.write(Data("\(relativePath): \(failure)\n".utf8))
            }
            exit(65)
        }

        let formulasFailures = RemoteFormulasValidator.validate(RemoteFormulas.published)
        guard formulasFailures.isEmpty else {
            fail(PublishedContent.formulasPath, formulasFailures)
        }
        try write(try encoder.encode(RemoteFormulas.published), to: PublishedContent.formulasPath)

        let flagsFailures = RemoteFlagsValidator.validate(RemoteFlags.published)
        guard flagsFailures.isEmpty else { fail(PublishedContent.flagsPath, flagsFailures) }
        try write(try encoder.encode(RemoteFlags.published), to: PublishedContent.flagsPath)

        // Validated rather than written — see the header comment for why this tool checks a file
        // it did not produce.
        let exercisesURL = outputRoot.appendingPathComponent(PublishedContent.exercisesPath)
        guard let exercisesData = try? Data(contentsOf: exercisesURL) else {
            FileHandle.standardError.write(
                Data(
                    """
                    \(PublishedContent.exercisesPath): not found under \(arguments[1]). \
                    Run scripts/generate-remote-content.sh, which copies it into place before \
                    this tool runs.

                    """.utf8))
            exit(66)
        }
        let exercisesFailures = SeedCatalogueValidator.validate(exercisesData)
        guard exercisesFailures.isEmpty else {
            fail(PublishedContent.exercisesPath, exercisesFailures)
        }
        print("validated \(PublishedContent.exercisesPath) (\(exercisesData.count) bytes)")
    }
}
