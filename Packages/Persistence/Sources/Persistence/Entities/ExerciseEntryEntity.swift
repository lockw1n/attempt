import Foundation
import SwiftData

/// One exercise performed within a session — the sets hang off this, not off the session
/// (`TR-0.3.3`).
@Model
final class ExerciseEntryEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``WorkoutSessionEntity`` this entry belongs to.
    ///
    /// A plain `UUID` column, because the schema declares no relationships (`G-2.5`) — so nothing
    /// enforces that the row exists, and a reference to a missing session is a repository concern.
    var sessionID: UUID = SchemaDefaults.unlinkedID

    /// The ``ExerciseEntity`` performed. Seeded exercise ids are permanent for this reason: they are
    /// in users' logged history and regenerating one orphans every set logged against it.
    var exerciseID: UUID = SchemaDefaults.unlinkedID

    /// Position within the session, ascending.
    ///
    /// Explicit because SwiftData's array order is not a contract, and reading order off a fetch
    /// that did not sort is a silent corruption rather than a visible one.
    var order: Int = 0

    var notes: String = ""

    /// Whether the lifter has said they are finished with this exercise (`FR-15.3.4`).
    ///
    /// **A column added after schema v1, and `false` is the value every existing row backfills
    /// from** — which is the right answer for all of them: nobody checked off an exercise before
    /// the control existed.
    var isMarkedDone: Bool = false

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        exerciseID: UUID,
        order: Int,
        notes: String = "",
        isMarkedDone: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.exerciseID = exerciseID
        self.order = order
        self.notes = notes
        self.isMarkedDone = isMarkedDone
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension ExerciseEntryEntity {
    static func matchingID(_ id: UUID) -> Predicate<ExerciseEntryEntity> {
        #Predicate<ExerciseEntryEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<ExerciseEntryEntity> {
        #Predicate<ExerciseEntryEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<ExerciseEntryEntity>
    ) -> Predicate<ExerciseEntryEntity> {
        #Predicate<ExerciseEntryEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<ExerciseEntryEntity> {
        #Predicate<ExerciseEntryEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
