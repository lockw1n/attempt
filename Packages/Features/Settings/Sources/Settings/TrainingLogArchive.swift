import Foundation
import RepositoryInterface

/// The training log as one structured value — `FR-1.11.1`'s JSON export, and the shape `FR-1.11.3`'s
/// backup and its restore build on.
///
/// **Flat arrays of `RepositoryInterface`'s records, not a nested tree.** The records already carry
/// their own foreign keys (a set names its entry, an entry names its session and its exercise), so
/// nesting would either duplicate those keys or drop them, and a reader that dropped them could not
/// rebuild the rows. `TR-0.4.4`'s DTO layer is the wire format; this type is an envelope over it and
/// restates none of its rules.
///
/// **An export is what the lifter has, so soft-deleted rows are not in it** (`G-1.3`). The gatherer
/// asks every repository for live rows only, which is why every ``StoredRecord/deletedAt`` here is
/// `nil` and why the format still carries the column: a backup written by a later reading must not
/// need a different shape to say so.
///
/// **A section this export does not carry is a section a backup adds**, in this same envelope rather
/// than in a second one: preferences, equipment profiles and training-max history are the lifter's
/// configuration rather than the log, and `FR-1.11.1` asks for the log. Adding an array to a later
/// version is additive under rule 3 of `RecordCoding.swift` — an absent section is an omitted key.
struct TrainingLogArchive: Codable, Sendable, Equatable {
    /// Which reading of this envelope wrote the file.
    ///
    /// **It is not `TR-2.4`'s schema version and does not track it.** It says what fields to expect
    /// here; the rows inside are versioned by the store they came from.
    let formatVersion: Int

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

    /// The wire keys, declared rather than synthesised — rule 1 of `RecordCoding.swift`, which this
    /// envelope follows for the reason the records do: renaming a property must not be a rename.
    /// Both halves stay synthesised, because unlike a record this type holds no vocabulary column
    /// and so has nothing to resolve on the way in.
    enum CodingKeys: String, CodingKey {
        case formatVersion
        case exportedAt
        case exercises
        case sessions
        case entries
        case sets
        case bodyweight
    }

    /// The reading this build writes and the only one it has ever written.
    static let currentFormatVersion = 1

    /// Builds an archive at the current format version.
    ///
    /// - Parameters:
    ///   - exportedAt: When the file is being written.
    ///   - exercises: The catalogue.
    ///   - sessions: Every workout.
    ///   - entries: Every exercise slot.
    ///   - sets: Every set.
    ///   - bodyweight: Every reading.
    init(
        exportedAt: Date,
        exercises: [Exercise],
        sessions: [WorkoutSession],
        entries: [ExerciseEntry],
        sets: [SetEntry],
        bodyweight: [BodyweightEntry]
    ) {
        formatVersion = Self.currentFormatVersion
        self.exportedAt = exportedAt
        self.exercises = exercises
        self.sessions = sessions
        self.entries = entries
        self.sets = sets
        self.bodyweight = bodyweight
    }

    /// Whether there is a training log here at all.
    ///
    /// **The sessions and the readings decide it, never the exercises.** The catalogue is seeded at
    /// first launch, so an export of a store nobody has trained in is not empty by row count — it is
    /// a hundred exercises and nothing else, which is not a file worth handing anyone.
    var isEmpty: Bool { sessions.isEmpty && bodyweight.isEmpty }
}
