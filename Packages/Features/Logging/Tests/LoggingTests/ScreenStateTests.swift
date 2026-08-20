import Foundation
import RepositoryInterface
import Testing

@testable import Logging

/// Which state each of this module's two screens shows (`FR-1.13.1`).
///
/// **The decision, not the rendering.** `TR-1.12`'s references are rendered through `ImageRenderer`,
/// which cannot run the `.task` that fills the store, so they picture each state in isolation and
/// say nothing about which one a user is shown. That is the half where the two screens disagreed:
/// both answer a failed read and a workout that has ended with the same `nil` session, and telling
/// them apart is what these tests pin.
@MainActor
@Suite("Screen states")
struct ScreenStateTests {
    // MARK: - The workout's exercises (FR-1.2.2, FR-1.2.13)

    @Test("Nothing is shown until the exercises have been read, whatever else is true")
    func exercisesLoadBeforeTheReadAnswers() {
        #expect(
            SessionExercisesState.current(
                hasLoaded: false, exercises: [], readFailure: "boom", writeFailure: "boom")
                == .loading)
    }

    @Test("A failed read costs the list its cards, and carries no write to report")
    func exercisesReportAFailedRead() {
        // The screen can no longer vouch for what is in the workout, so it shows the state with the
        // retry in it — and it outranks a write failure, which describes a list that is not there.
        #expect(
            SessionExercisesState.current(
                hasLoaded: true, exercises: [], readFailure: "boom", writeFailure: "boom")
                == .readFailed)
    }

    @Test("A failed write keeps every card, which is the opposite of a failed read")
    func exercisesKeepTheCardsThroughAFailedWrite() {
        let card = SessionExercise.stateFixture()

        #expect(
            SessionExercisesState.current(
                hasLoaded: true, exercises: [card], readFailure: nil, writeFailure: "boom")
                == .listed([card], writeFailed: true))
    }

    @Test("A workout with nothing in it is empty, and still reports a failed write")
    func exercisesAreEmpty() {
        #expect(
            SessionExercisesState.current(
                hasLoaded: true, exercises: [], readFailure: nil, writeFailure: nil)
                == .empty(writeFailed: false))
        // The add that failed is why the workout is still empty — reporting nothing would look like
        // the exercise had been chosen and then vanished.
        #expect(
            SessionExercisesState.current(
                hasLoaded: true, exercises: [], readFailure: nil, writeFailure: "boom")
                == .empty(writeFailed: true))
    }

    // MARK: - Train root

    @Test("Nothing is shown until something has looked, whatever else is true")
    func rootLoadsBeforeTheReadAnswers() {
        #expect(
            TrainingHomeState.current(
                hasChecked: false, session: .fixture(), failure: "boom", startWasAttempted: true)
                == .loading)
    }

    @Test("A held workout outranks a failure: a failed write costs the root nothing")
    func rootKeepsTheWorkoutThroughAFailure() {
        let session = WorkoutSession.fixture()

        #expect(
            TrainingHomeState.current(
                hasChecked: true, session: session, failure: "boom", startWasAttempted: false)
                == .inProgress(session))
    }

    @Test("A read that failed takes the whole screen")
    func rootReportsAFailedRead() {
        #expect(
            TrainingHomeState.current(
                hasChecked: true, session: nil, failure: "boom", startWasAttempted: false)
                == .readFailed)
    }

    @Test("A start that failed is reported beside the command, not as a failed read")
    func rootReportsAFailedStartBesideTheCommand() {
        // The store carries one diagnostic for both operations. Reported as a read, this would tell
        // the user their workouts are unreadable and offer a retry that re-reads instead of
        // re-starting — which on success retires the failure and forgets the workout they asked for.
        #expect(
            TrainingHomeState.current(
                hasChecked: true, session: nil, failure: "boom", startWasAttempted: true)
                == .start(showingStartFailure: true))
    }

    @Test("Nothing in progress and nothing wrong is the empty state")
    func rootOffersToStart() {
        #expect(
            TrainingHomeState.current(
                hasChecked: true, session: nil, failure: nil, startWasAttempted: false)
                == .start(showingStartFailure: false))
    }

    @Test("A retired failure takes the start error with it, even after a start was attempted")
    func rootRetiresTheStartFailure() {
        // The screen's flag outlives the diagnostic — a later read clears `failure` and the error
        // must go with it rather than sitting under the button until the screen is left.
        #expect(
            TrainingHomeState.current(
                hasChecked: true, session: nil, failure: nil, startWasAttempted: true)
                == .start(showingStartFailure: false))
    }

    // MARK: - The workout in progress

    @Test("Nothing is announced until something has looked")
    func sessionLoadsBeforeTheReadAnswers() {
        #expect(
            ActiveSessionState.current(hasChecked: false, session: nil, failure: nil) == .loading)
    }

    @Test("A failed write keeps the workout on screen and is reported beside the commands")
    func sessionKeepsTheWorkoutThroughAFailedWrite() {
        let session = WorkoutSession.fixture()

        #expect(
            ActiveSessionState.current(hasChecked: true, session: session, failure: "boom")
                == .inProgress(session, writeFailed: true))
        #expect(
            ActiveSessionState.current(hasChecked: true, session: session, failure: nil)
                == .inProgress(session, writeFailed: false))
    }

    @Test("A read that failed is not the same fact as a workout that ended")
    func sessionDistinguishesAFailedReadFromAnEndedWorkout() {
        // The bug this pins: both answer with a `nil` session, and reporting the first as the second
        // tells a user whose workout is still in progress that it was finished or discarded — with
        // nothing to retry. This screen can be the first thing the app draws (a restored stack), so
        // the read that fails is the one that has found nothing yet.
        #expect(
            ActiveSessionState.current(hasChecked: true, session: nil, failure: "boom")
                == .readFailed)
        #expect(
            ActiveSessionState.current(hasChecked: true, session: nil, failure: nil) == .ended)
    }
}

extension SessionExercise {
    /// One card, with nothing about it varying — these tests are about which state is chosen.
    fileprivate static func stateFixture() -> SessionExercise {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        return SessionExercise(
            entry: ExerciseEntry(
                id: UUID(uuidString: "44444444-4444-4444-8444-444444444444") ?? UUID(),
                createdAt: stamp,
                updatedAt: stamp,
                deletedAt: nil,
                sessionID: UUID(),
                exerciseID: UUID(),
                order: 0,
                notes: ""
            ),
            exercise: nil,
            sets: []
        )
    }
}
