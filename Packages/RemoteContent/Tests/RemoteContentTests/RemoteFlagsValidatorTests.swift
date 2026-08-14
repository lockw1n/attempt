import Foundation
import Testing

@testable import RemoteContent

@Suite("RemoteFlagsValidator")
struct RemoteFlagsValidatorTests {
    @Test("A valid payload has no failures")
    func validPayloadPasses() throws {
        #expect(RemoteFlagsValidator.validate(try fixture("flags-valid")).isEmpty)
    }

    @Test("An unsupported schemaVersion is reported")
    func unsupportedSchemaVersionIsReported() throws {
        let failures = RemoteFlagsValidator.validate(try fixture("flags-unsupported-schema-version"))
        #expect(failures == [.unsupportedSchemaVersion(2)])
    }

    @Test("A non-positive revision is reported")
    func nonPositiveRevisionIsReported() throws {
        let failures = RemoteFlagsValidator.validate(try fixture("flags-non-positive-revision"))
        #expect(failures == [.nonPositiveRevision(0)])
    }

    @Test("A blank minimumSupportedVersion is reported")
    func blankMinimumVersionIsReported() throws {
        let failures = RemoteFlagsValidator.validate(try fixture("flags-blank-minimum-version"))
        #expect(failures == [.blankMinimumSupportedVersion])
    }

    @Test("A missing key is undecodable")
    func missingFieldIsUndecodable() throws {
        let failures = RemoteFlagsValidator.validate(try fixture("flags-missing-field"))
        #expect(failures.count == 1)
        guard case .undecodable = failures[0] else {
            Issue.record("expected .undecodable, got \(failures[0])")
            return
        }
    }
}
