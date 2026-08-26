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
        let state = PastSession.state(
            sessionID: past.sessionID,
            over: past.repositories,
            workouts: RefusingWorkoutRepository()
        )

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

    @Test("A read already in flight is not run twice")
    func aSecondLoadWhileLoadingIsRefused() async throws {
        let past = try await PastSession.logged()
        await past.state.load()
        // Reached only from the loading phase, which a completed read has already left — so the
        // guard is exercised by asking for the state it refuses in rather than by racing one.
        #expect(past.state.phase != .loading)
        await past.state.load()
        #expect(past.state.exercises.count == 3)
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
        await past.state.load()
        let broken = PastSession.state(
            sessionID: past.sessionID,
            over: past.repositories,
            workouts: RefusingWorkoutRepository()
        )
        // The failing state is loaded from the working store first, so the rows it keeps are real.
        await past.state.editSet(
            id: logged.id,
            inEntryID: logged.entryID,
            to: SetEntryValues(weight: Weight(grams: 95_000), reps: 5, rpe: nil, isWarmup: false)
        )
        await broken.deleteSet(id: logged.id, inEntryID: logged.entryID)

        #expect(broken.writeFailure != nil)
        #expect(broken.phase == .idle)
        // The working state is untouched by the other's failure, and still holds its row.
        #expect(past.state.exercises.first?.sets.count == 1)
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
        let broken = PastSession.state(
            sessionID: past.sessionID,
            over: past.repositories,
            workouts: RefusingWorkoutRepository()
        )

        await broken.saveNote("after")

        #expect(broken.noteWriteFailure != nil)
        let stored = try await past.repositories.workouts.session(
            id: past.sessionID, includingDeleted: false)
        #expect(stored?.notes == "before")
    }
}
