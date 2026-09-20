import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface

@testable import Logging

/// The plan shapes a week fixture does not have by default — a backoff with no load, and a second
/// group that has one.
///
/// **A file of their own because `WeekFixtures.swift` is at `file_length`'s ceiling**, and because
/// these are shapes a particular claim needs rather than part of what a week *is*: `FR-15.2.2`'s
/// open load, and `DOD-18.4`'s two-group exercise.
extension WeekFixture {
    /// Adds a second target group to a day's **first** slot prescribing reps and no load.
    ///
    /// **A backoff on a row that already has a load**, which is the case
    /// ``DayRowCircle/isOffered(answer:plan:)``'s "every group has to name a load, not merely the
    /// first" exists for — and the one ``addOpenLoadSlot(day:)`` cannot produce, that adding a
    /// whole row instead.
    ///
    /// - Parameter day: The `ProgramDay.order` whose first slot gains the group.
    /// - Throws: Whatever the repository throws.
    func addOpenLoadBackoff(day: Int) async throws {
        let slots = try await stack.routines.exercises(
            forRoutineID: routineIDs[day], includingDeleted: false)
        guard let slot = slots.first else { throw WeekFixtureFailure.noEntries }
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)
        try await stack.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                routineExerciseID: slot.id,
                order: groups.count,
                targetWeight: nil,
                targetReps: 8,
                targetSets: 2))
    }

    /// Adds a second **loaded** target group to one of a day's slots (`FR-15.2.1`).
    ///
    /// ``addOpenLoadBackoff(day:)``'s opposite number, and the shape `DOD-18.4` turns on: an
    /// exercise the plan names in two groups is one the circle answers in two runs, and every
    /// Phase 1.7 fixture prescribed exactly one.
    ///
    /// - Parameters:
    ///   - day: The `ProgramDay.order` whose routine gains the group.
    ///   - slot: Which of that routine's slots, in order.
    ///   - grams: The load prescribed.
    ///   - reps: The repetitions.
    ///   - sets: How many sets.
    /// - Throws: Whatever the repository throws, or a failure where the routine has no such slot.
    func addLoadedGroup(
        day: Int, slot index: Int, grams: Int = 120_000, reps: Int = 3, sets: Int = 2
    ) async throws {
        let unordered = try await stack.routines.exercises(
            forRoutineID: routineIDs[day], includingDeleted: false)
        let slots = unordered.sorted { $0.order < $1.order }
        guard index < slots.count else { throw WeekFixtureFailure.noEntries }
        let slot = slots[index]
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)
        try await stack.routines.save(
            RoutineTargetGroup(
                id: UUID(),
                createdAt: weekFixtureDay,
                updatedAt: weekFixtureDay,
                deletedAt: nil,
                routineExerciseID: slot.id,
                order: groups.count,
                targetWeight: Weight(grams: grams),
                targetReps: reps,
                targetSets: sets))
    }
}
