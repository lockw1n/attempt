import DerivedValues
import Foundation
import RepositoryInterface

/// Why a backup file cannot be restored — the refusals, in the shape the screen draws them.
///
/// **Three cases rather than one, because the three ask the lifter for three different things**: a
/// newer file wants a newer app, an export wants the other file, and a file that will not parse at
/// all wants a different copy of it. One "could not read that" would leave every one of those
/// unanswerable.
///
/// **A refusal is not a failure.** Nothing has been written when one is raised — see
/// ``StoreRestore/archive(from:)`` for why that is structural rather than a promise — which is what
/// separates this type from ``RestoreState/Phase/failed(_:)``.
enum RestoreRefusal: Error, Equatable, Sendable {
    /// The bytes are not an archive this build can read at all: truncated, another app's file, or a
    /// vocabulary spelling the envelope refuses (rule 5 of `RecordCoding.swift`).
    case unreadable

    /// A file written by a later version of the app, carrying the version it claims.
    case futureVersion(Int)

    /// A well-formed archive that is `FR-1.11.1`'s export rather than `FR-1.11.3`'s backup.
    case notABackup
}

/// What a file holds, read before anything is written (`FR-1.11.4`).
///
/// **The counts are the file's, not the restore's**, which is the reading ``TrainingLogArchive``
/// pins: ``deletedCount`` is how many rows the file carries a `deletedAt` on, and every one of them
/// comes back live. That divergence is the whole reason the number is drawn — see
/// ``StoreRestore/restore(_:)``.
///
/// One type for both sides of the confirmation, because it is one file: what the lifter is shown
/// before they confirm has to be what they are told was written after.
struct BackupSummary: Equatable, Sendable {
    /// When the backup was taken.
    let takenAt: Date

    /// How many workouts it holds.
    let workoutCount: Int

    /// How many rows it holds in total.
    let recordCount: Int

    /// How many of those the lifter had deleted.
    let deletedCount: Int

    /// Reads the counts off an archive.
    ///
    /// - Parameter archive: The file.
    init(_ archive: TrainingLogArchive) {
        takenAt = archive.exportedAt
        workoutCount = archive.sessions.count
        recordCount = archive.recordCount
        deletedCount = archive.deletedCount
    }

    /// Builds a summary directly, for a reference that has no file behind it.
    ///
    /// - Parameters:
    ///   - takenAt: When the backup was taken.
    ///   - workoutCount: How many workouts.
    ///   - recordCount: How many rows in total.
    ///   - deletedCount: How many of them were deleted.
    init(takenAt: Date, workoutCount: Int, recordCount: Int, deletedCount: Int) {
        self.takenAt = takenAt
        self.workoutCount = workoutCount
        self.recordCount = recordCount
        self.deletedCount = deletedCount
    }
}

/// Writes a backup file back into the store — `FR-1.11.4`'s half that ``FullBackup`` is the mirror
/// of.
///
/// **It writes through the repository protocols, one `save` at a time** (`TR-0.1.2`), which is
/// `TR-0.4.4`'s mapping asked to run in the direction only this task exercises: every column the
/// backup read out has to go back in through the same DTO.
///
/// **A restore overwrites by identifier; it does not empty the store first, and that is a
/// measurement rather than a preference.** The mapping layer never writes `deletedAt` on the way in
/// (rule 1 of `RecordMapping.swift`), so a wipe-then-write would soft-delete every row and then
/// upsert over it *leaving the deletion in place* — the restore would lose exactly the rows it had
/// just cleared, silently. What is available instead is an id-keyed upsert, which is a true replace
/// on the clean install `FR-1.11.3` describes and a file-wins merge anywhere else. The confirmation
/// copy says which.
///
/// **Two consequences of the same rule, both stated on the screen rather than left to be
/// discovered:** a soft-deleted row in the file arrives live, and a row already soft-deleted here
/// stays deleted however the file has it. `TR-1.14`'s purge and a writer that can set the column are
/// what would close them; neither exists yet.
struct StoreRestore {
    /// The catalogue, and each exercise's training-max history.
    let exercises: any ExerciseRepository

    /// Sessions, entries, sets — and what a routine planned for those slots (`FR-15.2.4`).
    ///
    /// One property answering two protocols, for ``FullBackup``'s reason read backwards: a planned
    /// target's save checks that the exercise entry it names is there, so the two writes have to be
    /// against one store.
    let workouts: any WorkoutRepository & PlannedTargetRepository

    /// The bodyweight log.
    let bodyweight: any BodyweightRepository

    /// The gyms.
    let equipment: any EquipmentRepository

    /// The routines, their slots and their target groups (`FR-15.2`).
    let routines: any RoutineRepository

    /// The preferences row — written through the restore's own entry point, not through a save.
    let settings: any SettingsRepository

    /// The app's one recompute actor, told that every restored session's sets are new to it.
    let records: PersonalRecordRecomputer

    /// Reads a file, and refuses it rather than writing part of it.
    ///
    /// **Nothing is written from here, which is what makes "no partial writes" structural.** The
    /// whole envelope is decoded and both questions are answered before ``restore(_:)`` is reachable
    /// at all, so a refused file cannot have touched the store — there is no path on which it could.
    ///
    /// **The version is asked first, and the discriminator second.** A file from a later version may
    /// spell `contents` in a way this build does not know, and reading that as "not a backup" would
    /// tell the lifter to find a different file when what they need is a newer app.
    ///
    /// **The version peek exists only to diagnose a decode that already failed**, rather than as a
    /// second validator beside the envelope's own: ``TrainingLogArchive``'s decoder is still the one
    /// thing that reads `contents`, and this asks the bytes for a number only once that decoder has
    /// said no.
    ///
    /// **`nonisolated`**, because the whole point of it is to run off the main thread: this module
    /// is `defaultIsolation(MainActor)` and the decode below is the expensive half of a restore.
    ///
    /// - Parameter data: The file's bytes.
    /// - Returns: The archive, known to be a backup this build can read.
    /// - Throws: A ``RestoreRefusal``.
    nonisolated static func archive(from data: Data) throws(RestoreRefusal) -> TrainingLogArchive {
        let archive: TrainingLogArchive
        do {
            archive = try TrainingLogArchive.decoded(from: data)
        } catch {
            throw claimedVersion(in: data).map(RestoreRefusal.futureVersion) ?? .unreadable
        }
        guard archive.formatVersion <= TrainingLogArchive.currentFormatVersion else {
            throw .futureVersion(archive.formatVersion)
        }
        guard archive.contents == .fullBackup else { throw .notABackup }
        return archive
    }

    /// The format version of a payload that did not decode, where it claims a later one.
    ///
    /// - Parameter data: The file's bytes.
    /// - Returns: The claimed version, or `nil` where there is none or it is one this build reads.
    private nonisolated static func claimedVersion(in data: Data) -> Int? {
        guard let marker = try? TrainingLogArchive.decoder.decode(VersionMarker.self, from: data),
            marker.formatVersion > TrainingLogArchive.currentFormatVersion
        else { return nil }
        return marker.formatVersion
    }

    /// Writes every row in the archive into the store.
    ///
    /// **The order is the store's referential rule and not a preference**: a save checks that the
    /// rows its foreign keys name are already there, so the catalogue precedes the training maxes
    /// and the slots, a session precedes its slots, and a slot precedes its sets and the targets a
    /// routine planned for it. Getting it wrong does not corrupt anything — it fails the save.
    ///
    /// **The routine tables are three more levels of the same rule** (`FR-15.2`): a routine precedes
    /// its slots, a slot precedes its target groups, and the catalogue precedes all three because a
    /// routine's slot names an exercise. They are written after the catalogue and before the log for
    /// no referential reason — nothing in the log names a routine — but reading the loops in
    /// dependency order is what makes the rule above checkable by eye.
    ///
    /// **A failed write stops the restore where it is, and the rows already written stay.** There is
    /// no transaction across six repositories, so the honest thing is to say so on the screen; what
    /// makes running the same file again *safe* is that every write here is an id-keyed upsert.
    /// **Safe is all it is, and the screen copy says only that** — a write that refused once refuses
    /// again, so a retry finishes the job only where the failure was transient. `FR-1.11.3` cost one
    /// of those the other reading: the settings row is written last and used to refuse a file from
    /// another device on identity grounds, forever, with all eleven other tables already landed —
    /// which is why the last write is now ``RepositoryInterface/SettingsRepository/restorePreferences(from:)``
    /// rather than a save.
    ///
    /// **`TR-0.3.9`'s cached records are not in the file and are recomputed afterwards** (`G-1.4`).
    /// Left out, every personal-record badge and estimated-max tile would read whatever the device
    /// held before the restore until the next qualifying set was logged. The recompute is per
    /// restored session, which is the granularity that touches only the exercises the file actually
    /// trained, and it swallows its own failures for the reason `PersonalRecordRecomputer` gives:
    /// the cache is then stale rather than wrong, and a stale one recomputes on the next read.
    ///
    /// - Parameter archive: The file, already accepted by ``archive(from:)``.
    /// - Returns: What was written.
    /// - Throws: Whatever a repository throws.
    @discardableResult
    func restore(_ archive: TrainingLogArchive) async throws -> BackupSummary {
        try await restoreCatalogue(archive)
        try await restoreRoutines(archive)
        try await restoreLog(archive)
        if let restored = archive.settings {
            try await settings.restorePreferences(from: restored)
        }

        for session in archive.sessions { await records.sessionDidChange(id: session.id) }
        return BackupSummary(archive)
    }

    /// Writes what the log's rows refer to: the catalogue, its training maxes, and the gyms.
    ///
    /// - Parameter archive: The file.
    /// - Throws: Whatever a repository throws.
    private func restoreCatalogue(_ archive: TrainingLogArchive) async throws {
        for exercise in archive.exercises { try await exercises.save(exercise) }
        for entry in archive.trainingMaxes { try await exercises.saveTrainingMax(entry) }
        for profile in archive.equipment { try await equipment.save(profile) }
    }

    /// Writes the three routine tables, parents first (`FR-15.2`).
    ///
    /// - Parameter archive: The file.
    /// - Throws: Whatever the routine repository throws.
    private func restoreRoutines(_ archive: TrainingLogArchive) async throws {
        for routine in archive.routines { try await routines.save(routine) }
        for slot in archive.routineExercises { try await routines.save(slot) }
        for group in archive.routineTargetGroups { try await routines.save(group) }
    }

    /// Writes what the lifter logged, and what a routine had planned for it.
    ///
    /// - Parameter archive: The file.
    /// - Throws: Whatever a repository throws.
    private func restoreLog(_ archive: TrainingLogArchive) async throws {
        for entry in archive.bodyweight { try await bodyweight.save(entry) }
        for session in archive.sessions { try await workouts.save(session) }
        for entry in archive.entries { try await workouts.save(entry) }
        for set in archive.sets { try await workouts.save(set) }
        for group in archive.plannedTargets { try await workouts.save(group) }
    }
}

/// The one key a payload that failed to decode is still asked for.
///
/// A type of its own rather than a keyed container read by hand, so the decoder that reads it is
/// ``TrainingLogArchive``'s own — a marker configuring a second one would be the second home for
/// that fact.
private struct VersionMarker: nonisolated Decodable {
    /// What the file says it was written under.
    let formatVersion: Int
}
