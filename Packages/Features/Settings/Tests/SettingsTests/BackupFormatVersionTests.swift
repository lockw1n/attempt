import Foundation
import Persistence
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

// Split out of `BackupRoundTripTests.swift` for size — that file reached the 500-line ceiling once
// `TR-16.3` gave the archive a fifteenth section. The line is the one the suites were already drawn
// along: what a file written by an EARLIER build restores to, and nothing else. The round trip
// proper — export, wipe, restore, compare — stays where it was.

@Suite("A backup written by an earlier format restores")
struct BackupFormatVersionTests {
    @Test func aFormatThreeFileRestoresItsConfigurationsAndNoHistory() async throws {
        // `currentFormatVersion` moved to 4 for `trainingMaxHistory`, so version 3 is the last file
        // written without it — and `FR-1.11.4` accepts any version at or below this build's. Such a
        // file has to restore, land the section it does carry, and leave the table it does not
        // carry empty rather than refusing or half-writing.
        //
        // **THE FIXTURE CARRIES A CONFIGURATION, AND THE ASSERTIONS BELOW ARE WHY.** A format-3
        // file with both sections empty makes "the history table is empty" true of every
        // implementation, including one that never reads either section — the emptiness would be
        // the fixture's, not the restore's. One live configuration is what turns the pair into a
        // contrast: the section that is there lands, the section that is absent does not.
        //
        // **AND ITS BYTES CARRY `manualWeight`**, injected below, because that is what a real
        // format-3 configuration looks like: the column the number moved out of. An unknown key is
        // dropped rather than refused (rule 7 of `RecordCoding.swift`), so a lifter's old backup
        // still restores every configuration it holds — through the store here, where
        // `BackupArchiveTests` proves the same of the decode alone.
        let stack = try PersistenceStack(location: .inMemory)
        let settings = try await stack.settings.settings()
        let squat = ExportRecords.exercise(name: "Squat", at: ExportLog.epoch)
        let configuration = TrainingMaxEntry(
            id: ExportRecords.id(0x21),
            createdAt: ExportLog.epoch,
            updatedAt: ExportLog.epoch,
            deletedAt: nil,
            exerciseID: squat.id,
            source: .manual,
            sourceRepCount: nil,
            percentage: 0.9,
            roundingIncrement: Weight(grams: 2_500),
            roundingStrategy: .nearest,
            progressionIncrement: nil,
            effectiveFrom: ExportLog.epoch.addingTimeInterval(-86_400))
        let file = TrainingLogArchive(
            formatVersion: 3,
            contents: .fullBackup,
            exportedAt: ExportLog.epoch,
            exercises: [squat],
            sessions: [],
            entries: [],
            sets: [],
            bodyweight: [],
            equipment: [],
            trainingMaxes: [configuration],
            trainingMaxHistory: [],
            routines: [],
            routineExercises: [],
            routineTargetGroups: [],
            plannedTargets: [],
            settings: settings)

        // Through the bytes rather than the value, so the version is read the way a lifter's file
        // is: `archive(from:)` is what `FR-1.11.4` refuses a future file on.
        let accepted = try StoreRestore.archive(from: try Self.carryingRetiredManualWeight(file))
        #expect(accepted.formatVersion == 3)
        try await BackupRoundTripTests.restore(into: stack).restore(accepted)

        let configurations = try await stack.trainingMaxes.configurationHistory(
            forExerciseID: squat.id, includingDeleted: true)
        #expect(configurations.map(\.id) == [configuration.id])
        #expect(configurations.first?.percentage == 0.9)
        #expect(configurations.first?.effectiveFrom == configuration.effectiveFrom)
        #expect(
            try await stack.trainingMaxes.history(
                forExerciseID: squat.id, includingDeleted: true
            ).isEmpty)
        #expect(try await stack.exercises.exercises(includingDeleted: false).count == 1)
    }

    /// `file` as bytes, with the retired `manualWeight` key put back on its one configuration row.
    ///
    /// **Injected rather than encoded, because the record can no longer write it** — which is the
    /// point: the key exists only in files this build did not produce, and that is the only shape a
    /// format-3 backup comes in.
    ///
    /// - Parameter file: An archive holding exactly one training-max configuration.
    /// - Returns: Its bytes, carrying one key more than this build writes.
    /// - Throws: A `DecodingError` if the archive will not encode.
    private static func carryingRetiredManualWeight(_ file: TrainingLogArchive) throws -> Data {
        let json = try #require(String(bytes: try file.encoded(), encoding: .utf8))
        // `percentage` is written by the training-max records alone and the archive holds one, so
        // the anchor is unambiguous. `#require` is what says so rather than assuming it.
        let anchor = try #require(json.range(of: "\"percentage\""))
        var injected = json
        injected.replaceSubrange(anchor, with: "\"manualWeight\" : 180000,\n\"percentage\"")
        return Data(injected.utf8)
    }
}
