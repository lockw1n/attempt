import Foundation
import SeedContent
import Testing

// `FR-1.14.2`'s catalogue half. Built as text rather than as a fixture file because what is on
// trial is the decoder's key list: `SeedExercise` refuses a key it does not declare, so an entry
// carrying this one is either accepted deliberately or rejected as a typo, and nothing in between.

@Suite("A catalogue entry may carry a Ukrainian name (FR-1.14.2)")
struct SeedUkrainianNameTests {
    private func catalogue(entryFields: String) -> Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "revision": 1,
              "exercises": [
                {
                  "id": "0f7b6a5c-1111-4222-8333-444455556666",
                  "name": "Back Squat",
                  \(entryFields)"movement": "squat",
                  "equipment": "barbell",
                  "laterality": "bilateral",
                  "barType": "standard"
                }
              ]
            }
            """.utf8)
    }

    @Test("An entry carrying a Ukrainian name decodes, and is not a typo")
    func aTranslatedEntryDecodes() throws {
        let data = catalogue(entryFields: "\"ukrainianName\": \"Присідання\",\n      ")

        #expect(SeedCatalogueValidator.validate(data).isEmpty)

        let decoded = try JSONDecoder().decode(SeedCatalogue.self, from: data)
        let entry = try #require(decoded.exercises.first)
        #expect(entry.ukrainianName == "Присідання")
        #expect(entry.name == "Back Squat")
    }

    // Absent is a normal state for a payload, not an edge one, and it must not read as a blank
    // translation. The shipped catalogue translates every entry — `BundledCatalogueTests` is what
    // holds it to that — but a fetched one, or a hand-written fixture, need not.
    @Test("An entry without one decodes to no Ukrainian name")
    func anUntranslatedEntryDecodes() throws {
        let data = catalogue(entryFields: "")

        #expect(SeedCatalogueValidator.validate(data).isEmpty)

        let entry = try #require(
            try JSONDecoder().decode(SeedCatalogue.self, from: data).exercises.first)
        #expect(entry.ukrainianName == nil)
        #expect(entry.name == "Back Squat")
    }

    // The key is real, so a near-miss of it is still a typo the author has to be told about — the
    // guard that says this suite's first test proves acceptance rather than a loosened decoder.
    @Test("A misspelling of the new key is still refused")
    func aMisspelledKeyIsRefused() {
        let data = catalogue(entryFields: "\"ukranianName\": \"Присідання\",\n      ")

        #expect(
            SeedCatalogueValidator.validate(data).map(\.kind) == [.unrecognisedField])
    }
}
