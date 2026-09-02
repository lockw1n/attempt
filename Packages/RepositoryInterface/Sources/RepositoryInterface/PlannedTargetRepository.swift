import Foundation

/// The targets a session's exercises were planned with (`TR-15.3`, `FR-15.2.3`).
///
/// **A protocol of its own rather than two more members on ``WorkoutRepository``**, which is the
/// split every other aggregate here already has. The rows belong to a session's entries and the
/// real implementations conform to both — so the cascade below is internal to one type — but a
/// caller that only logs sets has no business implementing a planned-target read, and the
/// obligation would land on every stand-in that exists to answer three questions about sets.
///
/// **There is no `deletePlannedTarget(id:)`, and that is not an omission.** A planned group is
/// removed only when the exercise it was planned for goes, which the cascade below does; nothing
/// in `FR-15.2`/`FR-15.3` deletes one on its own, and a write nothing performs is a promise
/// nothing keeps.
public protocol PlannedTargetRepository: Sendable {
    /// The groups planned for one exercise entry, in ``PlannedTargetGroup/order``.
    ///
    /// Empty for an exercise added by hand — most workouts are not started from a routine, and
    /// that is not a state anything reports.
    func plannedTargets(
        forEntryID entryID: UUID, includingDeleted: Bool
    ) async throws -> [PlannedTargetGroup]

    /// Inserts or replaces the group, keyed on ``PlannedTargetGroup/id``.
    ///
    /// - Throws: ``RepositoryError/danglingReference(recordID:referencing:)`` if the exercise entry
    ///   does not exist.
    func save(_ group: PlannedTargetGroup) async throws
}
