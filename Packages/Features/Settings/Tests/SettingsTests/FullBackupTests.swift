import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Settings

/// `FR-1.11.3`'s reader: every table, every row, `deletedAt` intact.
@Suite("Full backup")
struct FullBackupTests {
    @Test("It carries every table the store has, not only the log's")
    func readsEverySection() async throws {
        let log = try await ExportLog.wholeStore()
        let archive = try await log.backup.archive(takenAt: ExportLog.epoch)
        // Anchored to counts rather than to `!isEmpty`: a reader that returned one row per section
        // would satisfy emptiness and lose the rest, and the two training maxes are the case that
        // says the *history* is carried rather than what is in force.
        #expect(archive.exercises.count == 3)
        #expect(archive.sessions.count == 4)
        #expect(archive.entries.count == 3)
        #expect(archive.sets.count == 5)
        #expect(archive.bodyweight.count == 2)
        #expect(archive.equipment.count == 2)
        #expect(archive.trainingMaxes.count == 2)
        // FR-15.2's four tables. The two target groups under one slot are this section's version of
        // the two training maxes above: a walk that stopped at the first would still read one.
        #expect(archive.routines.count == 2)
        #expect(archive.routineExercises.count == 2)
        #expect(archive.routineTargetGroups.count == 4)
        #expect(archive.plannedTargets.count == 2)
        #expect(archive.settings != nil)
    }

    @Test("The file says it is a backup, which is the only thing that separates it from an export")
    func namesItsContents() async throws {
        let log = try await ExportLog.wholeStore()
        let backup = try await log.backup.archive(takenAt: ExportLog.epoch)
        let export = try await log.export.archive(exportedAt: ExportLog.epoch)
        #expect(backup.contents == .fullBackup)
        #expect(export.contents == .trainingLog)
    }

    @Test("Soft-deleted rows are in the backup and not in the export")
    func carriesDeletedRows() async throws {
        let log = try await ExportLog.wholeStore()
        let backup = try await log.backup.archive(takenAt: ExportLog.epoch)
        let export = try await log.export.archive(exportedAt: ExportLog.epoch)
        // The gym, the reading and the session are three different repositories' delete calls, so
        // one of them behaving differently cannot hide behind the other two.
        #expect(backup.equipment.count { $0.deletedAt != nil } == 1)
        #expect(backup.bodyweight.count { $0.deletedAt != nil } == 1)
        #expect(backup.sessions.count { $0.deletedAt != nil } == 1)
        // The slot and its set, which a deleted *session* would not distinguish: this pair sits
        // inside a session that is still live.
        #expect(backup.entries.count { $0.deletedAt != nil } == 1)
        #expect(backup.sets.count { $0.deletedAt != nil } == 1)
        // An archived routine (`FR-15.2.5`) is a soft delete that cascades, so one call puts a
        // deleted row in three tables at once — the shape a per-table delete cannot produce.
        #expect(backup.routines.count { $0.deletedAt != nil } == 1)
        #expect(backup.routineExercises.count { $0.deletedAt != nil } == 1)
        #expect(backup.routineTargetGroups.count { $0.deletedAt != nil } == 2)
        #expect(export.equipment.isEmpty)
        #expect(export.bodyweight.count == 1)
        #expect(export.sessions.count == 3)
        #expect(export.entries.count == 2)
        #expect(export.sets.count == 4)
        // The export carries none of the four, whatever their state: they are configuration.
        #expect(export.routines.isEmpty)
        #expect(export.plannedTargets.isEmpty)
    }

    @Test("A deleted set is carried with the date it was deleted on, not merely present")
    func carriesTheDeletionDate() async throws {
        let log = try await ExportLog.populated()
        let session = try #require(
            try await log.repositories.workouts.sessions(
                in: Date.distantPast...Date.distantFuture, includingDeleted: false
            ).first)
        let entry = try #require(
            try await log.repositories.workouts.entries(
                forSessionID: session.id, includingDeleted: false
            ).first)
        let sets = try await log.repositories.workouts.sets(
            forEntryID: entry.id, includingDeleted: false)
        let removed = try #require(sets.first)
        try await log.repositories.workouts.deleteSet(id: removed.id)

        let archive = try await log.backup.archive(takenAt: ExportLog.epoch)
        let carried = try #require(archive.sets.first { $0.id == removed.id })
        // `deletedAt != nil` is the claim; the count beside it is what stops a reader that marked
        // every row deleted from passing.
        #expect(carried.deletedAt != nil)
        #expect(archive.sets.count { $0.deletedAt == nil } == 2)
    }

    @Test("The preferences row in the file is the one the store holds")
    func carriesThePreferencesRow() async throws {
        let log = try await ExportLog.wholeStore()
        try await log.setDisplayUnit(.pounds)
        let archive = try await log.backup.archive(takenAt: ExportLog.epoch)
        let settings = try #require(archive.settings)
        let stored = try await log.repositories.settings.settings()
        #expect(settings.displayUnit == .pounds)
        #expect(settings.userID == stored.userID)
    }

    @Test("The whole training-max history is carried, not the entry in force")
    func carriesSupersededTrainingMaxes() async throws {
        let log = try await ExportLog.wholeStore()
        let archive = try await log.backup.archive(takenAt: ExportLog.epoch)
        let percentages = archive.trainingMaxes.map(\.percentage).sorted()
        #expect(percentages == [0.9, 0.95])
    }

    @Test("A backup of a store nobody has trained in still carries the configuration")
    func aFreshStoreStillBacksUp() async throws {
        let log = ExportLog()
        try await log.gym(named: "home gym")
        let archive = try await log.backup.archive(takenAt: ExportLog.epoch)
        // The screen has no empty state because of exactly this: the log is empty and the file is
        // not, and the gym is work a clean install cannot rebuild.
        #expect(archive.isEmpty)
        #expect(archive.equipment.count == 1)
        #expect(archive.settings != nil)
    }

    @Test("One failed read fails the whole backup rather than writing a short file")
    func refusesAPartialRead() async throws {
        let log = try await ExportLog.wholeStore()
        let backup = FullBackup(
            exercises: log.repositories.exercises,
            workouts: log.repositories.workouts,
            bodyweight: log.repositories.bodyweight,
            equipment: FailingEquipmentReads(),
            routines: log.repositories.routines,
            settings: log.repositories.settings)
        await #expect(throws: RepositoryError.self) {
            _ = try await backup.archive(takenAt: ExportLog.epoch)
        }
    }

    @Test("The catalogue and its training-max history are asked for deleted rows too")
    func asksTheCatalogueForDeletedRows() async throws {
        // A double rather than the fakes, and the reason is a finding: `ExerciseRepository` offers
        // no delete for an exercise or for a training-max entry — `FR-1.1.5` archives instead — so
        // no fixture written through the real store can produce one of those rows soft-deleted.
        // Without this, `includingDeleted: true` on those two reads is a flag nothing can falsify.
        let log = ExportLog()
        let catalogue = FlaggedExerciseReads(stamp: ExportLog.epoch)
        let backup = FullBackup(
            exercises: catalogue,
            workouts: log.repositories.workouts,
            bodyweight: log.repositories.bodyweight,
            equipment: log.repositories.equipment,
            routines: log.repositories.routines,
            settings: log.repositories.settings)
        let archive = try await backup.archive(takenAt: ExportLog.epoch)
        #expect(archive.exercises.count == 2)
        #expect(archive.exercises.count { $0.deletedAt != nil } == 1)
        #expect(archive.trainingMaxes.count == 2)
        #expect(archive.trainingMaxes.count { $0.deletedAt != nil } == 1)
    }
}

/// An exercise repository holding one live row and one soft-deleted row in each of its two tables,
/// handing back the second only when a read asks for deleted rows.
///
/// It answers the flag rather than counting calls: a spy on the parameter would pass for a reader
/// that asked correctly and then dropped what came back.
private struct FlaggedExerciseReads: ExerciseRepository {
    /// The exercise that is still in the catalogue.
    let live: Exercise

    /// The one that is not.
    let removed: Exercise

    /// One standing training-max entry against ``live``, and one that was removed.
    let maxes: [TrainingMaxEntry]

    /// Builds the four rows, all stamped from one instant.
    ///
    /// **Stored rather than computed**, because the protocol's reads are `nonisolated` and this
    /// module's record helpers are not.
    ///
    /// **`@MainActor` because this module's record helpers are**, under the package's default
    /// isolation, while the protocol's own reads below are not — so the rows are assembled once,
    /// here, and only read from there.
    ///
    /// - Parameter stamp: When every row here was written.
    @MainActor
    init(stamp: Date) {
        live = ExportRecords.exercise(id: ExportRecords.id(0x01), name: "Squat", at: stamp)
        let gone = ExportRecords.exercise(id: ExportRecords.id(0x02), name: "Gone", at: stamp)
        removed = Exercise(
            id: gone.id,
            createdAt: gone.createdAt,
            updatedAt: gone.updatedAt,
            deletedAt: stamp,
            name: gone.name,
            ukrainianName: nil,
            movement: gone.movement,
            parentExerciseID: gone.parentExerciseID,
            equipment: gone.equipment,
            laterality: gone.laterality,
            barType: gone.barType,
            implementCount: gone.implementCount,
            isCustom: gone.isCustom,
            isArchived: gone.isArchived,
            notes: gone.notes,
            manualE1RM: gone.manualE1RM)
        maxes = [
            Self.trainingMax(for: live.id, at: stamp, byte: 0x03, deletedAt: nil),
            Self.trainingMax(for: live.id, at: stamp, byte: 0x04, deletedAt: stamp),
        ]
    }

    /// One training-max entry.
    ///
    /// - Parameters:
    ///   - exerciseID: What it configures.
    ///   - stamp: When it was written.
    ///   - byte: What varies its identifier.
    ///   - deletedAt: When it was removed, or `nil` where it stands.
    /// - Returns: The record.
    @MainActor
    private static func trainingMax(
        for exerciseID: UUID,
        at stamp: Date,
        byte: UInt8,
        deletedAt: Date?
    ) -> TrainingMaxEntry {
        TrainingMaxEntry(
            id: ExportRecords.id(byte),
            createdAt: stamp,
            updatedAt: stamp,
            deletedAt: deletedAt,
            exerciseID: exerciseID,
            source: .percentOfE1RM,
            sourceRepCount: nil,
            manualWeight: nil,
            percentage: 0.9,
            roundingIncrement: Weight(grams: 2_500),
            roundingStrategy: .down,
            progressionIncrement: nil,
            effectiveFrom: stamp)
    }

    func exercises(includingDeleted: Bool) async throws -> [Exercise] {
        includingDeleted ? [live, removed] : [live]
    }
    func exercise(id: UUID, includingDeleted: Bool) async throws -> Exercise? {
        try await exercises(includingDeleted: includingDeleted).first { $0.id == id }
    }
    func save(_ exercise: Exercise) async throws {}
    func trainingMax(
        forExerciseID exerciseID: UUID,
        on date: Date
    ) async throws -> TrainingMaxEntry? {
        nil
    }
    func trainingMaxHistory(
        forExerciseID exerciseID: UUID,
        includingDeleted: Bool
    ) async throws -> [TrainingMaxEntry] {
        guard exerciseID == live.id else { return [] }
        return includingDeleted ? maxes : maxes.filter { $0.deletedAt == nil }
    }
    func saveTrainingMax(_ entry: TrainingMaxEntry) async throws {}
}

/// An equipment repository whose reads throw — one table failing under a backup.
private struct FailingEquipmentReads: EquipmentRepository {
    func profiles(includingDeleted: Bool) async throws -> [EquipmentProfile] {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func profile(id: UUID, includingDeleted: Bool) async throws -> EquipmentProfile? {
        throw RepositoryError.recordNotFound(id: id)
    }
    func defaultProfile() async throws -> EquipmentProfile? {
        throw RepositoryError.recordNotFound(id: UUID())
    }
    func save(_ profile: EquipmentProfile) async throws {}
    func makeDefault(profileID: UUID) async throws {}
    func deleteProfile(id: UUID) async throws {}
}
