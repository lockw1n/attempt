import Foundation
import SwiftData

/// One day of a program — a position, and the routine trained at it (`TR-16.2`, `FR-16.8.1`).
@Model
final class ProgramDayEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ProgramEntity`` this day belongs to.
    ///
    /// A plain `UUID` column, because the schema declares no relationships (`G-2.5`) — so nothing
    /// enforces that the row exists, and a reference to a missing program is a repository concern.
    var programID: UUID = SchemaDefaults.unlinkedID

    /// The ``RoutineEntity`` trained on this day.
    ///
    /// **It may name a routine the lifter has archived.** `FR-15.2.5`'s archive is a soft delete
    /// and nothing sweeps the days pointing at it, so this column outlives its target by design.
    var routineID: UUID = SchemaDefaults.unlinkedID

    /// Position within the program, ascending — the index a session records (`FR-16.8.3`).
    ///
    /// Explicit for ``RoutineExerciseEntity/order``'s reason: SwiftData's array order is not a
    /// contract, and reading order off an unsorted fetch is a silent corruption.
    var order: Int = 0

    init(
        id: UUID = UUID(),
        programID: UUID,
        routineID: UUID,
        order: Int,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.programID = programID
        self.routineID = routineID
        self.order = order
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension ProgramDayEntity {
    static func matchingID(_ id: UUID) -> Predicate<ProgramDayEntity> {
        #Predicate<ProgramDayEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<ProgramDayEntity> {
        #Predicate<ProgramDayEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<ProgramDayEntity>
    ) -> Predicate<ProgramDayEntity> {
        #Predicate<ProgramDayEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<ProgramDayEntity> {
        #Predicate<ProgramDayEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
