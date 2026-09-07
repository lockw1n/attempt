import Foundation
import SwiftData

/// A named, ordered list of routines with a note — one week's plan (`TR-16.2`, `FR-16.8.1`).
///
/// The days hang off this, not the other way round — the same split ``RoutineEntity`` uses, and
/// shaped so `FR-2.1`'s blocks and weeks can be inserted above ``ProgramDayEntity`` later without
/// moving its ``ProgramDayEntity/routineID``.
@Model
final class ProgramEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var name: String = ""

    /// The lifter's note on the program (`FR-16.8.1`). Empty where they wrote none.
    var notes: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension ProgramEntity {
    static func matchingID(_ id: UUID) -> Predicate<ProgramEntity> {
        #Predicate<ProgramEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<ProgramEntity> {
        #Predicate<ProgramEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<ProgramEntity>
    ) -> Predicate<ProgramEntity> {
        #Predicate<ProgramEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<ProgramEntity> {
        #Predicate<ProgramEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
