import Foundation
import SwiftData

/// One pass over the store: which ids the scope frees, and what removing them costs.
///
/// **Every row of every table is loaded, and that is the cheap half of a purge.** The scan has to
/// see live rows as well as eligible ones — a live row is what holds an eligible one back — so
/// there is no narrower fetch that answers the question.
///
/// **Ids, not rows, because two rows may share one** (`G-2.5`, rule 2 of `RowResolution.swift`).
/// An id is freed only when *every* row carrying it is eligible: a duplicate pair with one live
/// half still resolves for anything that names it, so removing the eligible half would be correct
/// and removing both would not.
struct PurgePlan {
    private let exercises: [ExerciseEntity]
    private let sessions: [WorkoutSessionEntity]
    private let entries: [ExerciseEntryEntity]
    private let sets: [SetEntryEntity]
    private let trainingMaxes: [TrainingMaxConfigEntity]
    private let trainingMaxHistory: [TrainingMaxHistoryEntity]
    private let bodyweight: [BodyweightEntryEntity]
    private let equipment: [EquipmentProfileEntity]
    private let settings: [UserSettingsEntity]
    private let records: [PersonalRecordCacheEntity]
    private let routines: [RoutineEntity]
    private let routineExercises: [RoutineExerciseEntity]
    private let targetGroups: [RoutineTargetGroupEntity]
    private let plannedTargets: [PlannedTargetGroupEntity]

    private let scope: PurgeScope

    /// Ids freed per table, after the retention scan.
    private var freedExercises: Set<UUID> = []
    private var freedSessions: Set<UUID> = []
    private var freedEntries: Set<UUID> = []
    private var freedSets: Set<UUID> = []
    private var freedTrainingMaxes: Set<UUID> = []
    private var freedTrainingMaxHistory: Set<UUID> = []
    private var freedBodyweight: Set<UUID> = []
    private var freedEquipment: Set<UUID> = []
    private var freedSettings: Set<UUID> = []
    private var freedRecords: Set<UUID> = []
    private var freedRoutines: Set<UUID> = []
    private var freedRoutineExercises: Set<UUID> = []
    private var freedTargetGroups: Set<UUID> = []
    private var freedPlannedTargets: Set<UUID> = []

    /// Reads the whole store and resolves the plan.
    ///
    /// - Parameters:
    ///   - context: The store.
    ///   - scope: Which rows are eligible.
    /// - Throws: Whatever a fetch throws.
    init(context: ModelContext, scope: PurgeScope) throws {
        self.scope = scope
        exercises = try context.rows(ExerciseEntity.self, includingDeleted: true)
        sessions = try context.rows(WorkoutSessionEntity.self, includingDeleted: true)
        entries = try context.rows(ExerciseEntryEntity.self, includingDeleted: true)
        sets = try context.rows(SetEntryEntity.self, includingDeleted: true)
        trainingMaxes = try context.rows(TrainingMaxConfigEntity.self, includingDeleted: true)
        trainingMaxHistory = try context.rows(
            TrainingMaxHistoryEntity.self, includingDeleted: true)
        bodyweight = try context.rows(BodyweightEntryEntity.self, includingDeleted: true)
        equipment = try context.rows(EquipmentProfileEntity.self, includingDeleted: true)
        settings = try context.rows(UserSettingsEntity.self, includingDeleted: true)
        records = try context.rows(PersonalRecordCacheEntity.self, includingDeleted: true)
        routines = try context.rows(RoutineEntity.self, includingDeleted: true)
        routineExercises = try context.rows(RoutineExerciseEntity.self, includingDeleted: true)
        targetGroups = try context.rows(RoutineTargetGroupEntity.self, includingDeleted: true)
        plannedTargets = try context.rows(PlannedTargetGroupEntity.self, includingDeleted: true)

        freedExercises = eligibleIDs(in: exercises)
        freedSessions = eligibleIDs(in: sessions)
        freedEntries = eligibleIDs(in: entries)
        freedSets = eligibleIDs(in: sets)
        freedTrainingMaxes = eligibleIDs(in: trainingMaxes)
        freedTrainingMaxHistory = eligibleIDs(in: trainingMaxHistory)
        freedBodyweight = eligibleIDs(in: bodyweight)
        freedEquipment = eligibleIDs(in: equipment)
        freedSettings = eligibleIDs(in: settings)
        freedRecords = eligibleIDs(in: records)
        freedRoutines = eligibleIDs(in: routines)
        freedRoutineExercises = eligibleIDs(in: routineExercises)
        freedTargetGroups = eligibleIDs(in: targetGroups)
        freedPlannedTargets = eligibleIDs(in: plannedTargets)

        retainReferenced()
    }

    /// Ids the scope covers on every row that carries them.
    private func eligibleIDs(in rows: [some StoredEntity]) -> Set<UUID> {
        var eligible: Set<UUID> = []
        var spared: Set<UUID> = []
        for row in rows {
            if scope.covers(row) { eligible.insert(row.id) } else { spared.insert(row.id) }
        }
        return eligible.subtracting(spared)
    }

    /// Puts back every id a surviving row still names, until nothing more is put back.
    ///
    /// **It iterates because retention is transitive.** Keeping a set keeps its entry, and keeping
    /// that entry keeps its session; keeping a target group keeps its slot, and that slot keeps
    /// both its routine and the exercise it prescribes — two three-level chains, a self-edge on the
    /// catalogue and a cross-chain edge into it, so a single pass in the wrong order would free a
    /// parent whose child had just been kept. The fixpoint costs one extra sweep over rows already
    /// in memory and needs no ordering argument.
    private mutating func retainReferenced() {
        var changed = true
        while changed {
            changed = false
            for entry in entries where !freedEntries.contains(entry.id) {
                changed = retain(entry.sessionID, in: &freedSessions) || changed
                changed = retain(entry.exerciseID, in: &freedExercises) || changed
            }
            for set in sets where !freedSets.contains(set.id) {
                changed = retain(set.entryID, in: &freedEntries) || changed
            }
            for config in trainingMaxes where !freedTrainingMaxes.contains(config.id) {
                changed = retain(config.exerciseID, in: &freedExercises) || changed
            }
            // The history hangs off the same edge as the configuration and is kept separately from
            // it: a lifter may have entered numbers for an exercise they never configured a source
            // for, which is every exercise in this phase (`FR-16.7.2`).
            for entry in trainingMaxHistory where !freedTrainingMaxHistory.contains(entry.id) {
                changed = retain(entry.exerciseID, in: &freedExercises) || changed
            }
            // TWO LISTS ON THIS ROW, not one: `FR-16.3.1`'s chosen feed scope names exercises the
            // dashboard selection need not, so a purge reading only the tiles would free an
            // exercise the recent-PR feed still filters on.
            for row in settings where !freedSettings.contains(row.id) {
                for id in (row.dashboardExerciseIDs ?? []) + (row.recentRecordsExerciseIDs ?? []) {
                    changed = retain(id, in: &freedExercises) || changed
                }
            }
            for exercise in exercises where !freedExercises.contains(exercise.id) {
                guard let parent = exercise.parentExerciseID else { continue }
                changed = retain(parent, in: &freedExercises) || changed
            }
            // A surviving routine slot holds its routine AND the exercise it prescribes. The
            // second edge is the one with teeth: without it a purge frees an exercise a live
            // routine still names, and `G-2.5` declares no relationship that would notice.
            for slot in routineExercises where !freedRoutineExercises.contains(slot.id) {
                changed = retain(slot.routineID, in: &freedRoutines) || changed
                changed = retain(slot.exerciseID, in: &freedExercises) || changed
            }
            for group in targetGroups where !freedTargetGroups.contains(group.id) {
                changed = retain(group.routineExerciseID, in: &freedRoutineExercises) || changed
            }
            // A surviving planned target holds the entry it was planned for, exactly as a
            // surviving set does — the snapshot is the session's own row and outlives the routine
            // it was copied from (`TR-15.3`).
            for group in plannedTargets where !freedPlannedTargets.contains(group.id) {
                changed = retain(group.exerciseEntryID, in: &freedEntries) || changed
            }
        }
    }

    /// Takes `id` back out of `freed`, reporting whether it was there.
    private func retain(_ id: UUID, in freed: inout Set<UUID>) -> Bool {
        freed.remove(id) != nil
    }

    /// How many eligible rows the scan held back.
    var retainedCount: Int {
        held(in: exercises, freed: freedExercises) + held(in: sessions, freed: freedSessions)
            + held(in: entries, freed: freedEntries) + held(in: sets, freed: freedSets)
            + held(in: trainingMaxes, freed: freedTrainingMaxes)
            + held(in: trainingMaxHistory, freed: freedTrainingMaxHistory)
            + held(in: bodyweight, freed: freedBodyweight)
            + held(in: equipment, freed: freedEquipment)
            + held(in: settings, freed: freedSettings)
            + held(in: routines, freed: freedRoutines)
            + held(in: routineExercises, freed: freedRoutineExercises)
            + held(in: targetGroups, freed: freedTargetGroups)
            + held(in: plannedTargets, freed: freedPlannedTargets)
            + records.filter { scope.covers($0) && !isDoomed($0) }.count
    }

    private func held(in rows: [some StoredEntity], freed: Set<UUID>) -> Int {
        rows.filter { scope.covers($0) && !freed.contains($0.id) }.count
    }

    /// Whether a cache row goes: its own id is freed, or the exercise or set it was computed from
    /// is. The second half is why it is asked here rather than read off ``freedRecords``.
    private func isDoomed(_ record: PersonalRecordCacheEntity) -> Bool {
        freedRecords.contains(record.id) || freedExercises.contains(record.exerciseID)
            || freedSets.contains(record.sourceSetID)
    }

    /// Every row this plan removes, in no particular order — the store checks no constraint, so
    /// there is no referential order to keep on the way out.
    ///
    /// The cache is the one table whose rows are chosen by what they *name* rather than by their
    /// own id: a record sourced from a freed set or exercise goes with it, live or not (`G-1.4`).
    var doomedRows: [any PersistentModel] {
        var doomed: [any PersistentModel] = []
        doomed.append(contentsOf: exercises.filter { freedExercises.contains($0.id) })
        doomed.append(contentsOf: sessions.filter { freedSessions.contains($0.id) })
        doomed.append(contentsOf: entries.filter { freedEntries.contains($0.id) })
        doomed.append(contentsOf: sets.filter { freedSets.contains($0.id) })
        doomed.append(contentsOf: trainingMaxes.filter { freedTrainingMaxes.contains($0.id) })
        doomed.append(
            contentsOf: trainingMaxHistory.filter { freedTrainingMaxHistory.contains($0.id) })
        doomed.append(contentsOf: bodyweight.filter { freedBodyweight.contains($0.id) })
        doomed.append(contentsOf: equipment.filter { freedEquipment.contains($0.id) })
        doomed.append(contentsOf: settings.filter { freedSettings.contains($0.id) })
        doomed.append(contentsOf: routines.filter { freedRoutines.contains($0.id) })
        doomed.append(
            contentsOf: routineExercises.filter { freedRoutineExercises.contains($0.id) })
        doomed.append(contentsOf: targetGroups.filter { freedTargetGroups.contains($0.id) })
        doomed.append(contentsOf: plannedTargets.filter { freedPlannedTargets.contains($0.id) })
        doomed.append(contentsOf: records.filter(isDoomed))
        return doomed
    }
}
