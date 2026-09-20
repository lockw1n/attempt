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

    @Test("The shipped catalogue lists one former Ukrainian name, and is still schema 1")
    func theShippedCatalogueListsOne() throws {
        // **The two counts are a tripwire.** `T-18.04` set both to 0 and said the second would go
        // red at `T-18.05`; it did, and `FR-18.2.2` raised it to 1 rather than deleting the line.
        // Whoever corrects the next name moves the number again for the same reason: a count that
        // is allowed to drift is a count that cannot tell a deliberate correction from a former
        // name added by a bad merge.
        //
        // The English count stays 0 — `FR-18.2.3`'s audit was of the Ukrainian column only, and
        // the author declined every candidate but the rear delt (`T-18.05`'s approval gate,
        // 2026-09-20), so revision 4 differs from 3 by one entry and the revision number.
        //
        // The schema expectation is the one that must not move whatever the counts do: an added
        // optional key is not a new schema.
        let catalogue = try JSONDecoder().decode(SeedCatalogue.self, from: BundledCatalogue.data())

        #expect(catalogue.schemaVersion == SeedCatalogue.supportedSchemaVersion)
        #expect(catalogue.exercises.count(where: { !$0.formerNames.isEmpty }) == 0)
        #expect(catalogue.exercises.count(where: { !$0.formerUkrainianNames.isEmpty }) == 1)
    }

    // `FR-18.2.2` is about two particular strings, and until here nothing asserted either of them
    // against the file that ships. The count above passes on a typo — one former Ukrainian name is
    // one former Ukrainian name whatever it spells — and `DOD-18.5`'s revision-3/4 pair in
    // `SeedImportTests` cannot see this file at all, deriving its revision 4 from a frozen fixture
    // by the same substitution a mistyped hand edit would have got wrong. So the corrected entry is
    // pinned by id, like every other permanent fact in `BundledCatalogueTests`.
    @Test("The rear delt fly ships under its corrected name, listing the retired one (FR-18.2.2)")
    func theCorrectedEntryShips() throws {
        let entries = try JSONDecoder()
            .decode(SeedCatalogue.self, from: BundledCatalogue.data()).exercises
        let id = try #require(UUID(uuidString: "48fb24a6-abd3-472d-87ca-d054c1c1f982"))
        let entry = try #require(entries.first { $0.id == id }, "the rear delt fly entry is gone")

        #expect(entry.name == "Machine Rear Delt Fly")
        #expect(entry.ukrainianName == "Розведення рук у тренажері")
        #expect(entry.formerUkrainianNames == ["Махи в тренажері в нахилі"])
        #expect(entry.formerNames.isEmpty)
    }

    // `Exercise.reseeded(from:)` corrects a stored name that still **equals** one of the entry's
    // former names, and `contains` matches on the string alone — never on the id. So a former name
    // that is some *other* row's current name renames the wrong exercise: a lifter who has both
    // would find the one they never touched silently retitled to the other's new name, and there is
    // no way back because the store records nothing about where a name came from.
    //
    // It cannot happen in revision 4, where the one former name is *Махи в тренажері в нахилі* and
    // no entry carries it any more. It becomes possible the first time a name is *moved* between
    // entries rather than corrected in place, which is why this is a test and not a remark.
    @Test("No former name is any entry's current name, in either language")
    func formerNamesAreRetired() throws {
        let entries = try JSONDecoder()
            .decode(SeedCatalogue.self, from: BundledCatalogue.data()).exercises
        func trimmed(_ value: String) -> String {
            value.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Trimmed on both sides because that is what the correction compares — a former name
        // padded with a space would pass an untrimmed check here and still rename the row.
        let currentEnglish = Set(entries.map { trimmed($0.name) })
        let currentUkrainian = Set(entries.compactMap { $0.ukrainianName.map(trimmed) })
        let formerEnglish = entries.flatMap(\.formerNames).map(trimmed)
        let formerUkrainian = entries.flatMap(\.formerUkrainianNames).map(trimmed)

        #expect(formerEnglish.filter(currentEnglish.contains) == [])
        #expect(formerUkrainian.filter(currentUkrainian.contains) == [])
        // Not vacuous: revision 4 lists one former Ukrainian name, and the set it is checked
        // against is the whole catalogue rather than an empty one.
        #expect(formerUkrainian.count == 1)
        #expect(currentUkrainian.count == entries.count)
    }
}
