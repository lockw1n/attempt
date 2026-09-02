import Foundation
import Persistence
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

// DOD-1.3, the formal verification: export a full backup, wipe the install, restore, and compare
// what came back against what went in.
//
// THREE THINGS SEPARATE THIS FROM `RestoreTests`, AND ALL THREE ARE WHY IT COULD NOT BE A CASE
// THERE. It runs against the REAL SwiftData store rather than the fakes, so `TR-0.4.4`'s mapping is
// the thing under test rather than a dictionary. It WIPES rather than restoring into a second empty
// store, through `TR-1.14`'s purge — which is the only caller `PurgeScope.everything` has, and the
// one the wipe half of this criterion is written against. And it goes through the FILE: the archive
// is encoded to bytes and read back through the refusal boundary, because `FR-1.11.3`'s deliverable
// is a file rather than a value.
//
// THE COMPARISON IS FIELD-FOR-FIELD AND GENERIC, WHICH IS DELIBERATE. Every row is re-encoded with
// the archive's own encoder and compared as a dictionary of wire keys, so a column added to any
// record later is compared by this suite the day it exists. A hand-written list of properties would
// have to be remembered instead — and the defect this task found is exactly what happens when a
// table is added and nobody remembers.

@Suite("Backup round trip")
struct BackupRoundTripTests {
    // MARK: - The round trip

    @Test func exportWipeRestoreIsLosslessOverTheRealStore() async throws {
        let stack = try PersistenceStack(location: .inMemory)
        let fixture = try await ExportLog.wholeStore(ExportLog(stack))
        try await fixture.setDisplayUnit(.pounds)

        let before = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        let file = try before.encoded()

        // The wipe. `retained` is the policy made visible: under `.everything` nothing survives to
        // hold a row back, so a non-zero here is a defect in the purge rather than in the restore.
        let wiped = try await stack.purge(.everything)
        #expect(wiped.retained == 0)
        #expect(wiped.removed == before.recordCount)
        try await Self.expectEmpty(stack)

        // Through the refusal boundary, not around it: a file this build cannot honour never
        // reaches `restore(_:)`, and the round trip has to prove its own file is honoured.
        let reread = try StoreRestore.archive(from: file)
        #expect(reread == before)
        try await Self.restore(into: stack).restore(reread)

        let after = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        try Self.expectSameRows(before, after)
    }

    // MARK: - The two documented divergences

    @Test func everySoftDeletedRowComesBackLive() async throws {
        // FR-1.11.4's known limitation, and the reason this criterion is met WITH a stated
        // exception rather than met plainly. `init(record:)` leaves `deletedAt` nil (rule 1 of
        // `RecordMapping.swift`), so the column cannot survive a restore that writes new rows.
        //
        // ANCHORED ON BOTH SIDES. `deletedCount == 0` after is also what an empty store reads, so
        // the literal before it is what makes this a claim about the restore.
        let stack = try PersistenceStack(location: .inMemory)
        let fixture = try await ExportLog.wholeStore(ExportLog(stack))
        _ = fixture

        let before = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        #expect(before.deletedCount == 9)
        try await stack.purge(.everything)
        try await Self.restore(into: stack).restore(before)

        let after = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        #expect(after.deletedCount == 0)
        #expect(after.recordCount == before.recordCount)
    }

    @Test func everyRestoredRowKeepsItsCreatedAtAndIsRestamped() async throws {
        // The second divergence, and the one that is not a limitation: `saveStamped` stamps
        // `updatedAt` on every row it writes (`G-2.4`), so a restore restamps the whole store. That
        // is why `expectSameRows` compares every wire key EXCEPT this one, and this is the test
        // that says so out loud rather than leaving the omission to be read as an oversight.
        //
        // `createdAt` is the opposite case and the reason the round trip is worth anything:
        // `init(record:)` honours it on a new row, so restored history is still dated when it
        // happened rather than when it was restored.
        let stack = try PersistenceStack(location: .inMemory)
        _ = try await ExportLog.populated(ExportLog(stack))

        let before = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        try await stack.purge(.everything)
        try await Self.restore(into: stack).restore(before)
        let after = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)

        let restored = try #require(after.sets.first { $0.id == before.sets[0].id })
        #expect(restored.createdAt == ExportLog.epoch)
        #expect(restored.updatedAt > ExportLog.epoch)
        #expect(restored.updatedAt >= before.sets[0].updatedAt)
        // And the fixture's own write was already restamped, which is the same rule seen from the
        // other end: the record handed to `save` carried the epoch in BOTH columns, and only
        // `createdAt` survived the insert.
        #expect(before.sets[0].createdAt == ExportLog.epoch)
        #expect(before.sets[0].updatedAt > ExportLog.epoch)
    }

    // MARK: - What the wipe has to leave alone

    @Test func restoringOntoAMintedIdentityKeepsItAndTakesThePreferences() async throws {
        // FR-1.11.3's clean install, over the real store and through the file — and the case the
        // round trip above cannot see. `TR-1.10`'s find-or-create mints a `userID` the first time
        // anything reads settings, and the shipping app reads settings at every launch, so by the
        // time a lifter can reach the restore screen there is ALWAYS an identity in force and the
        // file's is always foreign. This threw before T-1.69, on the last of twelve writes, with
        // every other table already landed and a screen saying to run the same file again.
        let stack = try PersistenceStack(location: .inMemory)
        let fixture = try await ExportLog.wholeStore(ExportLog(stack))
        try await Self.configureEveryPreference(of: stack)
        _ = fixture

        let before = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        let file = try before.encoded()
        let fromAnotherDevice = try #require(before.settings)

        try await stack.purge(.everything)
        // The launch, which is the whole point of the fixture: this is what makes the file foreign.
        let minted = try await stack.settings.settings()
        #expect(minted.userID != fromAnotherDevice.userID)

        try await Self.restore(into: stack).restore(StoreRestore.archive(from: file))

        let after = try await Self.backup(over: stack).archive(takenAt: ExportLog.epoch)
        let restored = try #require(after.settings)
        // The rule, asserted from both directions rather than left as whatever landed.
        #expect(restored.userID == minted.userID)
        #expect(restored.userID != fromAnotherDevice.userID)
        #expect(restored.id == minted.id)
        #expect(restored.createdAt == minted.createdAt)

        // …and every other table is whole, which is the half the refusal used to leave written but
        // reported as a failure.
        try Self.expectSameRows(before, after, settingsIdentityMoved: true)
    }

    /// Moves every preference off the value a first-launch row holds, so a restore that wrote
    /// nothing is visible in each column rather than in one.
    ///
    /// **The dashboard selection names an exercise that is in the fixture**, which is the one
    /// preference whose value is a join key; the rest are scalars and any distinct value does.
    ///
    /// - Parameter stack: The store to configure.
    /// - Throws: Whatever the repository throws.
    static func configureEveryPreference(of stack: PersistenceStack) async throws {
        let tiled = try #require(try await stack.exercises.exercises(includingDeleted: false).first)
        var configured = try await stack.settings.settings()
        configured.displayUnit = .pounds
        configured.displayPrecision = DisplayPrecision(milliUnits: 100)
        configured.e1RMFormula = .brzycki
        configured.e1RMLookbackDays = 30
        configured.theme = .light
        configured.keepScreenAwake = false
        configured.defaultRoundingIncrement = Weight(grams: 1134)
        configured.defaultRoundingStrategy = .down
        configured.dashboardExerciseIDs = [tiled.id]
        try await stack.settings.save(configured)
    }

    // MARK: - Subjects

    /// The reader over a real store.
    ///
    /// - Parameter stack: The store.
    /// - Returns: The backup.
    static func backup(over stack: PersistenceStack) -> FullBackup {
        FullBackup(
            exercises: stack.exercises,
            workouts: stack.workouts,
            bodyweight: stack.bodyweight,
            equipment: stack.equipment,
            routines: stack.routines,
            settings: stack.settings)
    }

    /// The writer over a real store.
    ///
    /// - Parameter stack: The store.
    /// - Returns: The restore.
    static func restore(into stack: PersistenceStack) -> StoreRestore {
        StoreRestore(
            exercises: stack.exercises,
            workouts: stack.workouts,
            bodyweight: stack.bodyweight,
            equipment: stack.equipment,
            routines: stack.routines,
            settings: stack.settings,
            records: PersonalRecordRecomputer(
                workouts: stack.workouts,
                exercises: stack.exercises,
                cache: stack.personalRecords))
    }

    // MARK: - Comparison

    /// Fails unless every read a backup makes comes back empty.
    ///
    /// **The settings row is asked for by count rather than by ``RepositoryInterface/SettingsRepository/settings()``**,
    /// which would mint one — see ``mintingTheSettingsRowBeforeTheRestoreRefusesIt``. There is no
    /// read that can see the row without creating it, so the purge's own report is the evidence for
    /// that one table and the five below are the evidence for the rest.
    ///
    /// **Five reads for twelve tables, and the seven missing ones cannot be asked.** Every child
    /// table is reached through its parent's identifier, so once the parents are gone there is
    /// nothing left to enumerate them from — which is why `wiped.removed` carries the weight for
    /// those rather than a read.
    ///
    /// - Parameter stack: The wiped store.
    /// - Throws: Whatever a repository throws.
    static func expectEmpty(_ stack: PersistenceStack) async throws {
        let all = Date.distantPast...Date.distantFuture
        #expect(try await stack.exercises.exercises(includingDeleted: true).isEmpty)
        #expect(try await stack.workouts.sessions(in: all, includingDeleted: true).isEmpty)
        #expect(try await stack.bodyweight.entries(in: all, includingDeleted: true).isEmpty)
        #expect(try await stack.equipment.profiles(includingDeleted: true).isEmpty)
        #expect(try await stack.routines.routines(includingDeleted: true).isEmpty)
    }

    /// Fails unless the two archives hold the same rows, field for field.
    ///
    /// **The list below is hand-written and omitting a line from it compiles**, so
    /// ``expectEverySectionCompared(_:_:)`` is what actually holds it complete. `TrainingLogArchive`'s
    /// explicit initialiser forces a new section to be answered wherever one is *built*, which is
    /// what keeps the fixtures honest; nothing forces it to be answered *here*, and a comparison
    /// that quietly skips a table is the defect this suite exists to catch.
    ///
    /// - Parameters:
    ///   - before: The archive taken before the wipe.
    ///   - after: The archive taken after the restore.
    /// - Throws: A `DecodingError` if a record will not re-encode.
    static func expectSameRows(
        _ before: TrainingLogArchive,
        _ after: TrainingLogArchive,
        settingsIdentityMoved: Bool = false
    ) throws {
        var compared: Set<String> = []
        try expectSameRows(before.exercises, after.exercises, "exercises", &compared)
        try expectSameRows(before.sessions, after.sessions, "sessions", &compared)
        try expectSameRows(before.entries, after.entries, "entries", &compared)
        try expectSameRows(before.sets, after.sets, "sets", &compared)
        try expectSameRows(before.bodyweight, after.bodyweight, "bodyweight", &compared)
        try expectSameRows(before.equipment, after.equipment, "equipment", &compared)
        try expectSameRows(before.trainingMaxes, after.trainingMaxes, "trainingMaxes", &compared)
        try expectSameRows(before.routines, after.routines, "routines", &compared)
        try expectSameRows(
            before.routineExercises, after.routineExercises, "routineExercises", &compared)
        try expectSameRows(
            before.routineTargetGroups, after.routineTargetGroups, "routineTargetGroups", &compared)
        try expectSameRows(before.plannedTargets, after.plannedTargets, "plannedTargets", &compared)
        if settingsIdentityMoved {
            compared.insert("settings")
            try expectSamePreferences(before.settings, after.settings)
        } else {
            try expectSameRows(
                before.settings.map { [$0] } ?? [],
                after.settings.map { [$0] } ?? [],
                "settings",
                &compared)
        }
        try expectEverySectionCompared(before, compared)
    }

    /// Fails unless every section the file actually carries was compared.
    ///
    /// **Read off the encoded envelope rather than a second hand-written list**, which is the only
    /// reading that cannot itself go stale: a section added to ``TrainingLogArchive`` shows up here
    /// as a key nobody compared, on the first run after the fixture writes a row into it.
    ///
    /// The residual hole is a section the fixture leaves empty — an omitted key (rule 3) is a
    /// section this file does not carry, and there is nothing to compare. That is the same
    /// condition ``expectSameRows(_:_:_:_:)``'s own non-empty anchor reports for every section
    /// named above.
    ///
    /// - Parameters:
    ///   - archive: The file taken before the wipe.
    ///   - compared: The sections that were checked.
    /// - Throws: A `DecodingError` if the archive will not encode.
    static func expectEverySectionCompared(
        _ archive: TrainingLogArchive,
        _ compared: Set<String>
    ) throws {
        let envelope: Set<String> = ["contents", "exportedAt", "formatVersion"]
        let json = try #require(String(bytes: try archive.encoded(), encoding: .utf8))
        let carried = Set(TrainingLogArchiveTests.envelopeKeys(of: json)).subtracting(envelope)
        #expect(carried == compared, "a section the file carries was never compared")
    }

    /// Fails unless one section came back whole.
    ///
    /// - Parameters:
    ///   - before: The section as it was written.
    ///   - after: The section as it was read back.
    ///   - section: What to name in a failure.
    ///   - compared: The ledger ``expectEverySectionCompared(_:_:)`` reads back.
    /// - Throws: A `DecodingError` if a record will not re-encode.
    static func expectSameRows<Record: StoredRecord>(
        _ before: [Record],
        _ after: [Record],
        _ section: String,
        _ compared: inout Set<String>
    ) throws {
        compared.insert(section)
        #expect(!before.isEmpty, "\(section) is empty, so this section asserts nothing")
        #expect(before.count == after.count, "\(section) row count")

        let written = try Dictionary(uniqueKeysWithValues: after.map { ($0.id, try fields(of: $0)) })
        for row in before {
            let match = written[row.id]
            #expect(match != nil, "\(section) lost \(row.id)")
            #expect(match == (try fields(of: row)), "\(section) row \(row.id)")
        }
    }

    /// Fails unless every preference the file carried is on the device, identity aside.
    ///
    /// **The same generic diff as every other section, three keys shorter.** A restore onto an
    /// identity that is already in force writes preferences and not identity (`TR-1.10`), so `id`,
    /// `userID` and `createdAt` are the row that was already there — and everything else has to be
    /// the file's, including a column this record gains later.
    ///
    /// - Parameters:
    ///   - before: The settings row the file carries.
    ///   - after: The row on the device after the restore.
    /// - Throws: A `DecodingError` if either will not re-encode.
    static func expectSamePreferences(_ before: UserSettings?, _ after: UserSettings?) throws {
        let file = try #require(before, "the file carries no settings row, so this asserts nothing")
        let device = try #require(after, "the device has no settings row after a restore")
        #expect(
            try preferenceFields(of: file) == preferenceFields(of: device),
            "a preference the file carried is not on the device")
    }

    /// One settings row's wire fields, less the three that belong to the identity in force.
    ///
    /// - Parameter settings: The row.
    /// - Returns: Its preferences, keyed as the file keys them.
    /// - Throws: A `DecodingError` if the encoded row is not a JSON object.
    static func preferenceFields(of settings: UserSettings) throws -> NSDictionary {
        let object = NSMutableDictionary(dictionary: try fields(of: settings))
        for key in ["id", "userID", "createdAt"] { object.removeObject(forKey: key) }
        return NSDictionary(dictionary: object)
    }

    /// One row's wire fields, less the two columns a restore is documented not to reproduce.
    ///
    /// **Through the archive's own encoder, so this reads the file's shape rather than the type's.**
    /// `TR-0.4.4`'s DTO is what a backup carries, and a comparison over the record's properties
    /// would agree with a wire format that had quietly stopped carrying one of them.
    ///
    /// - Parameter record: The row.
    /// - Returns: Its fields, keyed as the file keys them.
    /// - Throws: A `DecodingError` if the encoded row is not a JSON object.
    static func fields(of record: some StoredRecord) throws -> NSDictionary {
        let data = try TrainingLogArchive.encoder.encode(record)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "a record encoded to something else"))
        }
        object.removeValue(forKey: "updatedAt")
        object.removeValue(forKey: "deletedAt")
        return NSDictionary(dictionary: object)
    }
}
