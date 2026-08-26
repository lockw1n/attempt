import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// Reading one past session, and the states that reading can land in (`FR-1.2.7`, `FR-1.13.1`).
@Suite("Past session reads")
struct PastSessionReadTests {
    @Test("A session resolves to its record and its exercises, in entry order")
    func loadingResolvesTheSessionAndItsExercises() async throws {
        let past = try await PastSession.logged()
        try await past.logSet(at: 0, order: 0)
        try await past.logSet(at: 1, order: 0)

        await past.state.load()

        guard case .loaded(let session) = past.state.phase else {
            Issue.record("expected a loaded session, got \(past.state.phase)")
            return
        }
        #expect(session.id == past.sessionID)
        #expect(past.state.exercises.count == 3)
        #expect(past.state.exercises.map { $0.exercise?.name } == ["Back Squat", "Bench Press", "Deadlift"])
        #expect(past.state.exercises[0].sets.count == 1)
        #expect(past.state.exercises[2].sets.isEmpty)
    }

    @Test("An identifier that resolves to nothing is missing, not a failure")
    func anUnknownIdentifierIsMissing() async throws {
        let past = try await PastSession.logged()
        let state = PastSession.state(sessionID: UUID(), over: past.repositories)

        await state.load()

        #expect(state.phase == .missing)
        #expect(state.exercises.isEmpty)
    }

    @Test("A soft-deleted session is missing too — G-1.3")
    func aDeletedSessionIsMissing() async throws {
        let past = try await PastSession.logged()
        try await past.repositories.workouts.deleteSession(id: past.sessionID)

        await past.state.load()

        #expect(past.state.phase == .missing)
    }

    @Test("A read that fails is a failure with the diagnostic on it, and costs the screen its rows")
    func aFailedReadIsRecoverable() async throws {
        let past = try await PastSession.logged()
        try await past.logSet(at: 0, order: 0)
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)

        // Loaded first, so "costs the screen its rows" is a claim about rows that were on it. Read
        // against a state that had never loaded, the assertion below holds of an empty screen and
        // cannot fail.
        await state.load()
        #expect(state.exercises.count == 3)

        await repository.refuseReads()
        await state.load()

        guard case .failed(let diagnostic) = state.phase else {
            Issue.record("expected a failed read, got \(state.phase)")
            return
        }
        #expect(!diagnostic.isEmpty)
        #expect(state.exercises.isEmpty)
    }

    @Test("A soft-deleted entry and a soft-deleted set are both off the screen — G-1.3")
    func softDeletedRowsAreNotRead() async throws {
        let past = try await PastSession.logged(names: ["Back Squat", "Bench Press"])
        let kept = try await past.logSet(at: 0, order: 0)
        let removed = try await past.logSet(at: 0, order: 1)
        try await past.repositories.workouts.deleteSet(id: removed.id)
        try await past.repositories.workouts.deleteExerciseEntry(id: past.entries[1].id)

        await past.state.load()

        #expect(past.state.exercises.count == 1)
        #expect(past.state.exercises[0].sets.map(\.id) == [kept.id])
    }

    @Test("The display unit is read from settings, having started at the schema's own default")
    func theDisplayUnitFollowsSettings() async throws {
        let past = try await PastSession.logged()
        let stored = try await past.repositories.settings.settings()
        try await past.repositories.settings.save(
            UserSettings(
                id: stored.id,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt,
                deletedAt: stored.deletedAt,
                userID: stored.userID,
                displayUnit: .pounds,
                e1RMFormula: stored.e1RMFormula,
                theme: stored.theme,
                defaultRoundingIncrement: stored.defaultRoundingIncrement,
                defaultRoundingStrategy: stored.defaultRoundingStrategy
            ))

        #expect(past.state.displayUnit == .kilograms)
        await past.state.load()
        #expect(past.state.displayUnit == .pounds)
    }

    @Test("A second load() while the first is in flight is refused, not run twice")
    func aSecondLoadWhileLoadingIsRefused() async throws {
        let past = try await PastSession.logged()
        let gate = GatedWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: gate)

        let reading = Task { await state.load() }
        await gate.arrival()
        #expect(state.phase == .loading)

        // The screen appeared twice — a tab switched away from and back — mid-read.
        let second = Task { await state.load() }
        await Task.yield()
        await gate.release()
        await reading.value
        await second.value

        // One entry read for one load. Asserted as work not done, because the rows come out right
        // either way — which is what makes this the only assertion that can see the guard at all.
        let reads = await gate.entryReads
        #expect(reads == 1)
        #expect(state.exercises.count == 3)
    }

    @Test("A session of three exercises reads back its warmups, its work and a failed set")
    func aMixedSessionReadsBackWhole() async throws {
        let past = try await PastSession.logged()
        try await past.logSet(at: 0, order: 0, isWarmup: true)
        try await past.logSet(at: 0, order: 1, isWarmup: true)
        try await past.logSet(at: 0, order: 2)
        try await past.logSet(at: 0, order: 3, isCompleted: false)
        try await past.logSet(at: 1, order: 0)

        await past.state.load()

        // Entry order, which is T-1.21's and the repository's — not the order they were written in.
        #expect(
            past.state.exercises.map { $0.exercise?.name } == [
                "Back Squat", "Bench Press", "Deadlift",
            ])
        let squat = try #require(past.state.exercises.first)
        #expect(squat.sets.map(\.isWarmup) == [true, true, false, false])
        #expect(squat.sets.map(\.isCompleted) == [true, true, true, false])
        #expect(past.state.exercises[1].sets.count == 1)
        #expect(past.state.exercises[2].sets.isEmpty)
    }

    @Test("A re-read retires the diagnostics an earlier attempt left behind")
    func aReloadClearsStaleWriteFailures() async throws {
        let past = try await PastSession.logged()
        let logged = try await past.logSet(at: 0, order: 0)
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)
        await state.load()

        await repository.refuseWrites()
        await state.deleteSet(id: logged.id, inEntryID: logged.entryID)
        await state.saveNote("nor this")
        #expect(state.writeFailure != nil)
        #expect(state.noteWriteFailure != nil)

        await repository.refuseWrites(false)
        await state.load()

        // Both described one attempt against rows this read has since rebuilt.
        #expect(state.writeFailure == nil)
        #expect(state.noteWriteFailure == nil)
    }
}

/// Correcting a set from a session that is over (`FR-1.2.7`, `G-1.3`, `NFR-1.8`).
@Suite("Past session writes")
struct PastSessionWriteTests {
    @Test("An edit rewrites the row and the screen re-reads it")
    func editingRewritesTheSet() async throws {
        let past = try await PastSession.logged()
        let logged = try await past.logSet(at: 0, order: 0)
        await past.state.load()

        await past.state.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(
                weight: Weight(grams: 102_500), reps: 3, rpe: 9, isWarmup: true, notes: "belt on")
        )

        let shown = try #require(past.state.exercises.first?.sets.first)
        #expect(shown.weight == Weight(grams: 102_500))
        #expect(shown.reps == 3)
        #expect(shown.isWarmup)
        #expect(shown.notes == "belt on")
        #expect(past.state.writeFailure == nil)
        // NFR-1.8: in the store, not only on screen.
        let stored = try #require(await past.storedSets(at: 0).first)
        #expect(stored.weight == Weight(grams: 102_500))
    }

    @Test("An edit leaves the outcome and the position alone — FR-1.2.5 has its own control")
    func editingCarriesTheOtherFieldsAcross() async throws {
        let past = try await PastSession.logged()
        let before = try await past.logSet(at: 0, order: 3, isCompleted: false)
        await past.state.load()

        await past.state.editSet(
            id: before.id,
            inEntryID: before.entryID,
            to: SetEntryValues(weight: Weight(grams: 90_000), reps: 2, rpe: nil, isWarmup: false)
        )

        let after = try #require(past.state.exercises.first?.sets.first)
        #expect(after.id == before.id)
        #expect(after.order == 3)
        #expect(after.isCompleted == false)
        #expect(after.createdAt == before.createdAt)
    }

    @Test("A deletion is soft, and the row leaves the screen — G-1.3")
    func deletingIsSoftAndSweepsTheRowOff() async throws {
        let past = try await PastSession.logged()
        let doomed = try await past.logSet(at: 0, order: 0)
        let kept = try await past.logSet(at: 0, order: 1)
        await past.state.load()

        await past.state.deleteSet(id: doomed.id, inEntryID: doomed.entryID)

        #expect(past.state.exercises.first?.sets.map(\.id) == [kept.id])
        #expect(past.state.writeFailure == nil)
        let stored = try await past.storedSets(at: 0)
        #expect(stored.count == 2)
        #expect(stored.first { $0.id == doomed.id }?.deletedAt != nil)
    }

    @Test("A set that is already gone is swept off rather than reported")
    func aSetAlreadyGoneIsNotAFailure() async throws {
        let past = try await PastSession.logged()
        let doomed = try await past.logSet(at: 0, order: 0)
        await past.state.load()
        try await past.repositories.workouts.deleteSet(id: doomed.id)

        await past.state.deleteSet(id: doomed.id, inEntryID: doomed.entryID)

        #expect(past.state.exercises.first?.sets.isEmpty == true)
        #expect(past.state.writeFailure == nil)
    }

    @Test("A write that fails is a diagnostic beside the rows, never a phase")
    func aFailedWriteKeepsTheRows() async throws {
        let past = try await PastSession.logged()
        let logged = try await past.logSet(at: 0, order: 0)
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)

        // Loaded from the working store first, so the rows it keeps are real ones. Refused from the
        // start, every assertion below is about an empty screen and none of them can fail.
        await state.load()
        await repository.refuseWrites()
        await state.deleteSet(id: logged.id, inEntryID: logged.entryID)

        #expect(state.writeFailure != nil)
        // The screen still vouches for what it is showing, and it is still showing it.
        guard case .loaded = state.phase else {
            Issue.record("expected the session to survive a refused write, got \(state.phase)")
            return
        }
        #expect(state.exercises.first?.sets.map(\.id) == [logged.id])
        #expect(state.exercises.count == 3)
    }

    @Test("A stored change whose re-read fails is the screen's failure, not the write's")
    func aFailedRereadIsNotAFailedWrite() async throws {
        let past = try await PastSession.logged()
        let logged = try await past.logSet(at: 0, order: 0)
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)
        await state.load()

        // The deletion goes through; only the read that would redraw the rows is turned down.
        await repository.refuseEntryReads()
        await state.deleteSet(id: logged.id, inEntryID: logged.entryID)

        // Not "that change could not be saved" — it was. What is lost is the screen's claim to be
        // showing the session, which is the state that carries the retry.
        #expect(state.writeFailure == nil)
        guard case .failed = state.phase else {
            Issue.record("expected a failed read, got \(state.phase)")
            return
        }
        #expect(state.exercises.isEmpty)
        // NFR-1.8: the deletion is in the store, whatever the screen can show of it.
        let stored = try await past.storedSets(at: 0)
        #expect(stored.first { $0.id == logged.id }?.deletedAt != nil)
    }
}

/// `FR-1.2.9`'s note, read back and rewritten on a session that is over.
@Suite("Past session note")
struct PastSessionNoteTests {
    @Test("A note written during the workout is here, unedited")
    func aStoredNoteIsReadBack() async throws {
        let past = try await PastSession.logged(notes: "felt heavy, belt from 140")

        await past.state.load()

        guard case .loaded(let session) = past.state.phase else {
            Issue.record("expected a loaded session, got \(past.state.phase)")
            return
        }
        #expect(session.notes == "felt heavy, belt from 140")
    }

    @Test("Saving stores the note and republishes the record the field compares against")
    func savingStoresTheNote() async throws {
        let past = try await PastSession.logged(notes: "")
        await past.state.load()

        await past.state.saveNote("shoulder twinged on set 3")

        guard case .loaded(let session) = past.state.phase else {
            Issue.record("expected a loaded session, got \(past.state.phase)")
            return
        }
        #expect(session.notes == "shoulder twinged on set 3")
        #expect(past.state.noteWriteFailure == nil)
        let stored = try await past.repositories.workouts.session(
            id: past.sessionID, includingDeleted: false)
        #expect(stored?.notes == "shoulder twinged on set 3")
    }

    @Test("A note that failed to save leaves a diagnostic and changes nothing")
    func aFailedNoteSaveIsReported() async throws {
        let past = try await PastSession.logged(notes: "before")
        let repository = FailableWorkoutRepository(wrapping: past.repositories.workouts)
        let state = PastSession.state(
            sessionID: past.sessionID, over: past.repositories, workouts: repository)
        await state.load()

        await repository.refuseWrites()
        await state.saveNote("after")

        #expect(state.noteWriteFailure != nil)
        // The held record is what the field compares itself against, and a refused write must not
        // move it — the screen would otherwise show the note as saved.
        guard case .loaded(let session) = state.phase else {
            Issue.record("expected the session to survive a refused write, got \(state.phase)")
            return
        }
        #expect(session.notes == "before")
        let stored = try await past.repositories.workouts.session(
            id: past.sessionID, includingDeleted: false)
        #expect(stored?.notes == "before")
    }

    @Test("An unsaved edit survives the screen's own re-read — FR-1.2.9")
    func anUnsavedNoteSurvivesAReread() async throws {
        let past = try await PastSession.logged(notes: "stored")
        var draft = SessionNoteDraft()
        await past.state.load()
        draft.follow(holding: past.state.session)
        draft.text = "typed, not saved"

        // What a re-read looks like to the screen: the record goes away for as long as the read is
        // out, and comes back unchanged. `follow(holding:)` is what refuses the gap — handed it as
        // `nil`, the draft resets outright and the edit is gone silently.
        draft.follow(holding: nil)
        await past.state.load()
        draft.follow(holding: past.state.session)

        #expect(draft.text == "typed, not saved")
        #expect(draft.hasUnsavedChanges)

        // The rule it is an exception to, which the workout in progress still needs: no record at
        // all empties the field, because there is nothing left for the text to be about.
        draft.follow(nil)
        #expect(draft.text.isEmpty)
    }
}
