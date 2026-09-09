import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

/// What `T-17.13`'s **Start next week** needs of a week fixture that reading one does not
/// (`FR-17.8.4`, `FR-17.8.6`).
///
/// **A file of its own** rather than four more members on ``WeekFixture``, which is at
/// `file_length`'s ceiling: these shape a week so that *what it prescribes* and *what was lifted*
/// can disagree, which is the only way the per-answer copy can be told from a copy of anything.
extension WeekFixture {
    /// Rewrites one slot's single target group, so a day can prescribe more than one thing.
    ///
    /// **The plan, not the answer**: `FR-17.8.6`'s skip carries the *planned* rows forward, and a
    /// fixture whose every slot prescribes the same numbers cannot tell them from what was lifted.
    ///
    /// - Parameters:
    ///   - day: The `ProgramDay.order` whose routine holds the slot.
    ///   - slot: The slot's position in that routine.
    ///   - grams: Its load, or `nil` for `FR-15.2.2`'s blank target.
    ///   - reps: Reps per set.
    ///   - sets: Sets prescribed.
    /// - Throws: Whatever the repository throws, or a failure where the routine has no such slot.
    func setTarget(day: Int, slot: Int, grams: Int?, reps: Int, sets: Int) async throws {
        let slots = try await stack.routines.exercises(
            forRoutineID: routineIDs[day], includingDeleted: false)
        guard slots.indices.contains(slot) else { throw WeekFixtureFailure.noEntries }
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: slots[slot].id, includingDeleted: false)
        guard let existing = groups.first else { throw WeekFixtureFailure.noEntries }
        try await stack.routines.save(
            RoutineTargetGroup(
                id: existing.id,
                createdAt: existing.createdAt,
                updatedAt: existing.updatedAt,
                deletedAt: nil,
                routineExerciseID: slots[slot].id,
                order: existing.order,
                targetWeight: grams.map { Weight(grams: $0) },
                targetReps: reps,
                targetSets: sets))
    }

    /// The targets one routine prescribes, flattened for comparison — load in grams, reps, sets.
    ///
    /// - Parameter routineID: The routine to read.
    /// - Returns: One triple per target group, in slot then group order.
    /// - Throws: Whatever the repository throws.
    func prescription(ofRoutineID routineID: UUID) async throws -> [PrescribedTarget] {
        let slots = try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        var flattened: [PrescribedTarget] = []
        for slot in slots {
            let groups = try await stack.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false)
            flattened.append(
                contentsOf: groups.map {
                    PrescribedTarget(
                        exerciseID: slot.exerciseID,
                        grams: $0.targetWeight?.grams,
                        reps: $0.targetReps,
                        sets: $0.targetSets)
                })
        }
        return flattened
    }

    /// Which routine each day of the program names now, in day order.
    ///
    /// - Returns: The identifiers.
    /// - Throws: Whatever the repository throws.
    func currentRoutineIDs() async throws -> [UUID] {
        try await stack.programs.days(forProgramID: programID, includingDeleted: false)
            .map(\.routineID)
    }
}

/// A run whose retired day cursor says something other than what it started at.
///
/// **A test helper rather than production code** (`D-17.10`): nothing writes
/// ``RepositoryInterface/ProgramRun/nextDayIndex`` any more, and the two suites that still assert
/// what happens when it disagrees with the sessions have to write it themselves.
extension ProgramRun {
    /// This run with its day cursor set and every other column untouched.
    ///
    /// - Parameter index: The `ProgramDay.order` the column is to hold.
    /// - Returns: The record to store.
    func withCursor(_ index: Int) -> ProgramRun {
        ProgramRun(
            id: id,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            programID: programID,
            startedAt: startedAt,
            endedAt: endedAt,
            weekNumber: weekNumber,
            nextDayIndex: index)
    }
}
