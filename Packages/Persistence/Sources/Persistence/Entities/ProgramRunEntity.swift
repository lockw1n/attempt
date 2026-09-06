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

// `StoredEntity` requires these four per concrete type and supplies no default. The reason is on
// the protocol's own requirements, and it is not a style preference: a `#Predicate` written in a
// generic context captures a key path the optimizer may re-instantiate, which fetches correctly
// unoptimized and traps under `-O`.
extension ProgramRunEntity {
    static func matchingID(_ id: UUID) -> Predicate<ProgramRunEntity> {
        #Predicate<ProgramRunEntity> { $0.id == id }
    }

    static var notDeleted: Predicate<ProgramRunEntity> {
        #Predicate<ProgramRunEntity> { $0.deletedAt == nil }
    }

    static func notDeleted(
        alsoMatching other: Predicate<ProgramRunEntity>
    ) -> Predicate<ProgramRunEntity> {
        #Predicate<ProgramRunEntity> { entity in
            other.evaluate(entity) && entity.deletedAt == nil
        }
    }

    static func softDeleted(onOrBefore cutoff: Date) -> Predicate<ProgramRunEntity> {
        #Predicate<ProgramRunEntity> { entity in
            if let deletedAt = entity.deletedAt {
                return deletedAt <= cutoff
            } else {
                return false
            }
        }
    }
}
