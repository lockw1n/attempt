import Foundation
import SwiftData

/// One pass through a program: which week it is on, and which day comes next (`TR-16.2`,
/// `FR-16.8.3`).
///
/// **A table rather than three columns on ``ProgramEntity``**, because `FR-16.8.4`'s *Start next
/// week* needs a row to end and a row to begin — a counter on the program would be overwritten by
/// the advance, and every session already logged would re-describe itself as belonging to the
/// current week. `WorkoutSessionEntity/programRunID` has pointed here since schema v1.
@Model
final class ProgramRunEntity: StoredEntity {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    /// The ``ProgramEntity`` being run.
    var programID: UUID = SchemaDefaults.unlinkedID

    /// When this pass began — not ``createdAt``, which is when the row was written.
    var startedAt: Date = SchemaDefaults.runStartedAt

    /// When it finished, or `nil` while it is the run in force.
    ///
    /// **`nil` is the whole of what "current" means**, and there is no `isCurrent` column beside it:
    /// a second row could contradict one (`G-1.4`), where a second open run is a tie the read
    /// resolves.
    var endedAt: Date?

    /// The week the lifter is on — the `#N` of a plan file, not an index.
    ///
    /// Defaulted to zero, which is no week at all and therefore visibly wrong in a row this app did
    /// not write, rather than a plausible `1` that reads as the lifter's own first week.
    var weekNumber: Int = 0

    /// The ``ProgramDayEntity/order`` of the day to train next. Zero is the first day, which is what
    /// a run that has trained nothing holds.
    var nextDayIndex: Int = 0

    init(
        id: UUID = UUID(),
        programID: UUID,
        startedAt: Date,
        weekNumber: Int,
        nextDayIndex: Int,
        endedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.programID = programID
        self.startedAt = startedAt
        self.weekNumber = weekNumber
        self.nextDayIndex = nextDayIndex
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
