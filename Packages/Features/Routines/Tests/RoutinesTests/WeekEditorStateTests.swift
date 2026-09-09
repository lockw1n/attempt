import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

/// `FR-17.10`'s screen, as the decisions it makes rather than as the picture it draws
/// (`docs/phase-1/tasks.md` §2). What it draws is `RoutineSnapshotTests`', and what it does in
/// place is the simulator run's.
@MainActor
@Suite("Week editor")
struct WeekEditorStateTests {
    // MARK: - A week that does not exist yet (FR-17.10.2, FR-17.10.3, DOD-17.9)

    @Test("with no run the screen is ready to author one, and writes nothing until asked")
    func emptyWeekIsReady() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        #expect(state.phase == .ready)
        #expect(state.days.isEmpty)
        // The name field is seeded rather than blank: Train's root draws it as the week's heading.
        #expect(!state.name.isEmpty)
        #expect(try await stack.programs.programs(includingDeleted: true).isEmpty)
        #expect(try await stack.programs.currentRun() == nil)
    }

    @Test("the first day written starts the run at week 1 and makes it current")
    func firstWriteStartsTheRun() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()

        let run = try #require(try await stack.programs.currentRun())
        #expect(run.weekNumber == 1)
        #expect(run.endedAt == nil)
        let programs = try await stack.programs.programs(includingDeleted: false)
        #expect(programs.count == 1)
        #expect(run.programID == programs.first?.id)
    }

    @Test("saving the name before any day exists writes the program and starts its run")
    func savingTheNameStartsTheRun() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        state.name = "Squat block"
        await state.saveName()

        let run = try #require(try await stack.programs.currentRun())
        let program = try #require(
            try await stack.programs.program(
                id: run.programID, includingDeleted: false))
        #expect(program.name == "Squat block")
        #expect(run.weekNumber == 1)
    }

    /// `DOD-17.9`'s Plan-your-week half, as far as this module can see it: `WeekState` reads the
    /// run, the program and the days in order, and all three are what a re-read finds here.
    @Test("Plan your week, three days, back: a run at week 1 over three days in order")
    func threeDaysInOrder() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addDay()
        await state.addDay()

        let run = try #require(try await stack.programs.currentRun())
        let days = try await stack.programs.days(forProgramID: run.programID, includingDeleted: false)
        #expect(days.map(\.order) == [0, 1, 2])
        for day in days {
            #expect(try await stack.routines.routine(id: day.routineID, includingDeleted: false) != nil)
        }
        #expect(state.days.count == 3)
    }

    @Test("an empty name is refused and nothing is written")
    func emptyNameIsRefused() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        state.name = "   "
        await state.saveName()

        #expect(state.nameRequired)
        #expect(try await stack.programs.programs(includingDeleted: true).isEmpty)
    }

    @Test("a name typed and not saved survives the re-read a day write causes")
    func unsavedNameSurvivesAWrite() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        state.name = "Halfway typed"
        await state.addDay()

        #expect(state.name == "Halfway typed")
        // And it is still a draft: the program was written under the seeded name.
        let run = try #require(try await stack.programs.currentRun())
        let program = try #require(
            try await stack.programs.program(
                id: run.programID, includingDeleted: false))
        #expect(program.name != "Halfway typed")
    }

    // MARK: - Days (FR-17.10.4, FR-15.2.5)

    @Test("a day is renamed, and an empty name renames nothing")
    func renamingADay() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        let dayID = try #require(state.days.first?.id)

        await state.renameDay(dayID, to: "  Heavy squat  ")
        #expect(state.days.first?.name == "Heavy squat")

        await state.renameDay(dayID, to: "   ")
        #expect(state.nameRequired)
        #expect(state.days.first?.name == "Heavy squat")
    }

    @Test("a duplicated day copies its exercises and their targets and lands next to it")
    func duplicatingADay() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addDay()
        let firstID = try #require(state.days.first?.id)
        state.openDayID = firstID
        await state.addExercise(id: squat.id)
        await fillTarget(state, weight: "180", reps: "3", sets: "5")

        await state.duplicateDay(firstID)

        #expect(state.days.count == 3)
        // Directly after the original, not at the end.
        #expect(state.days[1].slots.count == 1)
        #expect(state.days[2].slots.isEmpty)
        let copy = state.days[1]
        #expect(copy.routineID != state.days[0].routineID)
        let slots = try await stack.routines.exercises(
            forRoutineID: copy.routineID, includingDeleted: false)
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: try #require(slots.first).id, includingDeleted: false)
        #expect(groups.map(\.targetReps) == [3])
        #expect(groups.map(\.targetSets) == [5])
        #expect(groups.first?.targetWeight == Weight(grams: 180_000))
        // New identifiers at every level, or one day's edit would be the other's.
        #expect(groups.first?.id != state.days[0].slots.first?.groups.first?.id)
    }

    @Test("a removed day leaves the week and the ones after it close the gap")
    func removingADay() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addDay()
        await state.addDay()
        let secondID = try #require(state.days[1].id as UUID?)
        let thirdID = state.days[2].id

        await state.removeDay(secondID)

        #expect(state.days.map(\.id) == [state.days[0].id, thirdID])
        let run = try #require(try await stack.programs.currentRun())
        let days = try await stack.programs.days(forProgramID: run.programID, includingDeleted: false)
        #expect(days.map(\.order) == [0, 1])
        // Soft, so the row is still there (`G-1.3`).
        let all = try await stack.programs.days(forProgramID: run.programID, includingDeleted: true)
        #expect(all.count == 3)
    }

    @Test("a day moves up and down, and the ends refuse")
    func movingADay() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addDay()
        await state.addDay()
        let names = state.days.map(\.name)

        await state.moveDay(at: 2, by: -1)
        #expect(state.days.map(\.name) == [names[0], names[2], names[1]])

        await state.moveDay(at: 0, by: -1)
        #expect(state.days.map(\.name) == [names[0], names[2], names[1]])

        let run = try #require(try await stack.programs.currentRun())
        let days = try await stack.programs.days(forProgramID: run.programID, includingDeleted: false)
        #expect(days.map(\.order) == [0, 1, 2])
    }

    @Test("a day whose routine has been archived is kept and drawn nameless")
    func archivedRoutineKeepsItsDay() async throws {
        let stack = InMemoryRepositoryStack()
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        let routineID = try #require(state.days.first?.routineID)
        try await stack.routines.deleteRoutine(id: routineID)

        await state.load()

        #expect(state.days.count == 1)
        #expect(state.days.first?.name == nil)
    }

    // MARK: - Exercises

    @Test("an exercise is added to the day that is open, and written at once")
    func addingAnExercise() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        let routineID = try #require(state.days.first?.routineID)

        await state.addExercise(id: squat.id)

        #expect(state.days.first?.slots.count == 1)
        #expect(state.days.first?.slots.first?.name == "Back Squat")
        // One empty group, and it is in no table until it resolves.
        #expect(state.days.first?.slots.first?.groups.count == 1)
        let stored = try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        #expect(stored.map(\.exerciseID) == [squat.id])
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: try #require(stored.first).id, includingDeleted: false
            ).isEmpty)
    }

    @Test("with no day open the chooser's selection is refused rather than misfiled")
    func addingWithNoDayOpen() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        state.openDayID = nil

        await state.addExercise(id: squat.id)

        #expect(state.days.first?.slots.isEmpty == true)
    }

    @Test("exercises reorder and a removed one takes its targets with it")
    func reorderingAndRemovingExercises() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let press = routineExerciseFixture(name: "Overhead Press")
        let stack = try await seededStack([squat, press])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await state.addExercise(id: press.id)
        await fillTarget(state, slot: 1)
        let routineID = try #require(state.days.first?.routineID)

        await state.moveSlot(1, by: -1, inDayAt: 0)
        #expect(state.days.first?.slots.map(\.exerciseID) == [press.id, squat.id])
        var stored = try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        #expect(stored.map(\.exerciseID) == [press.id, squat.id])
        #expect(stored.map(\.order) == [0, 1])

        await state.removeSlot(0, inDayAt: 0)
        #expect(state.days.first?.slots.map(\.exerciseID) == [squat.id])
        stored = try await stack.routines.exercises(forRoutineID: routineID, includingDeleted: false)
        #expect(stored.map(\.order) == [0])
    }
}

/// The write-through half of `FR-17.10.1`, and `Q-17.4`'s answer — a second suite rather than a
/// longer one, the first being the week's own shape.
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

    @Test("a second target reorders and removes, and one never stored is dropped silently")
    func reorderingAndRemovingTargets() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let state = await opened(weekEditor(over: stack))
        await state.addDay()
        await state.addExercise(id: squat.id)
        await fillTarget(state, group: 0, weight: "180", reps: "3", sets: "1")
        state.addTarget(toSlot: 0, inDayAt: 0)
        await fillTarget(state, group: 1, weight: "150", reps: "8", sets: "3")
        let slotID = try #require(state.days.first?.slots.first?.id)

        await state.moveTarget(1, by: -1, inSlot: 0, inDayAt: 0)
        var stored = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(stored.map(\.targetReps) == [8, 3])
        #expect(stored.map(\.order) == [0, 1])

        // A group added and never filled in is in no table, so removing it must not report a
        // failure over a row that was never written.
        state.addTarget(toSlot: 0, inDayAt: 0)
        await state.removeTarget(2, inSlot: 0, inDayAt: 0)
        #expect(state.writeFailed == false)
        #expect(state.days.first?.slots.first?.groups.count == 2)

        await state.removeTarget(0, inSlot: 0, inDayAt: 0)
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

    @Test("a day the store will not take says so and adds nothing")
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
