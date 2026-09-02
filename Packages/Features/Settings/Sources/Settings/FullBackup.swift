import Foundation
import RepositoryInterface

/// Reads the whole store into one archive — `FR-1.11.3`'s backup half.
///
/// **Not ``TrainingLogExport`` with a flag.** The two differ in more than a parameter: this one asks
/// every read for soft-deleted rows as well (`G-1.3`), adds three tables the log does not need, and
/// answers a different question — an export is what the lifter *has*, a backup is what the store
/// *holds*. A shared reader with a boolean would put both readings behind one call and make the
/// export's "live rows only" promise a caller's to keep rather than the type's.
///
/// **It reads through the repository protocols one at a time**, like every other screen here
/// (`TR-0.1.2`). The store is local and synchronous (`G-2.2`), so the cost of walking it is the cost
/// of the file.
struct FullBackup {
    /// The catalogue, and each exercise's training-max history.
    let exercises: any ExerciseRepository

    /// Sessions, entries, sets — and what a routine planned for those slots (`FR-15.2.4`).
    ///
    /// **One property answering two protocols**, which is `PersistenceStack`'s reason said on this
    /// side of the boundary: a planned target hangs off an exercise entry, so a backup that read the
    /// entries from one store and the targets from another would write a file whose two halves
    /// disagree about which session it is describing.
    let workouts: any WorkoutRepository & PlannedTargetRepository

    /// The bodyweight log.
    let bodyweight: any BodyweightRepository

    /// The gyms.
    let equipment: any EquipmentRepository

    /// The routines, their slots and their target groups (`FR-15.2`).
    let routines: any RoutineRepository

    /// The preferences row.
    let settings: any SettingsRepository

    /// Every date a repository read can be asked for: a backup is the whole store, not a window.
    private static let allTime = Date.distantPast...Date.distantFuture

    /// Gathers the store into one archive.
    ///
    /// **Every read asks for soft-deleted rows**, which is the whole difference from the export and
    /// the reason `FR-1.11.3` needs its own reader: a row the lifter deleted is still a row a clean
    /// install has to be restorable to, and `deletedAt` is what says which. The rows come back
    /// whole; nothing here interprets one.
    ///
    /// **The cached personal records (`TR-0.3.9`) are deliberately not in the file.** They are
    /// derived and never truth (`G-1.4`), recomputed from the sets that are here, and the only
    /// writer the cache has takes computed values rather than rows — so a restore could not put them
    /// back faithfully even if they were carried. A backup holding both the sets and a cache over
    /// them would be a file able to contradict itself. Leaving the section out stays reversible:
    /// adding one later is an added key, rule 3 of `RecordCoding.swift`.
    ///
    /// - Parameter takenAt: When the file is being written.
    /// - Returns: The archive.
    /// - Throws: Whatever the repositories throw. One failed read fails the whole backup, because a
    ///   file missing the rows a read could not answer is worse than no file — and worse here than
    ///   for an export, since this one is what a restore trusts.
    func archive(takenAt: Date = .now) async throws -> TrainingLogArchive {
        let catalogue = try await exercises.exercises(includingDeleted: true)
        let workoutRows = try await self.workoutRows()
        let routineRows = try await self.routineRows()
        return TrainingLogArchive(
            takenAt: takenAt,
            exercises: catalogue,
            sessions: workoutRows.sessions,
            entries: workoutRows.entries,
            sets: workoutRows.sets,
            bodyweight: try await bodyweight.entries(in: Self.allTime, includingDeleted: true),
            equipment: try await equipment.profiles(includingDeleted: true),
            trainingMaxes: try await trainingMaxes(for: catalogue),
            routines: routineRows.routines,
            routineExercises: routineRows.exercises,
            routineTargetGroups: routineRows.targetGroups,
            plannedTargets: workoutRows.plannedTargets,
            settings: try await settings.settings())
    }

    /// The four joined tables, walked in one pass.
    ///
    /// **The planned targets are read here rather than in a walk of their own**, because the only
    /// read there is takes an exercise entry and this is the loop that already has one. A second
    /// pass would enumerate the same slots to ask them a second question.
    ///
    /// - Returns: Every session, every slot in them, every set in those, and every target a routine
    ///   planned for one of those slots.
    /// - Throws: Whatever the workout repository throws.
    private func workoutRows() async throws -> WorkoutRows {
        let sessions = try await workouts.sessions(in: Self.allTime, includingDeleted: true)
        var entries: [ExerciseEntry] = []
        var sets: [SetEntry] = []
        var planned: [PlannedTargetGroup] = []
        for session in sessions {
            let slots = try await workouts.entries(forSessionID: session.id, includingDeleted: true)
            entries.append(contentsOf: slots)
            for slot in slots {
                sets.append(
                    contentsOf: try await workouts.sets(forEntryID: slot.id, includingDeleted: true))
                planned.append(
                    contentsOf: try await workouts.plannedTargets(
                        forEntryID: slot.id, includingDeleted: true))
            }
        }
        return WorkoutRows(
            sessions: sessions, entries: entries, sets: sets, plannedTargets: planned)
    }

    /// The routines and the two tables under them, walked the way the sessions are.
    ///
    /// **Walked per parent for the sessions' reason** — the protocol offers a routine's slots and a
    /// slot's target groups and no global fetch of either, so the routine list is the enumeration
    /// and a slot list is the next one. Soft-deleted rows at every level, since a routine the lifter
    /// archived (`FR-15.2.5`) is a soft delete and a backup that dropped it would hand back a
    /// library missing everything ever archived from it.
    ///
    /// - Returns: Every routine, every slot in them and every target group in those.
    /// - Throws: Whatever the routine repository throws.
    private func routineRows() async throws -> RoutineRows {
        let plans = try await routines.routines(includingDeleted: true)
        var slots: [RoutineExercise] = []
        var groups: [RoutineTargetGroup] = []
        for plan in plans {
            let planned = try await routines.exercises(forRoutineID: plan.id, includingDeleted: true)
            slots.append(contentsOf: planned)
            for slot in planned {
                groups.append(
                    contentsOf: try await routines.targetGroups(
                        forRoutineExerciseID: slot.id, includingDeleted: true))
            }
        }
        return RoutineRows(routines: plans, exercises: slots, targetGroups: groups)
    }

    /// Every training-max entry in the store (`TR-0.3.6`).
    ///
    /// **Walked per exercise, because that is the only read there is.** The protocol offers a
    /// history for one exercise and no global fetch, so the catalogue — soft-deleted exercises
    /// included, since their configurations are rows too — is the enumeration. It is one call per
    /// exercise against a local store, which is the shape the sets walk above already has.
    ///
    /// - Parameter catalogue: Every exercise, deleted ones included.
    /// - Returns: Every entry, grouped by exercise in catalogue order.
    /// - Throws: Whatever the exercise repository throws.
    private func trainingMaxes(for catalogue: [Exercise]) async throws -> [TrainingMaxEntry] {
        var entries: [TrainingMaxEntry] = []
        for exercise in catalogue {
            entries.append(
                contentsOf: try await exercises.trainingMaxHistory(
                    forExerciseID: exercise.id, includingDeleted: true))
        }
        return entries
    }
}

/// The four joined workout tables, read together.
///
/// A type rather than a tuple, which is the lint rule's call and the better one anyway: four
/// same-shaped arrays returned positionally are four that a caller can silently transpose.
private struct WorkoutRows {
    /// Every workout, soft-deleted ones included.
    let sessions: [WorkoutSession]

    /// Every exercise slot in them.
    let entries: [ExerciseEntry]

    /// Every set in those slots.
    let sets: [SetEntry]

    /// Every target a routine planned for one of those slots.
    let plannedTargets: [PlannedTargetGroup]
}

/// The three joined routine tables, read together — ``WorkoutRows``' shape and its reason.
private struct RoutineRows {
    /// Every routine, soft-deleted ones included.
    let routines: [Routine]

    /// Every exercise slot in them.
    let exercises: [RoutineExercise]

    /// Every target group in those slots.
    let targetGroups: [RoutineTargetGroup]
}
