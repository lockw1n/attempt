import Foundation
import PowerliftingCore
import RepositoryInterface
import Testing

@testable import Logging

/// Where a resumed workout opens (`FR-16.6.1`).
@Suite("Resuming a workout")
struct SessionResumeTests {
    @Test("A resumed workout scrolls to the first exercise still to do")
    func firstUnfinishedIsTheTarget() {
        let exercises = [
            SessionExercise.resumeFixture(index: 0, isDone: true),
            SessionExercise.resumeFixture(index: 1, isDone: true),
            SessionExercise.resumeFixture(index: 2, isDone: false),
            SessionExercise.resumeFixture(index: 3, isDone: false),
        ]

        #expect(SessionResumeTarget.exerciseInProgress(in: exercises) == exercises[2].id)
    }

    @Test("The lifter's check-off counts, not only the sets")
    func aCheckedOffExerciseIsPassedOver() {
        // `FR-15.3.4`: three of five sets can be enough for the day. Walking the sets instead would
        // send a resumed session back to work its owner has already dismissed.
        let exercises = [
            SessionExercise.resumeFixture(index: 0, isDone: false, isMarkedDone: true),
            SessionExercise.resumeFixture(index: 1, isDone: false),
        ]

        #expect(SessionResumeTarget.exerciseInProgress(in: exercises) == exercises[1].id)
    }

    @Test("Nothing done yet is no scroll at all")
    func theFirstExerciseIsNotScrolledTo() {
        // The screen already opens on the first card. Scrolling to it would push the workout's own
        // line off the top to reach something that was in view — a jump with nothing gained, on the
        // ordinary path where a lifter has done nothing yet.
        let exercises = [
            SessionExercise.resumeFixture(index: 0, isDone: false),
            SessionExercise.resumeFixture(index: 1, isDone: true),
        ]

        #expect(SessionResumeTarget.exerciseInProgress(in: exercises) == nil)
    }

    @Test("A workout with everything done scrolls nowhere")
    func everythingDoneIsNoScroll() {
        // There is no exercise in progress to return to, and what is wanted then is **Finish** —
        // which is the foot of the screen rather than a card.
        let exercises = [
            SessionExercise.resumeFixture(index: 0, isDone: true),
            SessionExercise.resumeFixture(index: 1, isDone: true),
        ]

        #expect(SessionResumeTarget.exerciseInProgress(in: exercises) == nil)
    }

    @Test("A workout with nothing in it scrolls nowhere")
    func anEmptyWorkoutIsNoScroll() {
        #expect(SessionResumeTarget.exerciseInProgress(in: []) == nil)
    }
}

extension SessionExercise {
    /// One card, varying only in whether it is finished — which is the whole of what the target
    /// reads.
    ///
    /// - Parameters:
    ///   - index: Its place in the workout, which also fixes its identifiers.
    ///   - isDone: Whether its work is finished, expressed as a completed working set.
    ///   - isMarkedDone: Whether the lifter checked it off (`FR-15.3.4`).
    /// - Returns: The card.
    fileprivate static func resumeFixture(
        index: Int,
        isDone: Bool,
        isMarkedDone: Bool = false
    ) -> SessionExercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let entryID = UUID(uuidString: "4444444\(index)-4444-4444-8444-444444444444") ?? UUID()
        return SessionExercise(
            entry: ExerciseEntry(
                id: entryID,
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: index,
                notes: "",
                isMarkedDone: isMarkedDone
            ),
            exercise: nil,
            sets: [
                SetEntry(
                    id: UUID(uuidString: "5555555\(index)-5555-4555-8555-555555555555") ?? UUID(),
                    createdAt: stamp,
                    updatedAt: stamp,
                    deletedAt: nil,
                    entryID: entryID,
                    order: 0,
                    weight: Weight(grams: 100_000),
                    reps: 5,
                    rpe: nil,
                    rir: nil,
                    isWarmup: false,
                    isCompleted: isDone,
                    targetWeight: nil,
                    targetReps: nil,
                    modifiers: [],
                    notes: "",
                    completedAt: stamp
                )
            ]
        )
    }
}
