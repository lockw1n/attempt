import Foundation
import PowerliftingCore
import Testing

@testable import RemoteContent

/// The keys at the top level of a pretty-printed document, in the order they appear.
///
/// `.prettyPrinted` indents by two spaces per level, so a top-level key is the only thing that can
/// start a line with exactly two spaces and a quote.
private func topLevelKeys(_ data: Data) throws -> [String] {
    let text = try #require(String(data: data, encoding: .utf8))
    return text.split(separator: "\n").compactMap { line -> String? in
        guard line.hasPrefix("  \""), !line.hasPrefix("   ") else { return nil }
        let afterQuote = line.dropFirst(3)
        guard let end = afterQuote.firstIndex(of: "\"") else { return nil }
        return String(afterQuote[..<end])
    }
}

/// FNV-1a over the bytes — a fingerprint, not a checksum, and only ever compared to itself.
private func fingerprint(_ data: Data) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in data {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

@Suite("The documents that are published")
struct PublishedContentTests {
    // `GenerateRemoteContent` holds no facts of its own — it encodes these documents with this
    // encoder and writes them at these paths — so testing them here tests what is published.

    @Test("Every published payload passes its own validator")
    func publishedDocumentsValidate() {
        #expect(RemoteFormulasValidator.validate(RemoteFormulas.published).isEmpty)
        #expect(RemoteFlagsValidator.validate(RemoteFlags.published).isEmpty)
    }

    @Test("The published bytes are readable by the validator that will read them over the wire")
    func publishedBytesRoundTripThroughTheDataValidator() throws {
        let encoder = PublishedContent.makeEncoder()
        #expect(
            RemoteFormulasValidator.validate(try encoder.encode(RemoteFormulas.published)).isEmpty)
        #expect(RemoteFlagsValidator.validate(try encoder.encode(RemoteFlags.published)).isEmpty)
    }

    @Test("Two runs of the encoder agree byte for byte")
    func encodingIsReproducible() throws {
        // What `.sortedKeys` buys, asserted rather than assumed: a republish that changed nothing
        // must not produce different bytes.
        let first = try PublishedContent.makeEncoder().encode(RemoteFormulas.published)
        let second = try PublishedContent.makeEncoder().encode(RemoteFormulas.published)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test("The published key order is the encoder's, not the encode(to:) methods'")
    func publishedKeyOrderIsSorted() throws {
        let encoder = PublishedContent.makeEncoder()
        // Both types write `schemaVersion` first; neither published document starts with it.
        #expect(
            try topLevelKeys(try encoder.encode(RemoteFlags.published))
                == ["minimumSupportedVersion", "revision", "schemaVersion"])
        #expect(
            try topLevelKeys(try encoder.encode(RemoteFormulas.published))
                == ["revision", "rpeTable", "schemaVersion", "verified"])
    }

    @Test("The paths are the ones TR-0.5.2 names, relative to a base with no trailing slash")
    func pathsAreTheRequirementsOwn() {
        #expect(PublishedContent.exercisesPath == "content/v1/exercises.json")
        #expect(PublishedContent.formulasPath == "content/v1/formulas.json")
        #expect(PublishedContent.flagsPath == "config/v1/flags.json")
        #expect(!PublishedContent.baseURL.hasSuffix("/"))
        #expect(
            PublishedContent.baseURL + "/" + PublishedContent.formulasPath
                == "https://lockw1n.github.io/attempt/content/v1/formulas.json")
    }

    @Test("A changed chart cannot be published under an unchanged revision")
    func chartIsTheOneRevisionWasSetFor() throws {
        // `deploy-content.yml` republishes whenever `RPETable*.swift` changes, and `revision` is a
        // literal — so correcting the chart with no other edit would serve new content under the
        // old edition number, which is invisible to `TR-0.5.3`'s launch check. This test is what
        // makes that impossible to do by accident.
        //
        // **If this fails because you changed `RPETable.standard`:** bump
        // `RemoteFormulas.published.revision`, decide whether `verified` is now `true`, then paste
        // the reported fingerprint here.
        let chart = try PublishedContent.makeEncoder().encode(RemoteFormulas.published.rpeTable)
        #expect(fingerprint(chart) == 0x4eea_ce64_44c3_e295)
        #expect(RemoteFormulas.published.revision == 1)
        #expect(RemoteFormulas.published.verified == false)
    }
}
