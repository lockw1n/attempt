import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.11.3`'s half of the envelope: the three sections a backup adds, the word that says which
/// file this is, and what a reader does with a payload written before either existed.
///
/// A suite of its own rather than more of ``TrainingLogArchiveTests``, which is where the export's
/// half is: the two share one type and ask different questions of it, and one struct holding both
/// is past the body length this repo holds every type to.
@Suite("Backup archive")
struct BackupArchiveTests {
    /// The stamp the export's suite uses, so the two files' bytes are comparable.
    static let stamp = TrainingLogArchiveTests.stamp

    /// The same archive as ``TrainingLogArchiveTests/awkwardArchive()``, plus the three sections only a backup carries.
    ///
    /// - Returns: The backup.
    static func awkwardBackup() -> TrainingLogArchive {
        let log = TrainingLogArchiveTests.awkwardArchive()
        return TrainingLogArchive(
            takenAt: stamp,
            exercises: log.exercises,
            sessions: log.sessions,
            entries: log.entries,
            sets: log.sets,
            bodyweight: log.bodyweight,
            equipment: [awkwardProfile()],
            trainingMaxes: [awkwardTrainingMax(log.exercises[0].id)],
            settings: awkwardSettings())
    }

    /// A gym whose two plate lists disagree in length — a row the projection refuses and the wire
    /// format still has to carry.
    private static func awkwardProfile() -> EquipmentProfile {
        EquipmentProfile(
            id: ExportRecords.id(0x66),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: stamp,
            name: "the meet",
            barWeight: Weight(grams: 20_000),
            collarWeight: Weight(grams: 2_500),
            plates: [Weight(grams: 25_000), Weight(grams: 20_000)],
            platePairCounts: [2],
            isDefault: true)
    }

    /// A training-max entry with every optional filled and a negative progression, which is a
    /// configured deload rather than a mistake.
    private static func awkwardTrainingMax(_ exerciseID: UUID) -> TrainingMaxEntry {
        TrainingMaxEntry(
            id: ExportRecords.id(0x77),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            exerciseID: exerciseID,
            source: .percentOfRepMax,
            sourceRepCount: 3,
            manualWeight: Weight(grams: 150_000),
            percentage: 0.925,
            roundingIncrement: Weight(grams: 1_250),
            roundingStrategy: .nearest,
            progressionIncrement: Weight(grams: -5_000),
            effectiveFrom: stamp)
    }

    /// A preferences row with the two optionals present.
    private static func awkwardSettings() -> UserSettings {
        UserSettings(
            id: ExportRecords.id(0x88),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            userID: ExportRecords.id(0x99),
            displayUnit: .pounds,
            e1RMFormula: .brzycki,
            theme: .dark,
            defaultRoundingIncrement: Weight(grams: 2_500),
            defaultRoundingStrategy: .down,
            displayPrecision: .quarter,
            e1RMLookbackDays: 180,
            keepScreenAwake: false,
            dashboardExerciseIDs: [ExportRecords.id(0x11)])
    }

    @Test("A backup round-trips its three extra sections too")
    func backupRoundTripsLosslessly() throws {
        let backup = Self.awkwardBackup()
        let restored = try TrainingLogArchive.decoded(from: backup.encoded())
        #expect(restored.equipment.first?.deletedAt == Self.stamp)
        #expect(restored.settings?.displayUnit == .pounds)
        #expect(restored.trainingMaxes.first?.progressionIncrement == Weight(grams: -5_000))
        #expect(restored == backup)
    }

    @Test("The file says which of the two it is, and the word survives the round trip")
    func carriesItsContents() throws {
        let backup = try TrainingLogArchive.decoded(from: Self.awkwardBackup().encoded())
        let export = try TrainingLogArchive.decoded(from: TrainingLogArchiveTests.awkwardArchive().encoded())
        #expect(backup.contents == .fullBackup)
        #expect(export.contents == .trainingLog)
        let json = try #require(String(data: Self.awkwardBackup().encoded(), encoding: .utf8))
        #expect(json.contains("\"contents\" : \"fullBackup\""))
    }

    @Test("A backup writes the three extra keys and an export writes none of them")
    func onlyABackupCarriesTheConfiguration() throws {
        let backup = try #require(String(data: Self.awkwardBackup().encoded(), encoding: .utf8))
        #expect(
            TrainingLogArchiveTests.envelopeKeys(of: backup) == [
                "bodyweight", "contents", "entries", "equipment", "exercises", "exportedAt",
                "formatVersion", "sessions", "sets", "settings", "trainingMaxes",
            ])
        let export = try #require(String(data: TrainingLogArchiveTests.awkwardArchive().encoded(), encoding: .utf8))
        // An empty section is omitted rather than written as `[]`, so an export's bytes are what
        // version 1 wrote plus the one key that says what it is.
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("equipment"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("settings"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("trainingMaxes"))
    }

    @Test("A file written before any of this still decodes, as the export it was")
    func readsAVersionOneFile() throws {
        // Hand-written rather than produced by this build, which is the whole point: no encoder
        // here can emit version 1 any more, so the only way to prove the reader still takes one is
        // to hand it the bytes the old one wrote.
        let json = """
            {
              "formatVersion" : 1,
              "exportedAt" : 773452800.1234567,
              "exercises" : [],
              "sessions" : [],
              "entries" : [],
              "sets" : [],
              "bodyweight" : []
            }
            """
        let restored = try TrainingLogArchive.decoded(from: Data(json.utf8))
        #expect(restored.formatVersion == 1)
        #expect(restored.contents == .trainingLog)
        #expect(restored.equipment.isEmpty)
        #expect(restored.trainingMaxes.isEmpty)
        #expect(restored.settings == nil)
    }

    @Test("A file written before a record gained a column still restores its rows")
    func readsEntriesFromBeforeTheCheckOffColumn() throws {
        // The version does not move when a record gains a column, so this file claims a version
        // this build reads and then hands it an entry with eight keys where the decoder now knows
        // nine. Refusing it would report the app's own backup as damaged — rule 7 of
        // `RecordCoding.swift`, tested here because this is the path that made it a rule.
        let json = """
            {
              "formatVersion" : 2,
              "contents" : "trainingLog",
              "exportedAt" : 773452800.1234567,
              "exercises" : [],
              "sessions" : [],
              "entries" : [
                {
                  "id" : "0F5A1E24-9B7D-4C31-8E62-000000000001",
                  "createdAt" : 0,
                  "updatedAt" : 0,
                  "sessionID" : "0F5A1E24-9B7D-4C31-8E62-000000000002",
                  "exerciseID" : "0F5A1E24-9B7D-4C31-8E62-000000000003",
                  "order" : 0,
                  "notes" : "wide stance"
                }
              ],
              "sets" : [],
              "bodyweight" : []
            }
            """
        let restored = try TrainingLogArchive.decoded(from: Data(json.utf8))

        #expect(restored.entries.count == 1)
        #expect(restored.entries.first?.isMarkedDone == false)
        #expect(restored.entries.first?.notes == "wide stance")
    }

    @Test("A contents word this build does not know is refused rather than guessed at")
    func refusesAnUnknownContents() throws {
        // The one vocabulary in this module that throws. Resolving it to either known value would
        // be a claim about rows the file does not contain — see `TrainingLogArchive.Contents`.
        let json = """
            {
              "formatVersion" : 2,
              "contents" : "encryptedBackup",
              "exportedAt" : 773452800.1234567,
              "exercises" : [],
              "sessions" : [],
              "entries" : [],
              "sets" : [],
              "bodyweight" : []
            }
            """
        #expect(throws: DecodingError.self) {
            try TrainingLogArchive.decoded(from: Data(json.utf8))
        }
    }

    @Test("A missing required section is still corruption rather than an omitted one")
    func refusesAMissingLogSection() throws {
        // The other half of the rule above: the five log sections are what every archive is, so
        // their absence is a file this version cannot have produced. Only the sections added after
        // version 1 default.
        let json = """
            {
              "formatVersion" : 2,
              "contents" : "trainingLog",
              "exportedAt" : 773452800.1234567,
              "exercises" : [],
              "sessions" : [],
              "entries" : [],
              "bodyweight" : []
            }
            """
        #expect(throws: DecodingError.self) {
            try TrainingLogArchive.decoded(from: Data(json.utf8))
        }
    }
}
