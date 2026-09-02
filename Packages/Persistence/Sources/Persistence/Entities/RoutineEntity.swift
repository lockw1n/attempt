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
