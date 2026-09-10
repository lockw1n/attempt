import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

/// The write-through half of `FR-17.10.1`, and `Q-17.4`'s answer — a second suite in a file of
/// its own, `WeekEditorStateTests.swift` holding the week's own shape. Two files rather than
/// one on `file_length`'s argument, which is the same seam the suites already took.
@MainActor
@Suite("Week editor targets")
struct WeekEditorTargetTests {
    @Test("a target is written the moment it resolves, and not before")
    func targetsWriteThroughOnceTheyResolve() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addExercise(id: squat.id)
        let slotID = try #require(state.days.first?.slots.first?.id)

        // Reps alone is not a prescription.
        state.editTarget(0, inSlot: 0, inDayAt: 0) { $0.repsText = "5" }
        await state.commitTarget(0, inSlot: 0, inDayAt: 0)
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: slotID, includingDeleted: false
            ).isEmpty)

        // Reps and sets are, and a blank load is a prescribed blank (`FR-15.2.2`).
        state.editTarget(0, inSlot: 0, inDayAt: 0) { $0.setsText = "3" }
        await state.commitTarget(0, inSlot: 0, inDayAt: 0)
        let stored = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(stored.count == 1)
        #expect(stored.first?.targetWeight == nil)
        #expect(stored.first?.targetReps == 5)
        #expect(stored.first?.targetSets == 3)
        #expect(stored.first?.order == 0)
    }

    @Test("a load typed into a stored target lands, and emptying reps leaves the row alone")
    func emptyingAFieldKeepsTheStoredRow() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await fillTarget(state, weight: "100", reps: "5", sets: "3")
        let slotID = try #require(state.days.first?.slots.first?.id)

        state.editTarget(0, inSlot: 0, inDayAt: 0) { $0.weightText = "102.5" }
        await state.commitTarget(0, inSlot: 0, inDayAt: 0)
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: slotID, includingDeleted: false
            ).first?.targetWeight
                == Weight(grams: 102_500))

        // Mid-retype: unstorable, so the store keeps what it holds rather than a zero.
        state.editTarget(0, inSlot: 0, inDayAt: 0) { $0.repsText = "" }
        await state.commitTarget(0, inSlot: 0, inDayAt: 0)
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: slotID, includingDeleted: false
            ).first?.targetReps == 5)
    }

    /// The delete is watched rather than inferred. `removeTarget` also *catches*
    /// `recordNotFound`, so asserting only that nothing was reported passes whether or not the
    /// store was asked at all — and that is what the first version of this test did.
    @Test("a second target reorders and removes, and one never stored is never deleted")
    func reorderingAndRemovingTargets() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let recorder = FlakyRoutineRepository(stack.routines)
        let state = await opened(
            weekEditor(over: stack, routines: recorder, programs: stack.programs))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await fillTarget(state, group: 0, weight: "180", reps: "3", sets: "1")
        state.addTarget(toSlot: 0, inDayAt: 0)
        await fillTarget(state, group: 1, weight: "150", reps: "8", sets: "3")
        let slotID = try #require(state.days.first?.slots.first?.id)

        // Written through at their own positions BEFORE anything reorders them — `moveTarget`
        // rewrites every stored order, so an assertion made only after it passes for a commit that
        // wrote them all at zero.
        var stored = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(stored.map(\.order) == [0, 1])
        #expect(stored.map(\.targetReps) == [3, 8])

        await state.moveTarget(1, by: -1, inSlot: 0, inDayAt: 0)
        stored = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(stored.map(\.targetReps) == [8, 3])
        #expect(stored.map(\.order) == [0, 1])

        // A group added and never filled in is in no table, so the store is never named for it.
        state.addTarget(toSlot: 0, inDayAt: 0)
        await state.removeTarget(2, inSlot: 0, inDayAt: 0)
        #expect(recorder.deletedTargetGroupIDs.isEmpty)
        #expect(state.writeFailed == false)
        #expect(state.days.first?.slots.first?.groups.count == 2)

        let topSet = try #require(state.days.first?.slots.first?.groups.first?.id)
        await state.removeTarget(0, inSlot: 0, inDayAt: 0)
        #expect(recorder.deletedTargetGroupIDs == [topSet])
        stored = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(stored.map(\.targetReps) == [3])
        #expect(stored.map(\.order) == [0])
    }

    @Test("a target that resolves and cannot be written says so")
    func aRefusedTargetWriteIsReported() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(
            weekEditor(
                over: stack,
                routines: FlakyRoutineRepository(stack.routines, refusingTargetSaves: true),
                programs: stack.programs))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await fillTarget(state)

        #expect(state.writeFailed)
    }

    /// Reported AND undone. The routine lands before the day by necessity, and on a fresh install
    /// the program and its run land before both — left behind they are a routine nothing names and
    /// a current week with no days, which Train's root draws in place of **Plan your week**
    /// (`FR-17.10.2`, `DOD-17.9`).
    @Test("a day the store will not take says so and leaves nothing behind")
    func aRefusedDayWriteIsReported() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(
            weekEditor(
                over: stack,
                routines: stack.routines,
                programs: FlakyProgramRepository(stack.programs, refusingDaySaves: true)))

        await state.addDay()

        #expect(state.writeFailed)
        #expect(state.days.isEmpty)
        #expect(try await stack.routines.routines(includingDeleted: false).isEmpty)
        #expect(try await stack.programs.programs(includingDeleted: false).isEmpty)
        #expect(try await stack.programs.currentRun() == nil)
    }

    /// The same rule one command over, and the one place the week is NOT taken back: the second
    /// day of an existing week failing leaves that week alone, because the lifter did ask for it.
    @Test("a refused day on a week that already exists takes back only the routine")
    func aRefusedSecondDayKeepsTheWeek() async throws {
        let stack = InMemoryRepositoryStack()
        await opened(weekEditor(over: stack)).addDay()
        let state = await opened(
            weekEditor(
                over: stack,
                routines: stack.routines,
                programs: FlakyProgramRepository(stack.programs, refusingDaySaves: true)))

        await state.addDay()

        #expect(state.writeFailed)
        #expect(state.days.count == 1)
        // The first day's routine, and no second one orphaned beside it.
        #expect(try await stack.routines.routines(includingDeleted: false).count == 1)
        #expect(try await stack.programs.currentRun() != nil)
    }

    /// `writeCopy`'s stated rollback, which nothing exercised: the routine row lands first by
    /// necessity, so a store that refuses a slot would otherwise leave a routine nothing names.
    @Test("a duplicate that fails part-way leaves no half-copied day behind")
    func aRefusedDuplicateLeavesNoCopy() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let setUp = await opened(weekEditor(over: stack))
        await setUp.addDay()
        await setUp.addExercise(id: squat.id)
        let dayID = try #require(setUp.days.first?.id)

        let state = await opened(
            weekEditor(
                over: stack,
                routines: FlakyRoutineRepository(stack.routines, refusingSlotSaves: true),
                programs: stack.programs))
        await state.duplicateDay(dayID)

        #expect(state.writeFailed)
        #expect(state.days.count == 1)
        #expect(try await stack.routines.routines(includingDeleted: false).count == 1)
    }

    @Test("a read that fails is recoverable")
    func aFailedReadReloads() async throws {
        let stack = InMemoryRepositoryStack()
        // A week with a day in it, so the read has a routine to walk before it can fail.
        await opened(weekEditor(over: stack)).addDay()

        let flaky = FlakyRoutineRepository(stack.routines, refusingReads: 1)
        let state = await opened(
            weekEditor(over: stack, routines: flaky, programs: stack.programs))
        guard case .failed = state.phase else {
            Issue.record("expected a failed read, got \(state.phase)")
            return
        }

        await state.reload()
        #expect(state.phase == .ready)
        #expect(state.days.count == 1)
    }

    // MARK: - Q-17.4 (FR-17.10.5)

    /// An edit lands on the plan and on nothing else. A day already started this week keeps the
    /// targets its session copied when it started (`TR-15.3`), so the checklist and the week card
    /// can disagree for that day — drawn, not prevented.
    @Test("a day started this week keeps its planned rows through an edit of the same day")
    func editingAStartedDayLeavesItsPlannedRowsAlone() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await fillTarget(state, weight: "100", reps: "5", sets: "3")
        let run = try #require(try await stack.programs.currentRun())

        // The session a lifter starts on that day, with the plan copied into it.
        let now = Date.now
        let session = WorkoutSession(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            date: now,
            startedAt: now,
            endedAt: nil,
            notes: "",
            bodyweight: nil,
            programRunID: run.id,
            scheduledWorkoutID: nil,
            weekNumber: 1,
            dayIndex: 0)
        try await stack.workouts.save(session)
        let entry = ExerciseEntry(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: squat.id,
            order: 0,
            notes: "")
        try await stack.workouts.save(entry)
        let planned = PlannedTargetGroup(
            id: UUID(),
            createdAt: now,
            updatedAt: now,
            deletedAt: nil,
            exerciseEntryID: entry.id,
            order: 0,
            targetWeight: Weight(grams: 100_000),
            targetReps: 5,
            targetSets: 3)
        try await stack.workouts.save(planned)

        // The edit: the same day, a heavier top set.
        await fillTarget(state, weight: "110", reps: "5", sets: "3")

        let after = try await stack.workouts.plannedTargets(
            forEntryID: entry.id, includingDeleted: false)
        #expect(after.count == 1)
        #expect(after.first?.targetWeight == Weight(grams: 100_000))
        #expect(after.first?.targetReps == 5)
        #expect(after.first?.targetSets == 3)
        #expect(after.first?.id == planned.id)
        // And the plan itself did move, or the test would pass for an edit that did nothing.
        let slotID = try #require(state.days.first?.slots.first?.id)
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: slotID, includingDeleted: false
            ).first?.targetWeight
                == Weight(grams: 110_000))
    }
}
