import Foundation
import RemoteContent
import Testing

@testable import RemoteFetch

@Suite("RemoteResource")
struct RemoteResourceTests {
    @Test("Every path comes from PublishedContent")
    func pathsComeFromPublishedContent() {
        #expect(RemoteResource.exercises.path == PublishedContent.exercisesPath)
        #expect(RemoteResource.formulas.path == PublishedContent.formulasPath)
        #expect(RemoteResource.flags.path == PublishedContent.flagsPath)
    }

    @Test("The three paths are the ones the endpoint actually serves")
    func pathsAreTheServedOnes() {
        #expect(RemoteResource.exercises.path == "content/v1/exercises.json")
        #expect(RemoteResource.formulas.path == "content/v1/formulas.json")
        #expect(RemoteResource.flags.path == "config/v1/flags.json")
    }

    @Test("No two resources cache to the same file")
    func cacheFileNamesAreDistinct() {
        let names = Set(RemoteResource.allCases.map(\.cacheFileName))
        #expect(names.count == RemoteResource.allCases.count)
        #expect(RemoteResource.formulas.cacheFileName == "formulas.json")
    }

    @Test("Every bundled copy is one this build would accept", arguments: RemoteResource.allCases)
    func bundledCopiesAreUsable(resource: RemoteResource) throws {
        let inspection = resource.inspect(try resource.bundledData())
        guard case .usable(let revision) = inspection else {
            Issue.record("the bundled \(resource) is not usable: \(inspection)")
            return
        }
        #expect(revision >= 1)
    }

    @Test("Bytes that are not JSON are refused for declaring no revision")
    func malformedBytesAreRefused() {
        #expect(
            RemoteResource.formulas.inspect(malformedPayload)
                == .unusable(reasons: ["the payload declares no readable revision"]))
    }

    @Test("A readable revision on an otherwise unreadable document is still refused")
    func revisionAloneIsNotAPayload() {
        let inspection = RemoteResource.formulas.inspect(Data(#"{"revision": 3}"#.utf8))
        guard case .unusable(let reasons) = inspection else {
            Issue.record("expected a refusal, got \(inspection)")
            return
        }
        // The envelope read the revision, so the refusal has to come from the payload's own
        // validator — a different code path from the one malformed bytes take.
        #expect(reasons != ["the payload declares no readable revision"])
        #expect(reasons.count == 1)
    }

    @Test("An unrecognised schemaVersion is refused in the validator's own words")
    func unsupportedSchemaVersionIsRefused() throws {
        let payload = try formulasPayload(revision: 9, schemaVersion: 99)
        let inspection = RemoteResource.formulas.inspect(payload)
        guard case .unusable(let reasons) = inspection else {
            Issue.record("expected a refusal, got \(inspection)")
            return
        }
        #expect(reasons.count == 1)
        #expect(reasons[0].contains("99"))
    }

    @Test("A payload this build reads is usable at the revision it declares")
    func validPayloadIsUsable() throws {
        #expect(RemoteResource.formulas.inspect(try formulasPayload(revision: 7)) == .usable(revision: 7))
    }
}
