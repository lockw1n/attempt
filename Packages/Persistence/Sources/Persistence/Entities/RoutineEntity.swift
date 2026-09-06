import Foundation
import SwiftData

/// A named, ordered training plan for one day (`FR-15.2.1`). The exercises hang off this, not the
/// other way round — same split `WorkoutSessionEntity`/`ExerciseEntryEntity` uses.
@Model
final class RoutineEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    var name: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension RoutineEntity {
    static func matchingID(_ id: UUID) -> Predicate<RoutineEntity> {
        #Predicate<RoutineEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<RoutineEntity> {
        #Predicate<RoutineEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<RoutineEntity>
    ) -> Predicate<RoutineEntity> {
        #Predicate<RoutineEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<RoutineEntity> {
        #Predicate<RoutineEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
