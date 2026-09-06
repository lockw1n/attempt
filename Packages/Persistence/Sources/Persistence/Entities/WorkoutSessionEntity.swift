import Foundation
import SwiftData

/// One training session (`TR-0.3.2`).
///
/// **``date`` is a correctness input, not a display field.** `PersonalRecordCalculator` has no
/// `Date` at all, so `TR-0.2.8`'s "ties resolve to the earlier set" is positional — it means earlier
/// in the collection it was handed. `(date, ExerciseEntryEntity.order, SetEntryEntity.order)` is the
/// sort key that makes that mean chronological, and T-0.42 carries the obligation to apply it.
@Model
final class WorkoutSessionEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The training day this session belongs to, which is not necessarily when it was entered.
    var date: Date = SchemaDefaults.sessionDate

    /// When the session was started and finished, if it was tracked live.
    var startedAt: Date?

    /// See ``startedAt``.
    var endedAt: Date?

    var notes: String = ""

    /// Bodyweight recorded alongside the session, in grams (`G-1.1`), or `nil` if none was.
    var bodyweightGrams: Int?

    /// Forward references to Phase 2 entities that do not exist yet (`OUT-0.3` defers the storage,
    /// not the field). Nothing in Phase 0 reads or writes them.
    var programRunID: UUID?

    /// See ``programRunID``.
    var scheduledWorkoutID: UUID?

    /// The week and the day this session was started under, or `nil` where it was not started from
    /// a program (`FR-16.8.3`). Written once, at start; a program edited afterwards never reaches
    /// them.
    ///
    /// **Optional rather than defaulted, and that is `SchemaV1`'s first rule** — they are columns
    /// added after v1's declaration was written, so every session already on a lifter's device
    /// backfills from one frozen value, and `nil` is the only value that is not a claim about a
    /// workout logged before programs existed.
    var weekNumber: Int?

    /// See ``weekNumber``.
    var dayIndex: Int?

    init(
        id: UUID = UUID(),
        date: Date,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        notes: String = "",
        bodyweightGrams: Int? = nil,
        programRunID: UUID? = nil,
        scheduledWorkoutID: UUID? = nil,
        weekNumber: Int? = nil,
        dayIndex: Int? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.date = date
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.bodyweightGrams = bodyweightGrams
        self.programRunID = programRunID
        self.scheduledWorkoutID = scheduledWorkoutID
        self.weekNumber = weekNumber
        self.dayIndex = dayIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
