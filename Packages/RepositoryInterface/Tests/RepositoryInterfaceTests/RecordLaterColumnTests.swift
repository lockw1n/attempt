import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

// Split out of `RecordCodingTests.swift` for size — that file had reached the 500-line ceiling once
// `FR-16.3` gave the settings row five more keys. The line is the one the suites were already drawn
// along: rule 5's tolerance for a key a file predates, and nothing else.

@Suite("A column added later reads from a file that predates it")
struct RecordLaterColumnTests {
    // Rule 7, and the reason it is a rule rather than a convenience: `FR-1.11.3`'s restore reads
    // records straight out of an archive whose `formatVersion` does not move when one of them gains
    // a column, so a decoder that insisted on the new key would refuse the app's own backups and
    // report them as damaged. Hand-written rather than produced by this build, for
    // `readsAVersionOneFile`'s reason: no encoder here can leave the key out any more.
    @Test("An entry written before the check-off column decodes as not checked off")
    func entryWithoutTheCheckOffColumn() throws {
        let json = """
            {"id":"0F5A1E24-9B7D-4C31-8E62-000000000001",
             "createdAt":0,"updatedAt":0,
             "sessionID":"0F5A1E24-9B7D-4C31-8E62-000000000002",
             "exerciseID":"0F5A1E24-9B7D-4C31-8E62-000000000003",
             "order":3,"notes":"wide stance"}
            """
        let entry = try JSONDecoder().decode(ExerciseEntry.self, from: Data(json.utf8))

        #expect(entry.isMarkedDone == false)
        // The neighbouring fields too: a decoder that threw the record away and rebuilt an empty
        // one would satisfy the assertion above on its own.
        #expect(entry.notes == "wide stance")
        #expect(entry.order == 3)
    }

    /// Rule 5: a backup taken before these five keys existed restores every preference it does
    /// carry, and the absent ones arrive at exactly the values a fresh install has.
    @Test("A backup written before FR-16.3 restores at the shipped defaults")
    func settingsPredatingTheFeedConfiguration() throws {
        let encoded = try JSONEncoder().encode(codingUserSettings())
        var object = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in [
            "recentRecordsScope", "recentRecordsShowsBaselines", "recentRecordsExerciseIDs",
            "recentRecordsSchemeReps", "recentRecordsSchemeSets",
        ] {
            object.removeValue(forKey: key)
        }
        let older = try JSONSerialization.data(withJSONObject: object)

        let record = try JSONDecoder().decode(UserSettings.self, from: older)

        #expect(record.recentRecordsScope == .dashboardLifts)
        #expect(record.recentRecordsShowsBaselines == false)
        #expect(record.recentRecordsExerciseIDs == nil)
        #expect(record.recentRecordsSchemes == .derived)
        // The neighbours a decoder that threw over an absent preference could not have kept.
        #expect(record.theme == .dark)
        #expect(record.displayUnit == .pounds)
    }

    // The other half — the key is still required of *this* build's own output, so dropping it from
    // the encoder is a change this suite notices rather than one the tolerance above absorbs.
    @Test("This build still writes the column, whatever it holds")
    func theColumnIsStillWritten() throws {
        #expect(try encodedKeys(of: codingExerciseEntry()).contains("isMarkedDone"))
        let json = try jsonText(of: codingExerciseEntry())
        #expect(json.contains("\"isMarkedDone\":true"))
    }
}
