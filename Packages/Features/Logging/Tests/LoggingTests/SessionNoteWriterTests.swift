import Foundation
import PowerliftingCore
import RepositoryFakes
import RepositoryInterface
import Testing

@testable import Logging

/// The one write a past session carries on its own record (`FR-1.2.9`, `G-2.4`, `NFR-1.8`).
///
/// A suite of its own rather than part of the screen's, for `SessionSetEditingTests`' reason: the
/// writer is usable without a screen and its refusals are what a screen depends on.
@Suite("Session note writer")
struct SessionNoteWriterTests {
    @Test("A note is stored, and every other column is carried across")
    func savingStoresOnlyTheNote() async throws {
        let past = try await PastSession.logged(notes: "before")
        let before = try #require(
            await past.repositories.workouts.session(id: past.sessionID, includingDeleted: false))
        let writer = SessionNoteWriter(repository: past.repositories.workouts)

        let wrote = try await writer.save(id: past.sessionID, notes: "after")

        #expect(wrote)
        let after = try #require(
            await past.repositories.workouts.session(id: past.sessionID, includingDeleted: false))
        #expect(after.notes == "after")
        #expect(after.date == before.date)
        #expect(after.startedAt == before.startedAt)
        // The column a partial rebuild would put back to `nil`.
        #expect(after.endedAt == before.endedAt)
        #expect(after.createdAt == before.createdAt)
        #expect(after.bodyweight == before.bodyweight)
    }

    @Test("Text the record already carries is not written — G-2.4's conflict key stays put")
    func anUnchangedNoteIsNotWritten() async throws {
        let past = try await PastSession.logged(notes: "unchanged")
        let before = try #require(
            await past.repositories.workouts.session(id: past.sessionID, includingDeleted: false))
        let writer = SessionNoteWriter(repository: past.repositories.workouts)

        let wrote = try await writer.save(id: past.sessionID, notes: "unchanged")

        #expect(!wrote)
        let after = try #require(
            await past.repositories.workouts.session(id: past.sessionID, includingDeleted: false))
        #expect(after.updatedAt == before.updatedAt)
    }

    @Test("A session that is not there answers false rather than raising")
    func anUnknownSessionIsNothingToWrite() async throws {
        let past = try await PastSession.logged()
        let writer = SessionNoteWriter(repository: past.repositories.workouts)

        #expect(try await writer.save(id: UUID(), notes: "anything") == false)
    }

    @Test("A soft-deleted session is nothing to write either — G-1.3")
    func aDeletedSessionIsNothingToWrite() async throws {
        let past = try await PastSession.logged(notes: "before")
        try await past.repositories.workouts.deleteSession(id: past.sessionID)
        let writer = SessionNoteWriter(repository: past.repositories.workouts)

        #expect(try await writer.save(id: past.sessionID, notes: "after") == false)
        let stored = try #require(
            await past.repositories.workouts.session(id: past.sessionID, includingDeleted: true))
        #expect(stored.notes == "before")
    }

    @Test("A repository that refuses is reported rather than swallowed")
    func aRefusingRepositoryThrows() async throws {
        let writer = SessionNoteWriter(repository: RefusingWorkoutRepository())

        await #expect(throws: RepositoryError.self) {
            try await writer.save(id: UUID(), notes: "anything")
        }
    }
}

/// The one mapping between a typed form and the six columns it writes (`FR-1.2.3`, `FR-1.2.7`).
@Suite("Set draft resolution")
struct SetDraftResolutionTests {
    /// The locale every draft here parses in.
    private static let locale = Locale(identifier: "en_US_POSIX")

    @Test("A draft that resolves carries all six fields")
    func aResolvedDraftCarriesEveryField() throws {
        var draft = SetDraft(unit: .kilograms, locale: Self.locale)
        draft.weightText = "102.5"
        draft.repsText = "3"
        draft.rpeText = "9"
        draft.isWarmup = true
        draft.modifiers = [SetModifier(.belt)]
        draft.notes = "belt on"

        let values = try #require(draft.resolved)
        #expect(values.weight == Weight(grams: 102_500))
        #expect(values.reps == 3)
        #expect(values.rpe == 9)
        #expect(values.isWarmup)
        #expect(values.modifiers == [SetModifier(.belt)])
        #expect(values.notes == "belt on")
    }

    @Test("A draft the form refuses resolves to nothing")
    func aRefusedDraftResolvesToNothing() {
        var blank = SetDraft(unit: .kilograms, locale: Self.locale)
        #expect(blank.resolved == nil)

        blank.weightText = "100"
        #expect(blank.resolved == nil, "the reps are still missing")

        blank.repsText = "5"
        #expect(blank.resolved != nil)

        blank.rpeText = "42"
        #expect(blank.resolved == nil, "a rating outside 1...10 refuses the whole draft")
    }
}
