import Foundation
import RepositoryInterface

/// The store as one structured value — `FR-1.11.1`'s JSON export, and `FR-1.11.3`'s backup, in one
/// envelope.
///
/// **Flat arrays of `RepositoryInterface`'s records, not a nested tree.** The records already carry
/// their own foreign keys (a set names its entry, an entry names its session and its exercise), so
/// nesting would either duplicate those keys or drop them, and a reader that dropped them could not
/// rebuild the rows. `TR-0.4.4`'s DTO layer is the wire format; this type is an envelope over it and
/// restates none of its rules.
///
/// **One envelope for two files, and ``contents`` is what tells them apart.** An export carries the
/// log and live rows only (`G-1.3`); a backup carries every table and every row, soft-deleted ones
/// included. Those differ in what is *absent*, and an absence cannot be read: an all-`nil`
/// ``RepositoryInterface/StoredRecord/deletedAt`` means "nothing was deleted" in a backup and "deleted rows were left
/// out" in an export, and no row-level inspection separates the two. The discriminator is therefore
/// not a label — it is the only thing that makes the file's silence interpretable, and `FR-1.11.4`'s
/// restore reads it before it reads anything else.
///
/// **The sections a backup adds are additive keys, not a second format**: an absent section is an
/// omitted key, rule 3 of `RecordCoding.swift`, so a file written by the export reads under the
/// backup's reader and a file written before ``contents`` existed reads as the export it was.
///
/// **The `Codable` conformance is `nonisolated`, and the annotations under it are load-bearing.**
/// This module is compiled `defaultIsolation(MainActor)`, which would otherwise isolate the
/// conformance and confine every encode and decode of a whole store to the main thread — where
/// `FR-1.11.4`'s restore has to read a chosen file *off* it. Nothing here is shared mutable state,
/// so the looser isolation is the accurate one rather than a concession.
struct TrainingLogArchive: nonisolated Codable, Sendable, Equatable {
    /// Which of the two files this is — see this type's note on why the distinction cannot be
    /// inferred from the rows.
    ///
    /// **A closed vocabulary that throws on a spelling this build does not know**, which is the
    /// opposite of a record's vocabulary column (rule 4 of `RecordCoding.swift`, resolve and never
    /// fail) and deliberately so. A vocabulary column's fallback costs that column; this one's would
    /// cost every row the file does not contain, silently, in whichever direction the fallback was
    /// picked. There is no safe default, so there is no default.
    enum Contents: String, Sendable, nonisolated Codable {
        /// `FR-1.11.1`'s export: the log, live rows only, no configuration.
        case trainingLog

        /// `FR-1.11.3`'s backup: every table, every row, `deletedAt` intact.
        case fullBackup
    }

    /// Which reading of this envelope wrote the file.
    ///
    /// **It is not `TR-2.4`'s schema version and does not track it.** It says what fields to expect
    /// here; the rows inside are versioned by the store they came from.
    let formatVersion: Int

    /// Which file this is.
    let contents: Contents

    /// When the file was written. Metadata — nothing reads it back into a row.
    let exportedAt: Date

    /// The catalogue, including the seeded exercises the sets point at.
    ///
    /// **Every exercise, not only the trained ones.** A custom exercise with no sets logged against
    /// it yet is still the lifter's own work (`FR-1.1.3`), and an export that dropped it would be
    /// lossy in the direction a restore notices.
    let exercises: [Exercise]

    /// Every workout logged.
    let sessions: [WorkoutSession]

    /// Every exercise slot within those workouts.
    let entries: [ExerciseEntry]

    /// Every set logged in those slots — the rows `FR-1.11.1`'s CSV gives one line each.
    let sets: [SetEntry]

    /// Every bodyweight reading (`FR-1.8.1`).
    ///
    /// **In the log rather than in the configuration**, because it is measured rather than chosen:
    /// a reading is a dated observation the lifter recorded, which is what the rest of this envelope
    /// holds.
    let bodyweight: [BodyweightEntry]

    /// Every gym the lifter has set up (`TR-0.3.7`, `FR-1.4.2`). Empty in an export.
    let equipment: [EquipmentProfile]

    /// Every training-max configuration, across every exercise (`TR-0.3.6`, `FR-15.1.1`). Empty in
    /// an export.
    ///
    /// **How the number is derived, not the number** — that is ``trainingMaxHistory``. Both sections
    /// are carried because a backup restoring one without the other would give a clean install a
    /// training max with no source, or a source with nothing to apply it to.
    let trainingMaxes: [TrainingMaxEntry]

    /// Every change to every exercise's training max (`TR-16.3`, `FR-15.1.4`, `FR-16.7.2`). Empty in
    /// an export.
    ///
    /// **The history rather than what is in force**, because in force is a lookup over this and the
    /// entries it supersedes are what `FR-15.1.4` displays. Nothing recomputes a training max, so a
    /// backup that skipped this section would hand a clean install a log it cannot read a single
    /// percentage against (`FR-16.7.1`).
    let trainingMaxHistory: [TrainingMaxHistoryEntry]

    /// Every routine the lifter has built (`FR-15.2.1`). Empty in an export.
    ///
    /// **Backup-only, on the argument the gyms and the training maxes already make**: a routine is
    /// what the lifter trains *from* rather than what they logged, so `FR-1.11.1`'s export leaves it
    /// out and `FR-1.11.3`'s backup cannot — a file carrying every workout and none of the plans
    /// behind them is not a store a clean install can be restored to.
    let routines: [Routine]

    /// Every exercise slot in those routines, across all of them. Empty in an export.
    let routineExercises: [RoutineExercise]

    /// Every target group in those slots — `FR-15.2.1`'s several weights per exercise, and
    /// `FR-15.2.2`'s blank ones. Empty in an export.
    let routineTargetGroups: [RoutineTargetGroup]

    /// Every program the lifter has built (`TR-16.2`, `FR-16.8.1`). Empty in an export.
    ///
    /// **Backup-only, on the argument the routines already make**: a program is what the lifter
    /// trains *from* rather than what they logged.
    let programs: [Program]

    /// Every day in those programs, across all of them. Empty in an export.
    let programDays: [ProgramDay]

    /// Every pass through a program (`FR-16.8.3`). Empty in an export.
    ///
    /// **Carried although a run holds no training of its own**, because the sessions do name it:
    /// `WorkoutSession.programRunID` is a foreign key into this section, and a backup that dropped
    /// it would restore a log whose week and day numbers point at nothing.
    let programRuns: [ProgramRun]

    /// What a routine prescribed for a logged session's slots (`FR-15.2.4`). Empty in an export.
    ///
    /// **Carried although it hangs off a session that is already here**, because it is the half of
    /// `FR-15.3.3`'s planned-versus-actual that the sets do not hold: a restored session without it
    /// keeps every rep logged and loses the yardstick they were judged against, and nothing can
    /// recompute a plan from the performance it was measuring.
    let plannedTargets: [PlannedTargetGroup]

    /// The preferences row (`TR-0.3.8`), or `nil` in an export.
    ///
    /// **One row and therefore not an array**, which is `TR-1.10`'s find-or-create shape said in the
    /// wire format: a file carrying two would be a file with two answers for the display unit.
    let settings: UserSettings?

    /// The wire keys, declared rather than synthesised — rule 1 of `RecordCoding.swift`, which this
    /// envelope follows for the reason the records do: renaming a property must not be a rename.
    nonisolated enum CodingKeys: String, CodingKey {
        case formatVersion
        case contents
        case exportedAt
        case exercises
        case sessions
        case entries
        case sets
        case bodyweight
        case equipment
        case trainingMaxes
        case trainingMaxHistory
        case routines
        case routineExercises
        case routineTargetGroups
        case programs
        case programDays
        case programRuns
        case plannedTargets
        case settings
    }

    /// The reading this build writes.
    ///
    /// **The number moves when a reader that ignored the new keys would be wrong about the store,
    /// and stays when it would merely be incomplete about a row.** 2 was the ``contents``
    /// discriminator: a reader without it reads a backup as an export and concludes nothing in it
    /// had ever been deleted. 3 is `FR-15.2`'s routines and the targets a routine planned for a
    /// logged slot — additive keys, which is exactly why the number had to move, since a reader
    /// without them drops every plan behind the lifter's log and reports a successful restore.
    /// 4 is ``trainingMaxHistory``, on the same argument: a new table, holding the one number
    /// `FR-16.7.1`'s percentages are read against, which nothing recomputes.
    /// 5 is `FR-16.8`'s programs, their days and their runs — three new tables, and the runs are
    /// what the log's own `programRunID` points at, so a reader without them restores every session
    /// and loses which pass through which program it belonged to.
    /// `FR-1.11.4`'s refusal is what makes that visible, and it fires only on a number this build
    /// does not claim. A record gaining a column moves nothing (rule 7 of `RecordCoding.swift`).
    nonisolated static let currentFormatVersion = 5

    /// Builds a training-log export at the current format version.
    ///
    /// - Parameters:
    ///   - exportedAt: When the file is being written.
    ///   - exercises: The catalogue.
    ///   - sessions: Every workout.
    ///   - entries: Every exercise slot.
    ///   - sets: Every set.
    ///   - bodyweight: Every reading.
    nonisolated init(
        exportedAt: Date,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        entries: [ExerciseEntry],
        sets: [SetEntry],
        bodyweight: [BodyweightEntry]
    ) {
        self.init(
            contents: .trainingLog,
            exportedAt: exportedAt,
            exercises: exercises,
            sessions: sessions,
            entries: entries,
            sets: sets,
            bodyweight: bodyweight,
            equipment: [],
            trainingMaxes: [],
            trainingMaxHistory: [],
            routines: [],
            routineExercises: [],
            routineTargetGroups: [],
            programs: [],
            programDays: [],
            programRuns: [],
            plannedTargets: [],
            settings: nil)
    }

    /// Builds a full backup at the current format version.
    ///
    /// **The settings row is not optional here**, unlike the property: `TR-1.10` mints one on first
    /// read, so a backup taken from a store that opened always has one, and a caller that could pass
    /// `nil` would be a caller writing a backup that restores no preferences at all.
    ///
    /// - Parameters:
    ///   - takenAt: When the file is being written.
    ///   - exercises: The catalogue, soft-deleted rows included.
    ///   - sessions: Every workout, soft-deleted rows included.
    ///   - entries: Every exercise slot, soft-deleted rows included.
    ///   - sets: Every set, soft-deleted rows included.
    ///   - bodyweight: Every reading, soft-deleted rows included.
    ///   - equipment: Every gym, soft-deleted rows included.
    ///   - trainingMaxes: Every training-max configuration, soft-deleted rows included.
    ///   - trainingMaxHistory: Every change to a training max, soft-deleted rows included.
    ///   - routines: Every routine, soft-deleted rows included.
    ///   - routineExercises: Every slot in them, soft-deleted rows included.
    ///   - routineTargetGroups: Every target group in those slots, soft-deleted rows included.
    ///   - programs: Every program, soft-deleted rows included.
    ///   - programDays: Every day in them, soft-deleted rows included.
    ///   - programRuns: Every pass through one, soft-deleted rows included.
    ///   - plannedTargets: Every target a routine planned for a logged slot, soft-deleted rows
    ///     included.
    ///   - settings: The preferences row.
    nonisolated init(
        takenAt: Date,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        entries: [ExerciseEntry],
        sets: [SetEntry],
        bodyweight: [BodyweightEntry],
        equipment: [EquipmentProfile],
        trainingMaxes: [TrainingMaxEntry],
        trainingMaxHistory: [TrainingMaxHistoryEntry],
        routines: [Routine],
        routineExercises: [RoutineExercise],
        routineTargetGroups: [RoutineTargetGroup],
        programs: [Program],
        programDays: [ProgramDay],
        programRuns: [ProgramRun],
        plannedTargets: [PlannedTargetGroup],
        settings: UserSettings
    ) {
        self.init(
            contents: .fullBackup,
            exportedAt: takenAt,
            exercises: exercises,
            sessions: sessions,
            entries: entries,
            sets: sets,
            bodyweight: bodyweight,
            equipment: equipment,
            trainingMaxes: trainingMaxes,
            trainingMaxHistory: trainingMaxHistory,
            routines: routines,
            routineExercises: routineExercises,
            routineTargetGroups: routineTargetGroups,
            programs: programs,
            programDays: programDays,
            programRuns: programRuns,
            plannedTargets: plannedTargets,
            settings: settings)
    }

    /// The one initialiser the two above go through, and the only place ``formatVersion`` is set.
    ///
    /// **Internal rather than private, and it takes a version, because the decoder is in another
    /// file.** An initialiser declared in an extension may not assign a `let` stored property, so
    /// `init(from:)` reaches the envelope through here — and it is the one caller that passes a
    /// version, since what a file says it was written under is the file's rather than this build's.
    /// Every other caller takes the default and gets ``currentFormatVersion``.
    nonisolated init(
        formatVersion: Int = Self.currentFormatVersion,
        contents: Contents,
        exportedAt: Date,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        entries: [ExerciseEntry],
        sets: [SetEntry],
        bodyweight: [BodyweightEntry],
        equipment: [EquipmentProfile],
        trainingMaxes: [TrainingMaxEntry],
        trainingMaxHistory: [TrainingMaxHistoryEntry],
        routines: [Routine],
        routineExercises: [RoutineExercise],
        routineTargetGroups: [RoutineTargetGroup],
        programs: [Program],
        programDays: [ProgramDay],
        programRuns: [ProgramRun],
        plannedTargets: [PlannedTargetGroup],
        settings: UserSettings?
    ) {
        self.formatVersion = formatVersion
        self.contents = contents
        self.exportedAt = exportedAt
        self.exercises = exercises
        self.sessions = sessions
        self.entries = entries
        self.sets = sets
        self.bodyweight = bodyweight
        self.equipment = equipment
        self.trainingMaxes = trainingMaxes
        self.trainingMaxHistory = trainingMaxHistory
        self.routines = routines
        self.routineExercises = routineExercises
        self.routineTargetGroups = routineTargetGroups
        self.programs = programs
        self.programDays = programDays
        self.programRuns = programRuns
        self.plannedTargets = plannedTargets
        self.settings = settings
    }

    /// Whether there is a training log here at all.
    ///
    /// **The sessions and the readings decide it, never the exercises.** The catalogue is seeded at
    /// first launch, so an export of a store nobody has trained in is not empty by row count — it is
    /// a hundred exercises and nothing else, which is not a file worth handing anyone.
    ///
    /// **A backup is never asked this.** A backup carries the preferences row and the gyms, which
    /// exist from the first tap and are the lifter's whatever they have logged — see ``BackupState``
    /// for the whole of that argument.
    var isEmpty: Bool { sessions.isEmpty && bodyweight.isEmpty }

    /// Every row in the file, across every section.
    ///
    /// **Records the file holds, not rows a restore gives back**, and the two differ today: a
    /// soft-deleted row is in this count and in the file, and `FR-1.11.4`'s restore reinstates it as
    /// a live row rather than a deleted one. The completeness reading is the one a backup's count
    /// has to mean — a number that quietly excluded rows the file contains would be the number that
    /// makes a lifter think the backup is short.
    ///
    /// **On the envelope rather than on either screen**, because both screens say it: the backup
    /// counts what it wrote and the restore counts what it is about to write, and two computations
    /// of one number are two that can disagree about a section added later.
    ///
    /// The preferences row counts as the one row it is.
    var recordCount: Int {
        exercises.count + sessions.count + entries.count + sets.count + bodyweight.count
            + equipment.count + trainingMaxes.count + trainingMaxHistory.count + routines.count
            + routineExercises.count + routineTargetGroups.count + programs.count
            + programDays.count + programRuns.count + plannedTargets.count
            + (settings == nil ? 0 : 1)
    }

    /// How many of those rows carry a ``RepositoryInterface/StoredRecord/deletedAt``.
    ///
    /// The half of the file an export does not have — and, read from the other direction, the number
    /// of rows a restore hands back live rather than deleted, which is what `FR-1.11.4`'s
    /// confirmation says out loud rather than leaving for the lifter to discover.
    ///
    /// **The preferences row is summed with the rest although it can never be deleted**, so that
    /// term is structurally zero today: ``RepositoryInterface/SettingsRepository`` offers no delete.
    /// It is summed anyway because ``recordCount`` counts that row, and a deleted total that skipped
    /// a row the other total counts is the pair disagreeing the moment the row does become
    /// deletable.
    var deletedCount: Int {
        Self.deleted(exercises) + Self.deleted(sessions) + Self.deleted(entries)
            + Self.deleted(sets) + Self.deleted(bodyweight) + Self.deleted(equipment)
            + Self.deleted(trainingMaxes) + Self.deleted(trainingMaxHistory)
            + Self.deleted(routines) + Self.deleted(routineExercises)
            + Self.deleted(routineTargetGroups) + Self.deleted(programs)
            + Self.deleted(programDays) + Self.deleted(programRuns)
            + Self.deleted(plannedTargets)
            + Self.deleted(settings.map { [$0] } ?? [])
    }

    /// How many of one section's rows are soft-deleted.
    ///
    /// - Parameter rows: One section.
    /// - Returns: The count.
    private static func deleted(_ rows: [some StoredRecord]) -> Int {
        rows.count { $0.deletedAt != nil }
    }
}
