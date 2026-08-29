import Foundation
import PowerliftingCore
import RepositoryInterface

@testable import Settings

/// The rows a backup carries and the export does not, written through the real fakes.
///
/// An extension of ``ExportLog`` rather than a fixture of its own: `FR-1.11.3`'s file is
/// `FR-1.11.1`'s plus three tables, so a second store would make every test that compares the two
/// compare two different logs.
extension ExportLog {
    /// The backup over these fakes.
    var backup: FullBackup {
        FullBackup(
            exercises: repositories.exercises,
            workouts: repositories.workouts,
            bodyweight: repositories.bodyweight,
            equipment: repositories.equipment,
            settings: repositories.settings)
    }

    /// Writes one gym.
    ///
    /// - Parameters:
    ///   - name: What the lifter calls it.
    ///   - id: Its identifier.
    /// - Returns: The record.
    @discardableResult
    func gym(named name: String, id: UUID = UUID()) async throws -> EquipmentProfile {
        let profile = EquipmentProfile(
            id: id,
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            name: name,
            barWeight: Weight(grams: 20_000),
            collarWeight: Weight(grams: 2_500),
            plates: [Weight(grams: 25_000), Weight(grams: 20_000)],
            platePairCounts: [2, 2],
            isDefault: false)
        try await repositories.equipment.save(profile)
        return profile
    }

    /// Appends one training-max configuration to an exercise's history.
    ///
    /// - Parameters:
    ///   - exercise: What it configures.
    ///   - percentage: The fraction of the source weight, as a ratio.
    ///   - daysAgo: How many days before the epoch it takes effect.
    /// - Returns: The record.
    @discardableResult
    func trainingMax(
        for exercise: Exercise,
        percentage: Double = 0.9,
        daysAgo: Int = 0
    ) async throws -> TrainingMaxEntry {
        let date = Self.epoch.addingTimeInterval(-Double(daysAgo) * 86_400)
        let entry = TrainingMaxEntry(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            exerciseID: exercise.id,
            source: .percentOfE1RM,
            sourceRepCount: nil,
            manualWeight: nil,
            percentage: percentage,
            roundingIncrement: Weight(grams: 2_500),
            roundingStrategy: .down,
            progressionIncrement: Weight(grams: 2_500),
            effectiveFrom: date)
        try await repositories.exercises.saveTrainingMax(entry)
        return entry
    }

    /// A store with something in every table a backup reads, and one deleted row in three of them.
    ///
    /// **The deleted rows are made by the repositories' own delete calls, not by saving a record
    /// with a `deletedAt` on it.** Every save ignores that column (rule 7 of the mapping layer), so
    /// a fixture that set it by hand would produce a store with no soft-deleted rows in it and a
    /// suite that passed against a fiction.
    ///
    /// - Returns: The populated fixture.
    static func wholeStore() async throws -> ExportLog {
        let log = try await ExportLog.populated()
        let bench = try await log.exercise(named: "Bench Press")
        try await log.trainingMax(for: bench, percentage: 0.9, daysAgo: 30)
        try await log.trainingMax(for: bench, percentage: 0.95)
        try await log.gym(named: "home gym")
        try await log.bodyweight(grams: 82_000)

        let deletedGym = try await log.gym(named: "the meet")
        try await log.repositories.equipment.deleteProfile(id: deletedGym.id)
        let deletedReading = try await log.bodyweight(grams: 99_000, daysAgo: 2)
        try await log.repositories.bodyweight.deleteEntry(id: deletedReading.id)
        let strayed = try await log.session(daysAgo: 9, notes: "logged by mistake")
        try await log.repositories.workouts.deleteSession(id: strayed.id)

        // A live session holding a slot the lifter removed, which is the only shape that separates
        // "this session is deleted" from "a slot inside a live session is". Deleting the slot
        // cascades to its set, so this row is two deleted rows.
        let kept = try await log.session(daysAgo: 4)
        let removed = try await log.entry(bench, in: kept)
        _ = try await log.set(in: removed, order: 0, grams: 80_000, reps: 5)
        try await log.repositories.workouts.deleteExerciseEntry(id: removed.id)
        return log
    }
}
