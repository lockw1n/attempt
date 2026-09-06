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
