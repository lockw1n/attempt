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

    /// The same archive as ``TrainingLogArchiveTests/awkwardArchive()``, plus the seven sections only a backup carries.
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
            trainingMaxHistory: [awkwardTrainingMaxChange(log.exercises[0].id)],
            routines: [awkwardRoutine()],
            routineExercises: [awkwardRoutineExercise(log.exercises[0].id)],
            routineTargetGroups: [awkwardTargetGroup()],
            plannedTargets: [awkwardPlannedTarget(log.entries[0].id)],
            settings: awkwardSettings())
    }

    /// A routine the lifter archived — `FR-15.2.5`'s soft delete, which is the state the export
    /// never carries and a restore is documented not to give back.
    private static func awkwardRoutine() -> Routine {
        Routine(
            id: ExportRecords.id(0xAA),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: stamp,
            name: "\"heavy\" day")
    }

    /// The archived routine's one slot, soft-deleted with it.
    ///
    /// - Parameter exerciseID: What the slot prescribes.
    private static func awkwardRoutineExercise(_ exerciseID: UUID) -> RoutineExercise {
        RoutineExercise(
            id: ExportRecords.id(0xAB),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: stamp,
            routineID: ExportRecords.id(0xAA),
            exerciseID: exerciseID,
            order: 2)
    }

    /// A target group with no weight at all — `FR-15.2.2`'s blank target, and the one shape that
    /// proves an omitted optional is read back as absent rather than as zero.
    private static func awkwardTargetGroup() -> RoutineTargetGroup {
        RoutineTargetGroup(
            id: ExportRecords.id(0xAC),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: stamp,
            routineExerciseID: ExportRecords.id(0xAB),
            order: 0,
            targetWeight: nil,
            targetReps: 8,
            targetSets: 3)
    }

    /// What a routine planned for a logged slot, at a negative load — assisted work, which `Weight`
    /// is signed for.
    ///
    /// - Parameter entryID: The slot it was planned for.
    private static func awkwardPlannedTarget(_ entryID: UUID) -> PlannedTargetGroup {
        PlannedTargetGroup(
            id: ExportRecords.id(0xAD),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            exerciseEntryID: entryID,
            order: 1,
            targetWeight: Weight(grams: -15_000),
            targetReps: 6,
            targetSets: 4)
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
            percentage: 0.925,
            roundingIncrement: Weight(grams: 1_250),
            roundingStrategy: .nearest,
            progressionIncrement: Weight(grams: -5_000),
            effectiveFrom: stamp)
    }

    /// A change to a training max, with every column off its default: an old value present, a
    /// reason that is not the empty string, and a new value that is neither.
    ///
    /// **``effectiveFrom`` is a day before ``stamp`` rather than equal to it**, so the two dates a
    /// restore preserves cannot stand in for one another in a field-for-field comparison.
    private static func awkwardTrainingMaxChange(_ exerciseID: UUID) -> TrainingMaxHistoryEntry {
        TrainingMaxHistoryEntry(
            id: ExportRecords.id(0x99),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: nil,
            exerciseID: exerciseID,
            effectiveFrom: stamp.addingTimeInterval(-86_400),
            oldWeight: Weight(grams: 137_500),
            newWeight: Weight(grams: 142_500),
            reason: "coach, week 4")
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

    @Test("A backup round-trips its seven extra sections too")
    func backupRoundTripsLosslessly() throws {
        let backup = Self.awkwardBackup()
        let restored = try TrainingLogArchive.decoded(from: backup.encoded())
        #expect(restored.equipment.first?.deletedAt == Self.stamp)
        #expect(restored.settings?.displayUnit == .pounds)
        #expect(restored.trainingMaxes.first?.progressionIncrement == Weight(grams: -5_000))
        #expect(restored.routines.first?.deletedAt == Self.stamp)
        #expect(restored.routineTargetGroups.first?.targetWeight == nil)
        #expect(restored.plannedTargets.first?.targetWeight == Weight(grams: -15_000))
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

    @Test("A backup writes the eight extra keys and an export writes none of them")
    func onlyABackupCarriesTheConfiguration() throws {
        let backup = try #require(String(data: Self.awkwardBackup().encoded(), encoding: .utf8))
        #expect(
            TrainingLogArchiveTests.envelopeKeys(of: backup) == [
                "bodyweight", "contents", "entries", "equipment", "exercises", "exportedAt",
                "formatVersion", "plannedTargets", "routineExercises", "routineTargetGroups",
                "routines", "sessions", "sets", "settings", "trainingMaxHistory", "trainingMaxes",
            ])
        let export = try #require(String(data: TrainingLogArchiveTests.awkwardArchive().encoded(), encoding: .utf8))
        // An empty section is omitted rather than written as `[]`, so an export's bytes are what
        // version 1 wrote plus the one key that says what it is.
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("equipment"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("settings"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("trainingMaxes"))
        #expect(
            !TrainingLogArchiveTests.envelopeKeys(of: export).contains("trainingMaxHistory"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("routines"))
        #expect(!TrainingLogArchiveTests.envelopeKeys(of: export).contains("plannedTargets"))
    }

    /// `G-1.4` and `TR-16.1`: the personal-record cache is derived, so it is not a section — and a
    /// restore recomputes it rather than reinstating an answer. `TR-16.1`'s two new columns are
    /// therefore not a table added to the backup, which is why the format version does not move.
    @Test("The derived record cache is not a section of the backup")
    func theRecordCacheIsNotBackedUp() throws {
        let backup = try #require(String(data: Self.awkwardBackup().encoded(), encoding: .utf8))
        let sections = TrainingLogArchiveTests.envelopeKeys(of: backup)

        #expect(!sections.contains("personalRecords"))
        #expect(!sections.contains { $0.localizedCaseInsensitiveContains("personalRecord") })
        // Anchored, so the three absences above cannot pass over an empty key list.
        #expect(sections.contains("sets"))
        #expect(TrainingLogArchive.currentFormatVersion == 4)
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
        #expect(restored.routines.isEmpty)
        #expect(restored.plannedTargets.isEmpty)
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

    @Test("A format-3 backup decodes with the training-max history empty")
    func readsAFormatThreeBackup() throws {
        // Version 3 predates `trainingMaxHistory`, so the key is simply absent — rule 3 read one
        // level up, which is what lets the version move without breaking the files before it. The
        // configuration row here also carries `manualWeight`, the column the number moved out of:
        // an unknown key is dropped rather than refused, so the row still restores.
        let json = """
            {
              "formatVersion" : 3,
              "contents" : "fullBackup",
              "exportedAt" : 773452800.1234567,
              "exercises" : [],
              "sessions" : [],
              "entries" : [],
              "sets" : [],
              "bodyweight" : [],
              "trainingMaxes" : [
                {
                  "id" : "0F5A1E24-9B7D-4C31-8E62-000000000008",
                  "createdAt" : 0,
                  "updatedAt" : 0,
                  "exerciseID" : "0F5A1E24-9B7D-4C31-8E62-000000000009",
                  "source" : "manual",
                  "manualWeight" : 180000,
                  "percentage" : 0.9,
                  "roundingIncrement" : 2500,
                  "roundingStrategy" : "nearest",
                  "effectiveFrom" : 0
                }
              ]
            }
            """
        let restored = try TrainingLogArchive.decoded(from: Data(json.utf8))

        #expect(restored.trainingMaxHistory.isEmpty)
        // Anchored, so the emptiness above is not simply a file this build failed to read: the
        // section beside it came through whole.
        #expect(restored.trainingMaxes.count == 1)
        #expect(restored.trainingMaxes.first?.percentage == 0.9)
        #expect(restored.formatVersion == 3)
        #expect(restored.contents == .fullBackup)
    }
}
