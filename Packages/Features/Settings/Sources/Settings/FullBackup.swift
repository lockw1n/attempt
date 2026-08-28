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

    /// Sessions, entries and sets.
    let workouts: any WorkoutRepository

    /// The bodyweight log.
    let bodyweight: any BodyweightRepository

    /// The gyms.
    let equipment: any EquipmentRepository

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
        return TrainingLogArchive(
            takenAt: takenAt,
            exercises: catalogue,
            sessions: workoutRows.sessions,
            entries: workoutRows.entries,
            sets: workoutRows.sets,
            bodyweight: try await bodyweight.entries(in: Self.allTime, includingDeleted: true),
            equipment: try await equipment.profiles(includingDeleted: true),
            trainingMaxes: try await trainingMaxes(for: catalogue),
            settings: try await settings.settings())
    }

    /// The three joined tables, walked in one pass.
    ///
    /// - Returns: Every session, every slot in them and every set in those.
    /// - Throws: Whatever the workout repository throws.
    private func workoutRows() async throws -> WorkoutRows {
        let sessions = try await workouts.sessions(in: Self.allTime, includingDeleted: true)
        var entries: [ExerciseEntry] = []
        var sets: [SetEntry] = []
        for session in sessions {
            let slots = try await workouts.entries(forSessionID: session.id, includingDeleted: true)
            entries.append(contentsOf: slots)
            for slot in slots {
                sets.append(
                    contentsOf: try await workouts.sets(forEntryID: slot.id, includingDeleted: true))
            }
        }
        return WorkoutRows(sessions: sessions, entries: entries, sets: sets)
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

/// The three joined workout tables, read together.
///
/// A type rather than a tuple, which is the lint rule's call and the better one anyway: three
/// same-shaped arrays returned positionally are three that a caller can silently transpose.
private struct WorkoutRows {
    /// Every workout, soft-deleted ones included.
    let sessions: [WorkoutSession]

    /// Every exercise slot in them.
    let entries: [ExerciseEntry]

    /// Every set in those slots.
    let sets: [SetEntry]
}
