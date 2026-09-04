import Foundation
import PowerliftingCore
import RepositoryInterface

@testable import Settings

/// The rows a backup carries and the export does not, written through the real fakes.
///
/// An extension of ``ExportLog`` rather than a fixture of its own: `FR-1.11.3`'s file is
/// `FR-1.11.1`'s plus seven tables, so a second store would make every test that compares the two
/// compare two different logs.
extension ExportLog {
    /// The backup over these fakes.
    var backup: FullBackup {
        FullBackup(
            exercises: repositories.exercises,
            trainingMaxes: repositories.trainingMaxes,
            workouts: repositories.workouts,
            bodyweight: repositories.bodyweight,
            equipment: repositories.equipment,
            routines: repositories.routines,
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
            percentage: percentage,
            roundingIncrement: Weight(grams: 2_500),
            roundingStrategy: .down,
            progressionIncrement: Weight(grams: 2_500),
            effectiveFrom: date)
        try await repositories.trainingMaxes.saveConfiguration(entry)
        return entry
    }

    /// Appends one change to an exercise's training max (`FR-15.1.4`, `FR-16.7.2`).
    ///
    /// **The old value and the reason both differ per call**, because two rows agreeing on either
    /// would pass for a restore that wrote one column into both — the trap `dashboardExerciseIDs`
    /// and `recentRecordsExerciseIDs` sprang on this suite once already.
    ///
    /// - Parameters:
    ///   - exercise: Whose training max changed.
    ///   - newGrams: What it becomes.
    ///   - oldGrams: What it was, or `nil` for the first entry.
    ///   - reason: Why.
    ///   - daysAgo: How many days before the epoch it takes effect.
    /// - Returns: The record.
    @discardableResult
    func trainingMaxChange(
        for exercise: Exercise,
        newGrams: Int,
        oldGrams: Int?,
        reason: String,
        daysAgo: Int = 0
    ) async throws -> TrainingMaxHistoryEntry {
        let date = Self.epoch.addingTimeInterval(-Double(daysAgo) * 86_400)
        let entry = TrainingMaxHistoryEntry(
            id: UUID(),
            createdAt: date,
            updatedAt: date,
            deletedAt: nil,
            exerciseID: exercise.id,
            effectiveFrom: date,
            oldWeight: oldGrams.map(Weight.init(grams:)),
            newWeight: Weight(grams: newGrams),
            reason: reason)
        try await repositories.trainingMaxes.save(entry)
        return entry
    }

    /// Writes one routine with one slot and two target groups (`FR-15.2.1`).
    ///
    /// **Two groups rather than one**, because a single group is the shape a walk that read only the
    /// first would still agree with.
    ///
    /// - Parameters:
    ///   - name: What the lifter calls it.
    ///   - exercise: What the one slot prescribes.
    /// - Returns: The routine, its slot and its groups.
    @discardableResult
    func routine(named name: String, for exercise: Exercise) async throws -> WrittenRoutine {
        let plan = Routine(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            name: name)
        try await repositories.routines.save(plan)

        let slot = RoutineExercise(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            routineID: plan.id,
            exerciseID: exercise.id,
            order: 0)
        try await repositories.routines.save(slot)

        // One fixed weight and one blank — `FR-15.2.2`'s two readings, which is also the only pair
        // that proves an optional column survives the file in both of its states.
        let groups = [
            RoutineTargetGroup(
                id: UUID(),
                createdAt: Self.epoch,
                updatedAt: Self.epoch,
                deletedAt: nil,
                routineExerciseID: slot.id,
                order: 0,
                targetWeight: Weight(grams: 100_000),
                targetReps: 5,
                targetSets: 3),
            RoutineTargetGroup(
                id: UUID(),
                createdAt: Self.epoch,
                updatedAt: Self.epoch,
                deletedAt: nil,
                routineExerciseID: slot.id,
                order: 1,
                targetWeight: nil,
                targetReps: 8,
                targetSets: 1),
        ]
        for group in groups { try await repositories.routines.save(group) }
        return WrittenRoutine(routine: plan, slot: slot, targetGroups: groups)
    }

    /// Writes what a routine prescribed for one logged slot (`FR-15.2.4`).
    ///
    /// - Parameters:
    ///   - entry: The slot it was planned for.
    ///   - grams: The target load, or `nil` for a blank one.
    ///   - order: Its position among that slot's groups.
    /// - Returns: The record.
    @discardableResult
    func plannedTarget(
        for entry: ExerciseEntry,
        grams: Int? = 102_500,
        order: Int = 0
    ) async throws -> PlannedTargetGroup {
        let group = PlannedTargetGroup(
            id: UUID(),
            createdAt: Self.epoch,
            updatedAt: Self.epoch,
            deletedAt: nil,
            exerciseEntryID: entry.id,
            order: order,
            targetWeight: grams.map(Weight.init(grams:)),
            targetReps: 5,
            targetSets: 3)
        try await repositories.workouts.save(group)
        return group
    }

    /// A store with something in every table a backup reads, and one deleted row in four of them.
    ///
    /// **The deleted rows are made by the repositories' own delete calls, not by saving a record
    /// with a `deletedAt` on it.** Every save ignores that column (rule 7 of the mapping layer), so
    /// a fixture that set it by hand would produce a store with no soft-deleted rows in it and a
    /// suite that passed against a fiction.
    ///
    /// - Parameter store: Which store to write into, defaulting to a fresh set of fakes.
    /// - Returns: The populated fixture.
    static func wholeStore(_ store: ExportLog = ExportLog()) async throws -> ExportLog {
        let log = try await ExportLog.populated(store)
        let bench = try await log.exercise(named: "Bench Press")
        try await log.trainingMax(for: bench, percentage: 0.9, daysAgo: 30)
        try await log.trainingMax(for: bench, percentage: 0.95)
        // FR-16.7.2's history, and the two rows differ in EVERY column rather than merely in the
        // new weight. `oldWeight` and `newWeight` are two weights on one row, so a fixture whose
        // second row repeats the first's old value is written, compared, agreed, and passes for a
        // restore that wrote one column into both. The first row names no old value at all, which
        // is the third distinct shape the column has.
        try await log.trainingMaxChange(
            for: bench, newGrams: 137_500, oldGrams: nil, reason: "starting point", daysAgo: 30)
        try await log.trainingMaxChange(
            for: bench, newGrams: 142_500, oldGrams: 137_500, reason: "coach, week 4")
        // FR-1.1.7's variations make `exercises` a self-referencing table, and `parentExerciseID`
        // is carried from the record like any other column — so a fixture whose exercises are all
        // roots leaves it nil on both sides of every field-for-field comparison and agrees with a
        // restore that dropped the link entirely. This says the column survives; it deliberately
        // says nothing about the ORDER the section is written in, which is
        // `aVariationListedAboveItsParentRestores`' subject and needs the child listed first.
        try await log.exercise(named: "Close-grip Bench Press", parentExerciseID: bench.id)
        // FR-1.10.3's flag is written by `makeDefault(profileID:)` and by nothing else — no save
        // carries it — so a fixture that only wrote profiles would leave `isDefault` false on both
        // sides of every comparison and agree with a restore that had dropped the column.
        let home = try await log.gym(named: "home gym")
        try await log.repositories.equipment.makeDefault(profileID: home.id)
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

        // FR-15.2: a routine the lifter trains from, and one they archived. Archiving is the
        // repository's soft delete cascading to the slot and its groups (`FR-15.2.5`), so the
        // second routine is what puts a deleted row in all three of those tables at once.
        try await log.routine(named: "Heavy day", for: bench)
        let archived = try await log.routine(named: "Last block", for: bench)
        try await log.repositories.routines.deleteRoutine(id: archived.routine.id)

        // FR-15.2.3/FR-15.2.4: a session started from a routine keeps what was prescribed beside
        // what was logged. On a LIVE slot, so the plan and the sets are readable together — the
        // deleted slot above already covers the other case.
        let planned = try await log.session(daysAgo: 1)
        let plannedEntry = try await log.entry(bench, in: planned)
        _ = try await log.set(in: plannedEntry, order: 0, grams: 100_000, reps: 5)
        try await log.plannedTarget(for: plannedEntry, grams: 102_500, order: 0)
        try await log.plannedTarget(for: plannedEntry, grams: nil, order: 1)
        return log
    }
}

/// The three rows one fixture routine is — a type rather than a tuple, which is the lint rule's
/// call and `FullBackup`'s own reason: three same-shaped values returned positionally are three a
/// caller can silently transpose.
struct WrittenRoutine {
    /// The routine itself.
    let routine: Routine

    /// Its one exercise slot.
    let slot: RoutineExercise

    /// That slot's target groups.
    let targetGroups: [RoutineTargetGroup]
}
