import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import DerivedValues
@testable import Settings

// FR-1.11.4. Two claims, and they are not the same claim: that a file this build cannot honour is
// refused BEFORE anything is written, and that a file it can honour comes back whole.
//
// THE ROUND TRIP IS THROUGH THE REAL FAKES IN BOTH DIRECTIONS — T-1.66's `FullBackup` reads one
// store and this writes a second — because that is the only arrangement in which `TR-0.4.4`'s
// mapping is genuinely exercised in the direction this task adds. A test that compared an archive
// to itself would agree with a restore that wrote nothing at all.

@Suite("Restore")
struct RestoreTests {
    /// The writer over a fresh, empty store.
    ///
    /// - Parameter stack: The fakes to write into.
    /// - Returns: The restore.
    static func restore(into stack: InMemoryRepositoryStack) -> StoreRestore {
        restore(into: FixtureRepositories(stack))
    }

    /// The writer over whichever store a fixture is holding.
    ///
    /// - Parameter stack: The repositories to write into.
    /// - Returns: The restore.
    static func restore(into stack: FixtureRepositories) -> StoreRestore {
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

    /// A backup taken over a store with something in every table.
    ///
    /// - Returns: The archive and the store it came from.
    static func backupOfWholeStore() async throws -> (TrainingLogArchive, ExportLog) {
        let source = try await ExportLog.wholeStore()
        return (try await source.backup.archive(takenAt: ExportLog.epoch), source)
    }

    // MARK: - What comes back

    @Test func writesEveryTableIntoAFreshStore() async throws {
        // The Done-when's first line: a backup restored into a clean install reproduces every
        // entity. Read back as a second backup, so the comparison is over the same nine reads that
        // wrote the file rather than over whatever this test remembered to check.
        let (archive, _) = try await Self.backupOfWholeStore()
        let target = InMemoryRepositoryStack()
        try await Self.restore(into: target).restore(archive)

        let reread = try await FullBackup(
            exercises: target.exercises,
            workouts: target.workouts,
            bodyweight: target.bodyweight,
            equipment: target.equipment,
            routines: target.routines,
            settings: target.settings
        ).archive(takenAt: ExportLog.epoch)

        #expect(reread.exercises.count == archive.exercises.count)
        #expect(reread.sessions.count == archive.sessions.count)
        #expect(reread.entries.count == archive.entries.count)
        #expect(reread.sets.count == archive.sets.count)
        #expect(reread.bodyweight.count == archive.bodyweight.count)
        #expect(reread.equipment.count == archive.equipment.count)
        #expect(reread.trainingMaxes.count == archive.trainingMaxes.count)
        // The row rather than the whole value: `updatedAt` is restamped by the save, which the
        // test below is about.
        #expect(reread.settings?.id == archive.settings?.id)
        #expect(reread.settings?.theme == archive.settings?.theme)
        #expect(reread.settings?.e1RMLookbackDays == archive.settings?.e1RMLookbackDays)
        // Anchored to a literal, not just to each other: every count above is satisfied by a
        // restore that wrote nothing into a store the fixture also left empty.
        #expect(!archive.sets.isEmpty)
        #expect(archive.trainingMaxes.count == 2)
    }

    @Test func reproducesEveryColumnOfARestoredSet() async throws {
        // The counts above say the rows arrived; this says the mapping carried their contents.
        // A set is the row with the most columns and the only one carrying a modifier list.
        let (archive, _) = try await Self.backupOfWholeStore()
        let target = InMemoryRepositoryStack()
        try await Self.restore(into: target).restore(archive)

        for original in archive.sets {
            let restored = try await target.workouts.sets(
                forEntryID: original.entryID, includingDeleted: true
            ).first { $0.id == original.id }
            #expect(restored?.weight == original.weight)
            #expect(restored?.reps == original.reps)
            #expect(restored?.isWarmup == original.isWarmup)
            #expect(restored?.isCompleted == original.isCompleted)
            #expect(restored?.order == original.order)
            #expect(restored?.createdAt == original.createdAt)
        }
    }

    @Test func reinstatesASoftDeletedRowAsALiveOne() async throws {
        // Gap §32, pinned rather than merely documented. `RecordMapping` rule 1 leaves `deletedAt`
        // to `markDeleted(at:)`, so nothing this layer writes can put a row back as deleted — and
        // the confirmation copy is what says so. If a writer ever does close this, this test is the
        // one that fails and says the copy has to change with it.
        let (archive, _) = try await Self.backupOfWholeStore()
        #expect(archive.deletedCount > 0)

        let target = InMemoryRepositoryStack()
        try await Self.restore(into: target).restore(archive)

        let reread = try await FullBackup(
            exercises: target.exercises,
            workouts: target.workouts,
            bodyweight: target.bodyweight,
            equipment: target.equipment,
            routines: target.routines,
            settings: target.settings
        ).archive(takenAt: ExportLog.epoch)
        #expect(reread.deletedCount == 0)
        // ANCHORED, and this line is the test. `deletedCount == 0` is also what an untouched store
        // reads back, so on its own the assertion above is satisfied by a restore that wrote
        // nothing at all — measured, not supposed. The row count is what says the rows arrived;
        // only then is the zero above a statement about HOW they arrived.
        #expect(reread.recordCount == archive.recordCount)
        #expect(archive.recordCount > archive.deletedCount)
    }

    @Test func reportsWhatTheFileHeldRatherThanWhatCameBackLive() async throws {
        // T-1.66's reading, carried across the confirmation: `deletedCount` counts records the FILE
        // holds. The two numbers diverge exactly where the test above lives, and the screen says
        // the file's — a summary that reported zero would be the summary that hid the divergence.
        let (archive, _) = try await Self.backupOfWholeStore()
        let summary = try await Self.restore(into: InMemoryRepositoryStack()).restore(archive)
        #expect(summary.deletedCount == archive.deletedCount)
        #expect(summary.deletedCount > 0)
        #expect(summary.recordCount == archive.recordCount)
        #expect(summary.workoutCount == archive.sessions.count)
        #expect(summary.takenAt == ExportLog.epoch)
    }

    @Test func overwritesARowTheStoreAlreadyHoldsUnderTheSameIdentifier() async throws {
        // The design this task settled on: an id-keyed overwrite rather than a wipe-and-write. A
        // row present under both names is the file's afterwards, which is what makes the
        // confirmation's "writes over" sentence true.
        let target = try await ExportLog.populated()
        let squat = try await target.exercise(named: "Back Squat")
        let edited = ExportRecords.exercise(
            id: squat.id, name: "Squat, as backed up", at: ExportLog.epoch)

        try await Self.restore(into: target.repositories).restore(
            TrainingLogArchive(
                takenAt: ExportLog.epoch,
                exercises: [edited],
                sessions: [],
                entries: [],
                sets: [],
                bodyweight: [],
                equipment: [],
                trainingMaxes: [],
                routines: [],
                routineExercises: [],
                routineTargetGroups: [],
                plannedTargets: [],
                settings: try await target.repositories.settings.settings()))

        let read = try await target.repositories.exercises.exercise(
            id: squat.id, includingDeleted: true)
        #expect(read?.name == "Squat, as backed up")
    }

    @Test func leavesARowTheFileDoesNotName() async throws {
        // The other half of the same decision, and the half the copy has to admit to: nothing is
        // emptied first, so a record the file has never heard of survives. A wipe is not available
        // — see `StoreRestore` for the measurement that rules it out — so this is the behaviour the
        // confirmation describes rather than a shortfall it hides.
        let target = try await ExportLog.populated()
        let ours = try await target.exercise(named: "Only on this device")
        // The file names one row of its own, so this test is about a restore that RAN. Without it
        // the survival below is equally the story of a restore that wrote nothing — measured.
        let theirs = ExportRecords.exercise(
            id: UUID(), name: "Only in the file", at: ExportLog.epoch)

        try await Self.restore(into: target.repositories).restore(
            TrainingLogArchive(
                takenAt: ExportLog.epoch,
                exercises: [theirs],
                sessions: [],
                entries: [],
                sets: [],
                bodyweight: [],
                equipment: [],
                trainingMaxes: [],
                routines: [],
                routineExercises: [],
                routineTargetGroups: [],
                plannedTargets: [],
                settings: try await target.repositories.settings.settings()))

        let read = try await target.repositories.exercises.exercise(
            id: ours.id, includingDeleted: true)
        #expect(read?.name == "Only on this device")
        let landed = try await target.repositories.exercises.exercise(
            id: theirs.id, includingDeleted: true)
        #expect(landed?.name == "Only in the file")
    }

    @Test func rebuildsTheRecordCacheTheFileDeliberatelyDoesNotCarry() async throws {
        // T-1.66 left the PR cache out of the file (derived, G-1.4), so the rows a restore writes
        // arrive with no records computed over them. Left unhooked, every badge and estimated-max
        // tile would read whatever the device held before.
        let (archive, _) = try await Self.backupOfWholeStore()
        let target = InMemoryRepositoryStack()
        #expect(try await target.personalRecords.personalRecords(includingDeleted: true).isEmpty)

        try await Self.restore(into: target).restore(archive)
        #expect(!(try await target.personalRecords.personalRecords(includingDeleted: true).isEmpty))
    }

    @Test func keepsCreatedAtAndRestampsUpdatedAt() async throws {
        // Rule 1 of `RecordMapping` from the caller's side, and the reason the test above cannot
        // compare whole rows. `createdAt` is the record's — the row is new and the file's history
        // is the only history there is — while `updatedAt` belongs to the save that just ran.
        //
        // WORTH KNOWING FOR G-2.4: every restored row therefore carries a stamp from the restore,
        // so a restore outranks a remote edit made before it on the conflict key. That is the same
        // reading `updatedAt` already has (an audit field, not a merge key), stated where a restore
        // makes it visible.
        let (archive, _) = try await Self.backupOfWholeStore()
        let target = InMemoryRepositoryStack()
        let before = Date.now
        try await Self.restore(into: target).restore(archive)

        let original = try #require(archive.sessions.first)
        let restored = try #require(
            try await target.workouts.session(id: original.id, includingDeleted: true))
        #expect(restored.createdAt == original.createdAt)
        #expect(restored.updatedAt >= before)
        #expect(restored.updatedAt > original.updatedAt)
    }

    // MARK: - What is refused

    @Test func refusesATrainingLogExport() async throws {
        // The discriminator T-1.66 added, doing the job it was added for. An export decodes
        // perfectly — it is the same envelope — so nothing but `contents` separates the two.
        let log = try await ExportLog.populated()
        let export = try await log.export.archive(exportedAt: ExportLog.epoch)
        #expect(throws: RestoreRefusal.notABackup) {
            try StoreRestore.archive(from: try export.encoded())
        }
    }

    @Test func refusesAVersionOneFile() throws {
        // A file written before `contents` existed IS an export (T-1.66's "a fact rather than a
        // default"), so it is refused as one rather than as unreadable.
        let payload = Data(
            """
            {"formatVersion":1,"exportedAt":0,"exercises":[],"sessions":[],"entries":[],
             "sets":[],"bodyweight":[]}
            """.utf8)
        #expect(throws: RestoreRefusal.notABackup) {
            try StoreRestore.archive(from: payload)
        }
    }

    @Test func refusesAFileFromALaterVersion() async throws {
        // The Scope's version marker. A future file that still decodes is caught by the guard —
        // this is the case where the bytes are readable and the CLAIM is not honourable.
        // ONE PAST WHATEVER THIS BUILD WRITES, rather than a literal: the version has moved once
        // since this test was written, and a literal here would have started asserting that a file
        // this build itself produces is refused.
        let next = TrainingLogArchive.currentFormatVersion + 1
        let (archive, _) = try await Self.backupOfWholeStore()
        let future = try Self.reversioned(archive, to: next)
        #expect(throws: RestoreRefusal.futureVersion(next)) {
            try StoreRestore.archive(from: future)
        }
    }

    @Test func refusesAFutureFileThatWillNotDecodeAsFutureRatherThanAsDamaged() throws {
        // The reason the version is asked first. A later version may spell `contents` in a way this
        // build refuses (T-1.66's closed vocabulary), and reading THAT as "damaged" would send the
        // lifter looking for another copy of a file that is fine.
        let payload = Data(
            """
            {"formatVersion":9,"contents":"fullBackupWithPrograms","exportedAt":0}
            """.utf8)
        #expect(throws: RestoreRefusal.futureVersion(9)) {
            try StoreRestore.archive(from: payload)
        }
    }

    @Test func refusesAnUnknownContentsAtAVersionItCanRead() throws {
        // The same spelling at a version this build DOES claim to read is corruption rather than
        // the future, and is refused as such. This is the case that stops the version peek from
        // becoming a blanket "anything that fails to decode must be newer".
        let payload = Data(
            """
            {"formatVersion":2,"contents":"somethingElse","exportedAt":0,"exercises":[],
             "sessions":[],"entries":[],"sets":[],"bodyweight":[]}
            """.utf8)
        #expect(throws: RestoreRefusal.unreadable) {
            try StoreRestore.archive(from: payload)
        }
    }

    @Test func refusesBytesThatAreNotAnArchiveAtAll() throws {
        #expect(throws: RestoreRefusal.unreadable) {
            try StoreRestore.archive(from: Data("not a backup".utf8))
        }
        #expect(throws: RestoreRefusal.unreadable) {
            try StoreRestore.archive(from: Data())
        }
    }

    @Test func acceptsABackupAtTheVersionThisBuildWrites() async throws {
        // The negative case's mirror, so the four refusals above are not passing because everything
        // is refused.
        let (archive, _) = try await Self.backupOfWholeStore()
        let read = try StoreRestore.archive(from: try archive.encoded())
        #expect(read.contents == .fullBackup)
        #expect(read.formatVersion == TrainingLogArchive.currentFormatVersion)
    }

    /// The same archive with a different version stamped on it.
    ///
    /// **Rewritten as JSON rather than re-encoded from a modified value**, because the envelope's
    /// version is the encoder's own constant — there is no initialiser that would let a test claim
    /// a version this build cannot write, which is the point.
    ///
    /// - Parameters:
    ///   - archive: The file.
    ///   - version: What to claim.
    /// - Returns: The payload.
    static func reversioned(_ archive: TrainingLogArchive, to version: Int) throws -> Data {
        let text = String(bytes: try archive.encoded(), encoding: .utf8) ?? ""
        return Data(
            text.replacingOccurrences(
                of: "\"formatVersion\" : \(TrainingLogArchive.currentFormatVersion)",
                with: "\"formatVersion\" : \(version)"
            ).utf8)
    }
}
