import Foundation
import PowerliftingCore
import Testing

@testable import RemoteContent

@Suite("RemoteFormulas — decoding")
struct RemoteFormulasDecodingTests {
    @Test("Decodes the published shape")
    func decodesThePublishedShape() throws {
        let document = try JSONDecoder().decode(RemoteFormulas.self, from: try fixture("formulas-valid"))
        #expect(document.schemaVersion == 1)
        #expect(document.revision == 1)
        #expect(document.verified == false)
        #expect(document.rpeTable.repRange == 1...10)
        #expect(document.rpeTable.entries.count == 2)
    }

    @Test("Round-trips RPETable.standard through JSONEncoder/JSONDecoder")
    func roundTripsTheShippedChart() throws {
        let original = RemoteFormulas(
            schemaVersion: RemoteFormulas.supportedSchemaVersion,
            revision: 1,
            verified: false,
            rpeTable: .standard
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteFormulas.self, from: data)
        #expect(decoded == original)
    }

    @Test("An RPETable that fails its own initialiser's guards fails to decode")
    func invalidRPETableFailsToDecode() throws {
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(RemoteFormulas.self, from: try fixture("formulas-invalid-rpe-table"))
        }
    }
}
