import Foundation
import Testing

@testable import RemoteContent

@Suite("RemoteFlags — decoding")
struct RemoteFlagsDecodingTests {
    @Test("Decodes the published shape")
    func decodesThePublishedShape() throws {
        let document = try JSONDecoder().decode(RemoteFlags.self, from: try fixture("flags-valid"))
        #expect(document.schemaVersion == 1)
        #expect(document.revision == 1)
        #expect(document.minimumSupportedVersion == "1.0.0")
    }

    @Test("Round-trips through JSONEncoder/JSONDecoder")
    func roundTrips() throws {
        let original = RemoteFlags(
            schemaVersion: RemoteFlags.supportedSchemaVersion,
            revision: 3,
            minimumSupportedVersion: "1.2.0"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteFlags.self, from: data)
        #expect(decoded == original)
    }
}
