import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

@MainActor
@Suite("Routine editor")
struct RoutineEditorStateTests {
    @Test("A routine with a multi-group exercise round-trips through the store")
    func multiGroupRoundTrip() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Heavy squat day"
        await author.addExercise(id: squat.id)
        author.updateGroup(at: 0, inSlotAt: 0) { group in
            group.weightText = "100"
            group.repsText = "5"
            group.setsText = "3"
        }
        author.addGroup(toSlotAt: 0)
        author.updateGroup(at: 1, inSlotAt: 0) { group in
            group.weightText = "90"
            group.repsText = "8"
            group.setsText = "2"
        }
        #expect(author.canSave)
        await author.save()
        #expect(author.writeFailure == nil)
        #expect(author.didSave)

        let stored = try await stack.routines.routines(includingDeleted: false)
        #expect(stored.count == 1)
        let routineID = try #require(stored.first?.id)
        #expect(stored.first?.name == "Heavy squat day")

        let reader = editor(over: stack)
        await reader.open(.edit(routineID: routineID))
        #expect(reader.phase == .ready)
        #expect(reader.name == "Heavy squat day")
        #expect(reader.slots.count == 1)
        #expect(reader.slots.first?.exerciseID == squat.id)
        #expect(reader.slots.first?.name == "Back Squat")
        #expect(reader.slots.first?.groups.map(\.weightText) == ["100", "90"])
        #expect(reader.slots.first?.groups.map(\.repsText) == ["5", "8"])
        #expect(reader.slots.first?.groups.map(\.setsText) == ["3", "2"])
    }

    // FR-15.2.2. Blank is the empty field on the way in and on the way back out, and the stored
    // column is `nil` rather than zero — which is the whole distinction, since a zero would
    // re-open as "0" and read as a plan to lift nothing.
    @Test("A blank target stores no weight and re-reads as blank")
    func blankTargetRoundTrips() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        author.updateGroup(at: 0, inSlotAt: 0) { group in
            group.repsText = "5"
            group.setsText = "5"
        }
        #expect(author.canSave, "a blank weight must not block a save")
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        let slotID = try #require(
            try await stack.routines.exercises(forRoutineID: routineID, includingDeleted: false)
                .first?.id)
        let groups = try await stack.routines.targetGroups(
            forRoutineExerciseID: slotID, includingDeleted: false)
        #expect(groups.count == 1)
        #expect(groups.first?.targetWeight == nil)
        #expect(groups.first?.prescription == nil)
        #expect(groups.first?.targetReps == 5)
        #expect(groups.first?.targetSets == 5)

        let reader = editor(over: stack)
        await reader.open(.edit(routineID: routineID))
        #expect(reader.slots.first?.groups.first?.weightText.isEmpty == true)
        #expect(reader.slots.first?.groups.first?.isBlankWeight == true)
    }

    // The other half of the same requirement: a weight the lifter actually entered as zero is
    // stored as zero and comes back as a number, so nothing collapses the two.
    @Test("A target weight of zero is stored and re-read as zero, not as blank")
    func zeroTargetIsNotBlank() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Bar work"
        await author.addExercise(id: squat.id)
        author.updateGroup(at: 0, inSlotAt: 0) { group in
            group.weightText = "0"
            group.repsText = "10"
            group.setsText = "2"
        }
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        let slotID = try #require(
            try await stack.routines.exercises(forRoutineID: routineID, includingDeleted: false)
                .first?.id)
        let group = try #require(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: slotID, includingDeleted: false
            ).first)
        #expect(group.targetWeight == Weight(grams: 0))
        #expect(group.prescription == .fixedWeight(Weight(grams: 0)))

        let reader = editor(over: stack)
        await reader.open(.edit(routineID: routineID))
        #expect(reader.slots.first?.groups.first?.isBlankWeight == false)
        #expect(reader.slots.first?.groups.first?.weightText == "0")
    }

    @Test("Reordering exercises rewrites their stored order")
    func reorderingRewritesOrder() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let press = routineExerciseFixture(name: "Bench Press")
        let stack = try await seededStack([squat, press])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Two lifts"
        await author.addExercise(id: squat.id)
        await author.addExercise(id: press.id)
        fill(author, slot: 0)
        fill(author, slot: 1)
        author.moveSlotDown(0)
        #expect(author.slots.map(\.exerciseID) == [press.id, squat.id])
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        let slots = try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        #expect(slots.map(\.exerciseID) == [press.id, squat.id])
        #expect(slots.map(\.order) == [0, 1])
    }

    @Test("Removing an exercise soft-deletes the stored slot and its groups")
    func removingAnExerciseDeletesIt() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let press = routineExerciseFixture(name: "Bench Press")
        let stack = try await seededStack([squat, press])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Two lifts"
        await author.addExercise(id: squat.id)
        await author.addExercise(id: press.id)
        fill(author, slot: 0)
        fill(author, slot: 1)
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        let editing = editor(over: stack)
        await editing.open(.edit(routineID: routineID))
        let removedSlotID = try #require(editing.slots.first?.id)
        editing.removeSlot(at: 0)
        await editing.save()
        #expect(editing.writeFailure == nil)

        let live = try await stack.routines.exercises(
            forRoutineID: routineID, includingDeleted: false)
        #expect(live.map(\.exerciseID) == [press.id])
        #expect(
            try await stack.routines.targetGroups(
                forRoutineExerciseID: removedSlotID, includingDeleted: false
            ).isEmpty)
    }

    // The store refuses a delete of a row it never held, so a slot added and dropped inside one
    // editing session must not reach one — the tidy-up would fail the whole save.
    @Test("An exercise added and removed before the first save costs the save nothing")
    func addingAndRemovingBeforeSavingIsSilent() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Empty plan"
        await author.addExercise(id: squat.id)
        author.removeSlot(at: 0)
        await author.save()

        #expect(author.writeFailure == nil)
        #expect(author.didSave)
        #expect(try await stack.routines.routines(includingDeleted: false).count == 1)
    }

    @Test("A group missing its reps or sets blocks the save")
    func incompleteGroupBlocksTheSave() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        author.updateGroup(at: 0, inSlotAt: 0) { $0.repsText = "5" }
        #expect(!author.everyGroupResolves)
        #expect(!author.canSave)

        author.updateGroup(at: 0, inSlotAt: 0) { $0.setsText = "3" }
        #expect(author.everyGroupResolves)
        #expect(author.canSave)
    }

    @Test("A load that is not a number blocks the save, where an empty one does not")
    func unparseableWeightBlocksTheSave() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        author.updateGroup(at: 0, inSlotAt: 0) { group in
            group.weightText = "1o0"
            group.repsText = "5"
            group.setsText = "3"
        }
        #expect(!author.canSave)

        author.updateGroup(at: 0, inSlotAt: 0) { $0.weightText = "" }
        #expect(author.canSave)
    }

    @Test("A routine with no name cannot be saved")
    func nameIsRequired() async throws {
        let stack = InMemoryRepositoryStack()
        let author = editor(over: stack)
        await author.open(.create)
        #expect(!author.canSave)
        author.name = "   "
        #expect(!author.canSave, "whitespace is not a name")
        author.name = "Squat day"
        #expect(author.canSave)
    }

    @Test("An identifier that names no routine is missing rather than failed")
    func missingRoutine() async throws {
        let stack = InMemoryRepositoryStack()
        let author = editor(over: stack)
        await author.open(.edit(routineID: UUID()))
        #expect(author.phase == .missing)
    }

    // The store outlives the screen, so opening the same routine after a save has to read again
    // rather than hand back a draft that would dismiss the screen on sight.
    @Test("Re-opening a saved routine reads it again")
    func reopeningAfterASaveReads() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create)
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        fill(author, slot: 0)
        await author.save()
        #expect(author.didSave)

        await author.open(.create)
        #expect(!author.didSave)
        #expect(author.name.isEmpty)
        #expect(author.slots.isEmpty)
    }

    /// Fills a slot's first group with something storable, for the tests that are about the slots
    /// rather than about the numbers in them.
    private func fill(_ state: RoutineEditorState, slot index: Int) {
        state.updateGroup(at: 0, inSlotAt: index) { group in
            group.weightText = "100"
            group.repsText = "5"
            group.setsText = "3"
        }
    }
}
