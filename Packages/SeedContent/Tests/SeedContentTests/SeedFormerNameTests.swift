import Foundation
import SeedContent
import Testing

// FR-18.2.1, TR-18.1. Two optional keys per entry, and the one thing that has to stay true of them:
// a file that lists neither decodes exactly as it did before they existed. That is what lets
// `schemaVersion` stay at 1 — an added optional key is one an older reader ignores rather than
// chokes on, and the payload is bundled with its reader anyway, so no old reader ever meets a new
// file.
//
// Former names live here and nowhere else (`TR-18.1`): no `@Model` property, no CloudKit field,
// nothing in the backup.

@Suite("Former names in the payload")
struct SeedFormerNameTests {

    @Test("An entry listing neither decodes as empty")
    func absentDecodesAsEmpty() throws {
        let catalogue = try JSONDecoder().decode(SeedCatalogue.self, from: try fixture("valid"))

        #expect(catalogue.exercises.allSatisfy { $0.formerNames.isEmpty })
        #expect(catalogue.exercises.allSatisfy { $0.formerUkrainianNames.isEmpty })
        #expect(catalogue.exercises.isEmpty == false)
    }

    @Test("An entry's listed former names decode, per language and in order")
    func formerNamesDecode() throws {
        let entries = try JSONDecoder()
            .decode(SeedCatalogue.self, from: try fixture("former-names")).exercises

        let renamed = try #require(entries.first { $0.name == "Back Squat" })
        let retranslated = try #require(entries.first { $0.name == "Machine Rear Delt Fly" })
        let untouched = try #require(entries.first { $0.name == "Sled Push" })
        #expect(renamed.formerNames == ["Squat", "Barbell Squat"])
        #expect(renamed.formerUkrainianNames.isEmpty)
        #expect(retranslated.formerUkrainianNames == ["Махи в тренажері в нахилі"])
        #expect(retranslated.formerNames.isEmpty)
        // An empty list written out and an absent key are the same value, which is what lets the
        // catalogue stop writing a key once an entry's history is no longer worth carrying.
        #expect(untouched.formerNames.isEmpty)
        #expect(untouched.formerUkrainianNames.isEmpty)
    }

    @Test("A payload listing former names still validates")
    func formerNamesValidate() throws {
        #expect(SeedCatalogueValidator.validate(try fixture("former-names")).isEmpty)
    }

    @Test("The shipped catalogue lists no former name, and is still schema 1")
    func theShippedCatalogueListsNone() throws {
        // The claim the two keys are added on: today's entries carry neither, so the file has to
        // decode unchanged.
        //
        // **The two counts are a tripwire, and `T-18.05` is expected to trip the second one.** It
        // lands `FR-18.2.2` — one former Ukrainian name in the shipped file — which turns the last
        // expectation red on purpose; that task raises the number to 1 rather than deleting the
        // line. The schema expectation is the one that must not move whatever the counts do: an
        // added optional key is not a new schema.
        let catalogue = try JSONDecoder().decode(SeedCatalogue.self, from: BundledCatalogue.data())

        #expect(catalogue.schemaVersion == SeedCatalogue.supportedSchemaVersion)
        #expect(catalogue.exercises.count(where: { !$0.formerNames.isEmpty }) == 0)
        #expect(catalogue.exercises.count(where: { !$0.formerUkrainianNames.isEmpty }) == 0)
    }
}
