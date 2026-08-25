import Foundation
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// `FR-1.2.9`'s session note: the field's own rules, and the write behind it (`NFR-1.8`, `G-2.4`).
///
/// The happy paths run against `RepositoryFakes`; the failures run against
/// `ScriptedWorkoutRepository`, which a faithful fake will not produce.
@Suite("Session notes")
struct SessionNoteTests {
    // MARK: - The field (FR-1.2.9)

    @Test("A first read fills the field from the record")
    func firstReadFillsTheField() {
        var draft = SessionNoteDraft()

        draft.follow(WorkoutSession.fixture().withNotes("felt heavy"))

        #expect(draft.text == "felt heavy")
        #expect(!draft.hasUnsavedChanges)
    }

    @Test("Re-reading the same workout keeps an edit that has not been saved")
    func rereadKeepsAnUnsavedEdit() {
        // The screen re-reads on every appearance. A read that overwrote the field would drop what
        // had been typed since, silently, along with the only sign it existed.
        let session = WorkoutSession.fixture().withNotes("stored")
        var draft = SessionNoteDraft()
        draft.follow(session)
        draft.text = "typed"

        draft.follow(session)

        #expect(draft.text == "typed")
        #expect(draft.hasUnsavedChanges)
    }

    @Test("Re-reading takes a note that changed elsewhere, where nothing is being typed")
    func rereadTakesTheRecord() {
        let session = WorkoutSession.fixture().withNotes("stored")
        var draft = SessionNoteDraft()
        draft.follow(session)

        draft.follow(session.withNotes("changed elsewhere"))

        #expect(draft.text == "changed elsewhere")
        #expect(!draft.hasUnsavedChanges)
    }

    @Test("A save the store confirms clears the unsaved edit")
    func confirmedSaveClearsTheEdit() {
        // What the screen does after a write lands: the record comes back carrying the text, so the
        // field and the record agree again and the two commands go away.
        let session = WorkoutSession.fixture().withNotes("stored")
        var draft = SessionNoteDraft()
        draft.follow(session)
        draft.text = "typed"

        draft.follow(session.withNotes("typed"))

        #expect(draft.text == "typed")
        #expect(!draft.hasUnsavedChanges)
    }

    @Test("A different workout replaces the field, edit and all")
    func anotherWorkoutReplacesTheField() {
        // A note is prose about one session. Carried across, it would put what the user wrote about
        // Tuesday into Thursday's record.
        var draft = SessionNoteDraft()
        draft.follow(WorkoutSession.fixture().withNotes("tuesday"))
        draft.text = "half-typed"

        draft.follow(WorkoutSession.fixture(id: UUID()).withNotes("thursday"))

        #expect(draft.text == "thursday")
        #expect(!draft.hasUnsavedChanges)
    }

    @Test("No workout empties the field")
    func noWorkoutEmptiesTheField() {
        var draft = SessionNoteDraft()
        draft.follow(WorkoutSession.fixture().withNotes("tuesday"))

        draft.follow(nil)

        #expect(draft.text.isEmpty)
        #expect(!draft.hasUnsavedChanges)
    }

    @Test("Discarding puts the stored note back")
    func discardRestoresTheRecord() {
        var draft = SessionNoteDraft()
        draft.follow(WorkoutSession.fixture().withNotes("stored"))
        draft.text = "typed"
        #expect(draft.hasUnsavedChanges)

        draft.discard()

        #expect(draft.text == "stored")
        #expect(!draft.hasUnsavedChanges)
    }

    // MARK: - The write (FR-1.2.9, NFR-1.8, G-2.4)

    @Test("A saved note is written through and comes back on the held record")
    func saveWritesThrough() async throws {
        let workout = try await Workout.started()

        await workout.store.saveNote("felt heavy")

        #expect(workout.store.session?.notes == "felt heavy")
        #expect(workout.store.noteWriteFailure == nil)
        // NFR-1.8's claim: in the store, not only on the screen.
        let session = try #require(workout.store.session)
        let stored = try await workout.repositories.workouts.session(
            id: session.id, includingDeleted: false)
        #expect(stored?.notes == "felt heavy")
    }

    @Test("Saving the note the record already carries writes nothing")
    func noOpSaveWritesNothing() async throws {
        // Every save restamps `updatedAt`, which is `G-2.4`'s conflict key — so a local no-op would
        // outrank a real remote edit.
        let workout = try await Workout.started()
        await workout.store.saveNote("felt heavy")
        let stamped = try #require(workout.store.session?.updatedAt)

        await workout.store.saveNote("felt heavy")

        #expect(workout.store.session?.updatedAt == stamped)
        #expect(workout.store.session?.notes == "felt heavy")
    }

    @Test("A note saved with no workout held writes nothing and reports nothing")
    func saveWithNoWorkoutIsSilent() async throws {
        let workout = try await Workout.started()
        await workout.store.finish()
        try #require(workout.store.session == nil)

        await workout.store.saveNote("felt heavy")

        #expect(workout.store.session == nil)
        #expect(workout.store.noteWriteFailure == nil)
    }

    @Test("Finishing a workout keeps the note that was saved into it")
    func finishKeepsTheNote() async throws {
        // The chain's sharpest case in the other direction: the note write rebuilds the whole
        // record, so a finish that ran over it would be the one to lose something.
        let workout = try await Workout.started()
        let session = try #require(workout.store.session)
        await workout.store.saveNote("felt heavy")

        await workout.store.finish()

        let stored = try await workout.repositories.workouts.session(
            id: session.id, includingDeleted: false)
        #expect(stored?.notes == "felt heavy")
        #expect(stored?.endedAt != nil)
    }

    @Test("A failed note write is its own diagnostic, and costs the workout nothing")
    func failedWriteIsReportedApart() async throws {
        let failure = RepositoryError.danglingReference(recordID: UUID(), referencing: UUID())
        let session = WorkoutSession.fixture()
        let store = ActiveSessionStore.overWorkouts(
            ScriptedWorkoutRepository(row: session, writeError: failure))
        await store.adopt(sessionID: session.id)

        await store.saveNote("felt heavy")

        #expect(store.noteWriteFailure == String(describing: failure))
        // Neither of the other two: a failed note leaves the workout and its cards as they were, so
        // the banner beside **Finish** must not appear for it.
        #expect(store.failure == nil)
        #expect(store.exercisesWriteFailure == nil)
        #expect(store.session == session)
    }

    @Test("A note that lands after one that failed retires the diagnostic")
    func aLaterSaveRetiresTheDiagnostic() async throws {
        let workout = try await Workout.started()
        workout.store.noteWriteFailure = "left over"

        await workout.store.saveNote("felt heavy")

        #expect(workout.store.noteWriteFailure == nil)
        #expect(workout.store.session?.notes == "felt heavy")
    }
}
