import Foundation
import Testing

@testable import RemoteContent

@Suite("RemoteFormulasValidator")
struct RemoteFormulasValidatorTests {
    @Test("A valid payload has no failures")
    func validPayloadPasses() throws {
        #expect(RemoteFormulasValidator.validate(try fixture("formulas-valid")).isEmpty)
    }

    @Test("An unsupported schemaVersion is reported")
    func unsupportedSchemaVersionIsReported() throws {
        let failures = RemoteFormulasValidator.validate(try fixture("formulas-unsupported-schema-version"))
        #expect(failures == [.unsupportedSchemaVersion(2)])
    }

    @Test("A non-positive revision is reported")
    func nonPositiveRevisionIsReported() throws {
        let failures = RemoteFormulasValidator.validate(try fixture("formulas-non-positive-revision"))
        #expect(failures == [.nonPositiveRevision(0)])
    }

    @Test("An RPETable failing its own guards is undecodable")
    func invalidRPETableIsUndecodable() throws {
        let failures = RemoteFormulasValidator.validate(try fixture("formulas-invalid-rpe-table"))
        #expect(failures.count == 1)
        guard case .undecodable = failures[0] else {
            Issue.record("expected .undecodable, got \(failures[0])")
            return
        }
    }

    @Test("A missing key is undecodable")
    func missingFieldIsUndecodable() throws {
        let failures = RemoteFormulasValidator.validate(try fixture("formulas-missing-field"))
        #expect(failures.count == 1)
        guard case .undecodable = failures[0] else {
            Issue.record("expected .undecodable, got \(failures[0])")
            return
        }
    }
}
