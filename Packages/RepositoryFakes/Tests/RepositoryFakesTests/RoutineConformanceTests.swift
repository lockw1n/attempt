import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

/// Routines, their exercise slots and target groups (`FR-15.2`), against both implementations.
@Suite("Conformance — routines")
struct RoutineConformanceTests {
    @Test(
        "A slot with two target groups at different weights round-trips, order and boundaries intact",
        arguments: Subject.all
    )
    func targetGroupsRoundTrip(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord(name: "Squat day")
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)

        let topSet = routineTargetGroupRecord(
            routineExerciseID: slot.id, order: 0, grams: 90_000, reps: 4, sets: 4)
        let backoff = routineTargetGroupRecord(
            routineExerciseID: slot.id, order: 1, grams: 80_000, reps: 5, sets: 4)
        // Saved out of order, so a read that trusted insertion order would still fail.
        try await repositories.routines.save(backoff)
        try await repositories.routines.save(topSet)

        let readRoutine = try await repositories.routines.routine(id: routine.id, includingDeleted: false)
        let readSlots = try await repositories.routines.exercises(
            forRoutineID: routine.id, includingDeleted: false)
        let readGroups = try await repositories.routines.targetGroups(
            forRoutineExerciseID: slot.id, includingDeleted: false)

        #expect(readRoutine?.name == "Squat day")
        #expect(readSlots.map(\.id) == [slot.id])
        #expect(readGroups.map(\.order) == [0, 1])
        #expect(readGroups.map(\.targetWeight) == [Weight(grams: 90_000), Weight(grams: 80_000)])
        #expect(readGroups.map(\.targetReps) == [4, 5])
        #expect(readGroups.map(\.targetSets) == [4, 4])
        #expect(
            readGroups.map(\.prescription) == [
                .fixedWeight(Weight(grams: 90_000)), .fixedWeight(Weight(grams: 80_000)),
            ])
    }

    @Test("Deleting a routine cascades to its slots and their target groups", arguments: Subject.all)
    func deletingARoutineCascades(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord()
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)
        let group = routineTargetGroupRecord(routineExerciseID: slot.id)
        try await repositories.routines.save(group)

        // A bystander routine that must not be touched — a cascade keyed on the wrong column would
        // take it, and every assertion below would still pass without it.
        let bystander = routineRecord(name: "Bench day")
        try await repositories.routines.save(bystander)
        let bystanderSlot = routineExerciseRecord(routineID: bystander.id, exerciseID: exerciseID)
        try await repositories.routines.save(bystanderSlot)
        let bystanderGroup = routineTargetGroupRecord(routineExerciseID: bystanderSlot.id)
        try await repositories.routines.save(bystanderGroup)

        try await repositories.routines.deleteRoutine(id: routine.id)

        #expect(try await repositories.routines.routine(id: routine.id, includingDeleted: false) == nil)
        #expect(
            try await repositories.routines.exercises(forRoutineID: routine.id, includingDeleted: false)
                .isEmpty)
        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ).isEmpty)

        #expect(try await repositories.routines.routine(id: bystander.id, includingDeleted: false) != nil)
        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: bystanderSlot.id, includingDeleted: false
            ).count == 1)
    }

    @Test("Deleting a slot takes its target groups and leaves the routine alone", arguments: Subject.all)
    func deletingASlotCascadesDownwardsOnly(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord()
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)
        try await repositories.routines.save(routineTargetGroupRecord(routineExerciseID: slot.id))

        try await repositories.routines.deleteRoutineExercise(id: slot.id)

        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ).isEmpty)
        // Upwards is what must not move — a cascade written in the wrong direction would take the
        // routine with the slot, and every assertion above would still pass.
        #expect(try await repositories.routines.routine(id: routine.id, includingDeleted: false) != nil)
    }

    /// A live target group under an already-deleted slot is still swept with the routine.
    ///
    /// Only a sync or an import produces this state, and both implementations sweep deleted slots
    /// for their *groups* rather than for themselves — so the guard that skips re-stamping the slot
    /// is invisible to any assertion about the groups alone, and `updatedAt` is asserted too.
    @Test("The routine cascade reaches through a slot that was already deleted", arguments: Subject.all)
    func theCascadeReachesThroughADeletedSlot(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord()
        try await repositories.routines.save(routine)
        let slot = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        try await repositories.routines.save(slot)
        try await repositories.routines.save(routineTargetGroupRecord(routineExerciseID: slot.id))
        try await repositories.routines.deleteRoutineExercise(id: slot.id)

        let deletedSlot = try #require(
            try await repositories.routines.routineExercise(id: slot.id, includingDeleted: true))

        try await repositories.routines.deleteRoutine(id: routine.id)

        #expect(
            try await repositories.routines.targetGroups(
                forRoutineExerciseID: slot.id, includingDeleted: false
            ).isEmpty)
        // The slot is not written again: it keeps the moment it actually left the routine AND the
        // `updatedAt` of the write that put it there. `deletedAt` alone does not say that — the
        // soft delete is idempotent in that column — so both are asserted, which is what makes the
        // cascade's already-deleted guard load-bearing rather than decorative.
        let afterwards = try #require(
            try await repositories.routines.routineExercise(id: slot.id, includingDeleted: true))
        #expect(afterwards.deletedAt == deletedSlot.deletedAt)
        #expect(afterwards.updatedAt == deletedSlot.updatedAt)
    }

    /// Five rows tied on `order`, not two, and that is about the probe rather than the code.
    ///
    /// The mutation worth catching is a tie-break that drops the `id.uuidString` clause. Neither
    /// subject's residual order is then meaningful — a dictionary's values have no order at all and
    /// `sorted` is not stable — so the answer is a permutation, and **with two tied rows a wrong
    /// implementation passes about half the time**. Measured: a two-row version of this test
    /// survived exactly that mutation on the fakes. Five ties make it 1 in 120, which is the
    /// difference between a probe that measures something and a coin. Same reasoning, and the same
    /// count, as `RecordTests.modifiersAreCanonicalised`.
    @Test("Slots and target groups come back by order, and ties by id", arguments: Subject.all)
    func routineChildrenAreOrderedByOrderThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))
        let routine = routineRecord()
        try await repositories.routines.save(routine)

        let tied = TiedIDs.ascending
        #expect(tied.count == 5, "the tie-break probe needs five ids to be worth running")
        // Saved in a scrambled order that is not the answer, so a read returning insertion order
        // fails as surely as one returning nothing.
        for id in [tied[3], tied[0], tied[4], tied[2], tied[1]] {
            try await repositories.routines.save(
                routineExerciseRecord(
                    id: id, routineID: routine.id, exerciseID: exerciseID, order: 0))
        }
        // One slot at a later `order`, so the primary key is exercised too — a read sorting on id
        // alone would put this one first and fail.
        let last = try #require(UUID(uuidString: "00000000-0000-4000-8000-0000000000FF"))
        try await repositories.routines.save(
            routineExerciseRecord(
                id: last, routineID: routine.id, exerciseID: exerciseID, order: 1))

        for id in [tied[2], tied[4], tied[1], tied[3], tied[0]] {
            try await repositories.routines.save(
                routineTargetGroupRecord(id: id, routineExerciseID: tied[0], order: 0))
        }

        let slots = try await repositories.routines.exercises(
            forRoutineID: routine.id, includingDeleted: false)
        let groups = try await repositories.routines.targetGroups(
            forRoutineExerciseID: tied[0], includingDeleted: false)

        #expect(slots.map(\.id) == tied + [last])
        #expect(slots.map(\.order) == [0, 0, 0, 0, 0, 1])
        #expect(groups.map(\.id) == tied)
    }

    /// **One key withheld at a time, and that is the point of the test rather than its shape.**
    ///
    /// An earlier version withheld only the exercise, so the routine check was refused by nothing:
    /// deleting it from *both* implementations left the whole suite green. Withholding both at
    /// once would be no better — either check alone satisfies the expectation, so one could still
    /// go missing for free.
    @Test("A slot needs both its routine and its exercise", arguments: Subject.all)
    func aSlotNeedsBothOfItsJoinKeys(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let routine = routineRecord()
        let exerciseID = UUID()
        try await repositories.exercises.save(exerciseRecord(id: exerciseID))

        // The routine key alone: the exercise this slot names exists, so nothing else can refuse.
        let unrooted = routineExerciseRecord(routineID: routine.id, exerciseID: exerciseID)
        await #expect(
            throws: RepositoryError.danglingReference(recordID: unrooted.id, referencing: routine.id)
        ) { try await repositories.routines.save(unrooted) }

        // Then the exercise key alone, the routine now in place.
        try await repositories.routines.save(routine)
        let missingExerciseID = UUID()
        let orphan = routineExerciseRecord(routineID: routine.id, exerciseID: missingExerciseID)
        await #expect(
            throws: RepositoryError.danglingReference(
                recordID: orphan.id, referencing: missingExerciseID)
        ) { try await repositories.routines.save(orphan) }

        // And with both present the refused write lands, so neither refusal is unconditional.
        try await repositories.routines.save(unrooted)
        #expect(
            try await repositories.routines.exercises(forRoutineID: routine.id, includingDeleted: false)
                .count == 1)
    }

    /// `RoutineRepository`'s only list-all read, and the only one of its members whose sort key is
    /// a **name** — every other read orders on `order`. It had no test and no caller at all.
    ///
    /// Five rows tied on the name for `routineChildrenAreOrderedByOrderThenID`'s reason: a
    /// tie-break that dropped `id.uuidString` would otherwise pass on a coin toss.
    @Test(
        "Routines come back by name, ties by id, and the flag hides a deleted one",
        arguments: Subject.all
    )
    func routinesAreListedByNameThenID(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let tied = TiedIDs.ascending
        let first = routineRecord(name: "Bench day")
        let last = routineRecord(name: "Zercher day")

        // Saved in an order that is neither the answer nor its reverse, so a read handing back
        // insertion order fails either way round.
        try await repositories.routines.save(last)
        for id in [tied[3], tied[0], tied[4], tied[2], tied[1]] {
            try await repositories.routines.save(routineRecord(id: id, name: "Squat day"))
        }
        try await repositories.routines.save(first)

        #expect(
            try await repositories.routines.routines(includingDeleted: false).map(\.id)
                == [first.id] + tied + [last.id])

        try await repositories.routines.deleteRoutine(id: tied[2])

        // Both halves of the flag, so the read cannot satisfy this by answering the same list twice.
        #expect(
            try await repositories.routines.routines(includingDeleted: false).map(\.id)
                == [first.id, tied[0], tied[1], tied[3], tied[4], last.id])
        #expect(
            try await repositories.routines.routines(includingDeleted: true).map(\.id)
                == [first.id] + tied + [last.id])
    }

    @Test("A target group needs its slot", arguments: Subject.all)
    func aTargetGroupNeedsItsSlot(_ subject: Subject) async throws {
        let repositories = try subject.make()
        let slotID = UUID()
        let orphan = routineTargetGroupRecord(routineExerciseID: slotID)

        await #expect(
            throws: RepositoryError.danglingReference(recordID: orphan.id, referencing: slotID)
        ) { try await repositories.routines.save(orphan) }
    }
}
