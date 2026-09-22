import Foundation
import RepositoryInterface

// `FR-18.5`'s way back: the one command that takes a row's answer off again. Its own file for
// `SessionRecordRefresh.swift`'s reason — `DayAnswerCommands.swift` is the three answers a day
// gives an exercise, and this is the undo of two of them, which grows with what an answer writes
// rather than with the checklist.

extension ActiveSessionStore {
    /// Takes one exercise's answer back (`FR-18.5.1`, `FR-18.5.3`).
    ///
    /// **One chained command and one re-read** (`NFR-18.3`), on ``answerAsPlanned(inEntryIDs:)``'s
    /// rule: the sets go, the mark is cleared and the day is re-opened inside a single link of
    /// ``pendingWrite``'s chain, so a reset that arrives behind a save is applied to what that save
    /// left.
    ///
    /// **It is the inverse of what ``answerAsPlanned(inEntryIDs:)`` and ``skipExercise(inEntryID:)``
    /// *write*, not of what a row displays.** Both of them write the same two things — completed
    /// sets, and the entry's check-off — so one command undoes either, and a row that was logged
    /// and a row that was skipped come back to the same place.
    ///
    /// **The planned rows stay.** They are the routine's prescription copied onto the session
    /// (`FR-15.3.2`), not an answer, and a reset that removed them would leave a row nothing could
    /// be logged against as planned — the circle reads them.
    ///
    /// - Parameter entryID: The exercise whose answer is being taken back.
    public func resetExercise(inEntryID entryID: UUID) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeReset(inEntryID: entryID)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``resetExercise(inEntryID:)``.
    private func writeReset(inEntryID entryID: UUID) async {
        guard let current = session else { return }
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            // A set nobody attempted is not an answer (`FR-16.4`): an import writes them ahead of
            // the work, and a reset that swept them up would delete the plan a lifter is about to
            // perform rather than the answer they are taking back.
            let completed = stored.filter(\.isCompleted)
            for set in completed {
                try await repository.deleteSet(id: set.id)
            }
            try await clearDoneMark(entryID: entryID, ofSessionID: current.id)
            try await reopenIfEnded(current)
            // Announced only where work went, on ``skipExercises(inEntryIDs:)``' rule: a row whose
            // answer was a skip stood at no record, so there is nothing for the walk to correct.
            if !completed.isEmpty {
                announceSetChange(inEntryID: entryID)
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Clears one entry's check-off, where it carries one.
    ///
    /// ``markDone(entryID:ofSessionID:)``'s inverse, guard included: an entry that is already not
    /// done is **not** written, because assigning a `@Model` property marks the row changed
    /// whatever the value was and the save would restamp `updatedAt` — `G-2.4`'s conflict key. An
    /// entry the read does not find is silently nothing, the row having gone away underneath the
    /// checklist.
    ///
    /// - Parameters:
    ///   - entryID: The exercise.
    ///   - sessionID: The workout it belongs to.
    /// - Throws: Whatever the repository throws.
    private func clearDoneMark(entryID: UUID, ofSessionID sessionID: UUID) async throws {
        let entries = try await repository.entries(forSessionID: sessionID, includingDeleted: false)
        guard let entry = entries.first(where: { $0.id == entryID }), entry.isMarkedDone else {
            return
        }
        try await repository.save(entry.notMarkedDone)
    }

    /// Puts a finished day back in progress (`FR-18.5.3`).
    ///
    /// **The one thing that puts `endedAt` back**, which ``endDay()`` says nothing does — and it is
    /// that method's own consequence rather than a contradiction of it: a day is over when every
    /// row is answered, and a row this command has just un-answered means the day is not. A day
    /// left ended would be read-only (`FR-17.7.5`) over a row with no answer on it, and its card
    /// would go on reading **Done** while the checklist read `5 of 6`.
    ///
    /// **`NFR-1.9` re-arms with it**, which is the reading of ``isInProgress`` rather than of
    /// ``isActive``: a lifter who took an answer back is lifting again, and the screen stays awake
    /// for the sets they are about to log.
    ///
    /// A day that never ended is not written — ``update(_:)``'s rule, one level down.
    ///
    /// - Parameter current: The day's session as held.
    /// - Throws: Whatever the repository throws.
    private func reopenIfEnded(_ current: WorkoutSession) async throws {
        guard current.endedAt != nil else { return }
        let reopened = Self.reopened(current)
        try await repository.save(reopened)
        guard let stored = try await repository.session(id: reopened.id, includingDeleted: false)
        else {
            throw RepositoryError.recordNotFound(id: reopened.id)
        }
        adopt(stored: stored)
    }

    /// `session` with its end taken off, and every other field untouched.
    ///
    /// Every column is named, on ``DerivedValues/SessionFinish/ended(_:at:)``'s rule: `save(_:)` is
    /// an upsert over a value whose initialiser defaults the program stamp to `nil`, so a rebuild
    /// that omitted it would erase which day of which week this workout is.
    ///
    /// - Parameter session: The workout.
    /// - Returns: The record to store.
    private static func reopened(_ session: WorkoutSession) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: session.date,
            startedAt: session.startedAt,
            endedAt: nil,
            notes: session.notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }
}
