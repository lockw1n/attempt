import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import ExerciseLibrary

/// Which exercises the form will offer as the one this exercise varies (`FR-1.1.7`).
///
/// Its own suite because its subject is a *filter* rather than a write: every claim here is about
/// which rows come back, and the four exclusions are each a save the store would otherwise be asked
/// to make — one of them, a cycle, being a save nothing in the repository refuses.
@MainActor
@Suite("Exercise form parent picker")
struct ExerciseFormParentTests {
    @Test("An exercise is never offered as its own parent")
    func selfIsNotACandidate() async {
        let state = await FormFixtures.editing(
            DetailFixtures.backSquat, offeringEveryMovement: true)
        #expect(!state.parentCandidates.contains { $0.id == DetailFixtures.backSquat.id })
    }

    @Test("An exercise's own descendants are never offered as its parent")
    func descendantsAreNotCandidates() async {
        // Front Squat varies Back Squat; this one varies Front Squat. Offering either as Back
        // Squat's parent would write a cycle, which nothing in the repository refuses.
        let grandchild = DetailFixtures.exercise(
            id: DetailFixtures.identifier("7"),
            name: "Front Squat, paused",
            movement: .squat,
            parentExerciseID: DetailFixtures.frontSquat.id
        )
        let state = await FormFixtures.editing(
            DetailFixtures.backSquat, extra: [grandchild], offeringEveryMovement: true)
        let offered = state.parentCandidates.map(\.name)
        #expect(!offered.contains("Front Squat"))
        #expect(!offered.contains("Front Squat, paused"))
        #expect(offered.contains("Bench Press"))
    }

    @Test("An archived exercise is not offered as a parent (FR-1.1.5)")
    func archivedExercisesAreNotCandidates() async {
        let retired = DetailFixtures.exercise(
            id: DetailFixtures.identifier("8"),
            name: "Retired Squat",
            movement: .squat,
            isArchived: true
        )
        let state = await FormFixtures.creating(extra: [retired])
        state.movement = .squat
        #expect(!state.parentCandidates.contains { $0.name == "Retired Squat" })
    }

    @Test("The parent already stored is offered even when nothing else would offer it")
    func theStoredParentSurvivesEveryExclusion() async {
        let retired = DetailFixtures.exercise(
            id: DetailFixtures.identifier("8"),
            name: "Retired Squat",
            movement: .squat,
            isArchived: true
        )
        let child = DetailFixtures.exercise(
            id: DetailFixtures.identifier("9"),
            name: "Retired Squat, wide",
            movement: .squat,
            parentExerciseID: retired.id
        )
        let state = await FormFixtures.editing(child, extra: [retired, child])
        // Losing it here would silently orphan the variation on the next save.
        #expect(state.parentCandidates.map(\.name).contains("Retired Squat"))
        #expect(state.selectedParent?.name == "Retired Squat")
    }

    @Test("The picker offers this movement's exercises, and widens on request")
    func candidatesFollowTheSelectedMovement() async {
        let state = await FormFixtures.creating()
        state.movement = .squat
        #expect(state.parentCandidates.map(\.name) == ["Back Squat", "Front Squat", "Pause Squat"])

        state.offersEveryMovementAsParent = true
        #expect(state.parentCandidates.map(\.name).contains("Bench Press"))
    }

    @Test("Changing the movement changes what the picker offers")
    func candidatesFollowAChangeOfMovement() async {
        let state = await FormFixtures.creating()
        state.movement = .bench
        #expect(state.parentCandidates.map(\.name) == ["Bench Press"])
    }

    @Test("Candidates are in reader order, not read order")
    func candidatesAreOrdered() async {
        let state = await FormFixtures.creating()
        state.movement = .squat
        // The catalogue is handed over shuffled; `ExerciseOrder` is what puts these in this order.
        #expect(state.parentCandidates.map(\.name) == ["Back Squat", "Front Squat", "Pause Squat"])
    }

    @Test("A form opened on a variation of another movement opens with the picker widened")
    func aCrossMovementParentOpensWidened() async {
        let crossMovement = DetailFixtures.exercise(
            id: DetailFixtures.identifier("A"),
            name: "Squat Grip Bench",
            movement: .bench,
            parentExerciseID: DetailFixtures.backSquat.id
        )
        let state = await FormFixtures.editing(crossMovement, extra: [crossMovement])
        // Without this the parent disappears from the picker the moment the form opens, which
        // reads as the form having dropped it.
        #expect(state.offersEveryMovementAsParent)
        #expect(state.selectedParent?.name == "Back Squat")
    }

    @Test("A form opened on a root exercise does not widen the picker for nothing")
    func aRootExerciseOpensNarrowed() async {
        let state = await FormFixtures.editing(DetailFixtures.benchPress)
        #expect(state.offersEveryMovementAsParent == false)
        #expect(state.selectedParent == nil)
    }
}

/// The forms these tests drive, over `DetailFixtures`' catalogue.
enum FormFixtures {
    /// A create form, already read.
    ///
    /// - Parameters:
    ///   - extra: Rows beyond the catalogue.
    ///   - writeError: What every save fails with, for the tests about a failed write.
    /// - Returns: The form, ready.
    static func creating(
        extra: [Exercise] = [],
        writeError: RepositoryError? = nil
    ) async -> ExerciseFormState {
        let state = ExerciseFormState(
            mode: .create,
            repository: ScriptedExerciseRepository(
                exercises: DetailFixtures.catalogue + extra, writeError: writeError)
        )
        await state.load()
        return state
    }

    /// An edit form over `exercise`, already read.
    ///
    /// - Parameters:
    ///   - exercise: The record being edited. Added to the catalogue unless `extra` already has it.
    ///   - extra: Rows beyond the catalogue.
    ///   - offeringEveryMovement: Whether to widen the parent picker before the assertions run.
    /// - Returns: The form, ready.
    static func editing(
        _ exercise: Exercise,
        extra: [Exercise] = [],
        offeringEveryMovement: Bool = false
    ) async -> ExerciseFormState {
        let rows = DetailFixtures.catalogue + extra
        let state = ExerciseFormState(
            mode: .edit(exerciseID: exercise.id),
            repository: ScriptedExerciseRepository(
                exercises: rows.contains(where: { $0.id == exercise.id }) ? rows : rows + [exercise])
        )
        await state.load()
        state.offersEveryMovementAsParent =
            offeringEveryMovement || state.offersEveryMovementAsParent
        return state
    }

    /// Logs one completed set against `exerciseID` — a session, an entry and a set, in the order the
    /// repository's referential integrity requires.
    ///
    /// - Parameters:
    ///   - exerciseID: The exercise the set is logged against.
    ///   - stack: The store to write into.
    static func logASet(against exerciseID: UUID, in stack: InMemoryRepositoryStack) async throws {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let session = WorkoutSession(
            id: DetailFixtures.identifier("B"),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            date: moment,
            startedAt: moment,
            endedAt: moment,
            notes: "",
            bodyweight: nil,
            programRunID: nil,
            scheduledWorkoutID: nil
        )
        try await stack.workouts.save(session)
        let entry = ExerciseEntry(
            id: DetailFixtures.identifier("C"),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            sessionID: session.id,
            exerciseID: exerciseID,
            order: 0,
            notes: ""
        )
        try await stack.workouts.save(entry)
        let set = SetEntry(
            id: DetailFixtures.identifier("D"),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            entryID: entry.id,
            order: 0,
            weight: Weight(grams: 140_000),
            reps: 5,
            rpe: nil,
            rir: nil,
            isWarmup: false,
            isCompleted: true,
            targetWeight: nil,
            targetReps: nil,
            modifiers: [],
            notes: "",
            completedAt: moment
        )
        try await stack.workouts.save(set)
    }
}
