import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Routines

/// What the editor does ACROSS screens and across failures, rather than to one draft.
///
/// A suite of its own because the store is the app's rather than the screen's (`TR-1.2`), which is
/// the one thing about this editor that no other screen in the project has to reason about: which
/// screen a draft belongs to, and what a write that failed part-way leaves behind.
@MainActor
@Suite("Routine editor lifecycle")
struct RoutineEditorLifecycleTests {
    // The editor writes nothing on the way out, so a draft the lifter backed out of is still in
    // this app-lifetime store when they tap the same routine again. Handing it back would show
    // them edits they had abandoned — over a list still showing the stored version, with the save
    // command armed over the difference.
    @Test("A draft abandoned without saving does not come back on the next push")
    func abandonedEditDoesNotComeBack() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create, screen: UUID())
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        fillFirstGroup(author, slot: 0)
        await author.save()
        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)

        let store = editor(over: stack)
        await store.open(.edit(routineID: routineID), screen: UUID())
        #expect(store.name == "Squat day")

        // Renamed, emptied, and backed out of without a save.
        store.name = "Totally different"
        store.removeSlot(at: 0)

        // The same row tapped again: a new screen, so a new token.
        await store.open(.edit(routineID: routineID), screen: UUID())
        #expect(store.name == "Squat day", "the abandoned rename must not survive")
        #expect(store.slots.count == 1, "nor the abandoned removal")
    }

    // The other direction, and the reason the token exists rather than an unconditional read:
    // SwiftUI re-runs `.task` whenever the view's identity is re-established — the exercise
    // chooser being pushed over this screen and popped again — and a read there would throw away
    // everything typed since the first.
    @Test("A re-run of the same screen's task keeps what has been typed")
    func theSameScreenKeepsItsDraft() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        let screen = UUID()
        await author.open(.create, screen: screen)
        author.name = "Squat day"
        await author.addExercise(id: squat.id)

        await author.open(.create, screen: screen)
        #expect(author.name == "Squat day")
        #expect(author.slots.count == 1)
    }

    // A delete is the one write in a save that is not an upsert: the repository refuses a second
    // delete of a row it has already reclaimed. A save whose delete phase fails part-way therefore
    // has to remember which deletes landed, or every retry throws on the first of them and the
    // routine can never be saved again.
    @Test("A save whose delete phase fails part-way finishes on the retry")
    func aPartlyFailedDeletePhaseFinishesOnTheRetry() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let press = routineExerciseFixture(name: "Bench Press")
        let stack = try await seededStack([squat, press])
        let author = editor(over: stack)
        await author.open(.create, screen: UUID())
        author.name = "Two lifts"
        await author.addExercise(id: squat.id)
        await author.addExercise(id: press.id)
        fillFirstGroup(author, slot: 0)
        fillFirstGroup(author, slot: 1)
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        // The second slot delete is refused, the first of the two having already landed.
        let flaky = FlakyRoutineRepository(stack.routines, refusingSlotDelete: 2)
        let editing = editor(over: stack, routines: flaky)
        await editing.open(.edit(routineID: routineID), screen: UUID())
        #expect(editing.slots.count == 2)
        editing.removeSlot(at: 1)
        editing.removeSlot(at: 0)

        await editing.save()
        #expect(editing.writeFailure != nil, "the refused delete is reported")
        #expect(!editing.didSave)

        await editing.save()
        #expect(editing.writeFailure == nil, "the retry must not trip over the delete that landed")
        #expect(editing.didSave)
        #expect(
            try await stack.routines.exercises(forRoutineID: routineID, includingDeleted: false)
                .isEmpty)
    }

    // FR-1.13.1's error state on this screen, and the retry beside it. A failed read is
    // RECOVERABLE, unlike an identifier that resolved to nothing — which is why one of the two
    // draws a retry and the other does not.
    @Test("A failed read is a recoverable phase, and reload() recovers from it")
    func aFailedReadIsRecoverable() async throws {
        let squat = routineExerciseFixture(name: "Back Squat")
        let stack = try await seededStack([squat])
        let author = editor(over: stack)
        await author.open(.create, screen: UUID())
        author.name = "Squat day"
        await author.addExercise(id: squat.id)
        fillFirstGroup(author, slot: 0)
        await author.save()

        let routineID = try #require(
            try await stack.routines.routines(includingDeleted: false).first?.id)
        let flaky = FlakyRoutineRepository(stack.routines, refusingReads: 1)
        let editing = editor(over: stack, routines: flaky)
        await editing.open(.edit(routineID: routineID), screen: UUID())
        guard case .failed(let diagnostic) = editing.phase else {
            Issue.record("expected a failed phase, got \(editing.phase)")
            return
        }
        #expect(!diagnostic.isEmpty)
        #expect(editing.slots.isEmpty)

        await editing.reload()
        #expect(editing.phase == .ready)
        #expect(editing.name == "Squat day")
        #expect(editing.slots.count == 1)

        // From any phase but `.failed` it is a no-op: the retry belongs to the error state alone,
        // and a reload from `.ready` would throw away a draft nobody asked it to.
        editing.name = "Edited"
        await editing.reload()
        #expect(editing.name == "Edited")
    }
}
