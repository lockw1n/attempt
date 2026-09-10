import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

// `FR-17.9`'s three answers a day's checklist gives an exercise — the circle, the skip, and the end
// of the day — in a file of their own for `ActiveSessionPlanCommands.swift`'s reason: that file is
// `FR-15.3`'s two writes against a card, and these are the day's, which grow with the checklist
// rather than with the card.

extension ActiveSessionStore {
    /// Logs one or more exercises exactly as the plan prescribed them, and marks each done
    /// (`FR-17.9.2`, `FR-17.9.9`).
    ///
    /// **One command for the whole exercise, and one chain for however many are named.** The circle
    /// is one tap that writes N sets: ``logPlannedSet(inEntryID:)`` announces to the recomputer per
    /// row and re-reads the list per row, which is the precedent and not the path — five taps' worth
    /// of recomputation for one. Here each entry is announced once, when its sets are all stored,
    /// and the list is re-read once at the end however many entries were named (`NFR-17.3`).
    ///
    /// **A member nobody attempted is completed rather than appended to** (`FR-16.4.4`, `Q-17.6`).
    /// An imported or half-logged exercise can already hold rows with `isCompleted == false`; those
    /// are the sets this command is claiming were performed, so writing new ones beside them would
    /// double the work and leave the originals to be resolved at the end of the day.
    ///
    /// **The plan and the sets are re-read inside the chain**, on every command here's rule: this
    /// runs behind whatever is queued ahead of it, and how many sets are already stored is what
    /// decides which planned group the next one falls in.
    ///
    /// - Parameter entryIDs: The exercises to answer, in the order they are drawn.
    public func answerAsPlanned(inEntryIDs entryIDs: [UUID]) async {
        // `NFR-1.2`'s own interval, and it spans the whole chain rather than the write: what the
        // budget is written about is the wait between the tap and the row re-reading, which is
        // `writeAnswersAsPlanned` plus the `loadExercises()` it ends in.
        await PerformanceSignpost.answer.measure {
            let previous = pendingWrite
            let write = Task { [weak self] in
                await previous?.value
                await self?.writeAnswersAsPlanned(inEntryIDs: entryIDs)
            }
            pendingWrite = write
            await write.value
        }
    }

    /// ``answerAsPlanned(inEntryIDs:)`` for the one row the circle was tapped on.
    ///
    /// - Parameter entryID: The exercise to answer.
    public func answerAsPlanned(inEntryID entryID: UUID) async {
        await answerAsPlanned(inEntryIDs: [entryID])
    }

    /// Records that the lifter is not doing these exercises today (`FR-17.9.6`, `FR-17.9.9`).
    ///
    /// **The pending members go and the row is marked done** — soft-deleted, like every deletion
    /// here (`G-1.3`). A skip that left them would end the day owing `FR-16.4.4` an answer about
    /// sets the lifter has already answered for, and a skip that kept them as failed would record
    /// lifts that were never attempted.
    ///
    /// **Nothing else is written.** A skip is `isMarkedDone` with no completed working set behind
    /// it — see ``DayRowAnswer`` — so it needs no column of its own, and a row that already carries
    /// completed work is marked done rather than emptied: the lifter is stopping, not undoing.
    ///
    /// - Parameter entryIDs: The exercises to skip, in the order they are drawn.
    public func skipExercises(inEntryIDs entryIDs: [UUID]) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeSkips(inEntryIDs: entryIDs)
        }
        pendingWrite = write
        await write.value
    }

    /// ``skipExercises(inEntryIDs:)`` for one row.
    ///
    /// - Parameter entryID: The exercise to skip.
    public func skipExercise(inEntryID entryID: UUID) async {
        await skipExercises(inEntryIDs: [entryID])
    }

    /// Ends the day's session, with no resolution step (`FR-17.9.8`, `FR-1.2.11`).
    ///
    /// **A day has no pending-set question, because it never gets to have one.** The circle writes
    /// completed rows, a skip removes the rows nobody attempted, and **Log** writes what the lifter
    /// typed — so by the time the last row is answered there is nothing left for `FR-16.4.4` to ask
    /// about. `.keepAsFailed` is therefore the honest resolution rather than a default chosen to
    /// avoid asking: a set that is not completed inside a session that has ended *is* a failed set,
    /// and there are none.
    ///
    /// **The cursor is not moved.** `ProgramRun.nextDayIndex` is `T-17.13`'s, and a week whose days
    /// can be done in any order (`D-17.10`) has no next day for finishing one to advance.
    ///
    /// **The session is kept held, unlike ``finish(resolving:)``.** The day's screen goes on drawing
    /// it — a done day is read-only rather than gone, and **Log** still edits it (`FR-17.7.5`).
    func endDay() async {
        guard let current = session, current.endedAt == nil else { return }
        do {
            let ended = try await SessionFinish(workouts: repository, records: records)
                .finish(current, at: .now, resolving: .keepAsFailed)
            guard let stored = try await repository.session(id: ended.id, includingDeleted: false)
            else {
                throw RepositoryError.recordNotFound(id: ended.id)
            }
            adopt(stored: stored)
        } catch {
            report(error)
        }
    }

    /// Moves the workout to another training day (`FR-1.2.1`, `FR-17.9.7`).
    ///
    /// **On the store rather than on either screen**, because both of the overflow menu's hosts
    /// issue it: a day's checklist and the free workout share the menu, and a rebuild written twice
    /// is two places for the program stamp to be dropped.
    ///
    /// - Parameter day: The training day, normalised to its start on ``start(on:)``'s rule — the
    ///   day, not the moment the picker was closed.
    public func changeDate(to day: Date) async {
        guard let current = session else { return }
        await update(Self.dated(current, to: day))
    }

    /// `session` on another training day, and every other field untouched.
    ///
    /// Every column is named, on ``DerivedValues/SessionFinish/ended(_:at:)``'s rule: `save(_:)` is
    /// an upsert over a value whose initialiser defaults the program stamp to `nil`, so a rebuild
    /// that omitted it would erase which day of which week this workout is.
    ///
    /// - Parameters:
    ///   - session: The workout.
    ///   - day: The training day it moves to.
    /// - Returns: The record to store.
    private static func dated(_ session: WorkoutSession, to day: Date) -> WorkoutSession {
        WorkoutSession(
            id: session.id,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt,
            deletedAt: session.deletedAt,
            date: Calendar.current.startOfDay(for: day),
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            notes: session.notes,
            bodyweight: session.bodyweight,
            programRunID: session.programRunID,
            scheduledWorkoutID: session.scheduledWorkoutID,
            weekNumber: session.weekNumber,
            dayIndex: session.dayIndex
        )
    }

    /// One link in ``pendingWrite``'s chain. See ``answerAsPlanned(inEntryIDs:)``.
    private func writeAnswersAsPlanned(inEntryIDs entryIDs: [UUID]) async {
        guard let current = session else { return }
        do {
            for entryID in entryIDs {
                try await writeAnswerAsPlanned(inEntryID: entryID, ofSessionID: current.id)
                await records.setDidChange(inEntryID: entryID)
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// One exercise's worth of that write.
    ///
    /// - Parameters:
    ///   - entryID: The exercise being answered.
    ///   - sessionID: The workout it belongs to.
    /// - Throws: Whatever the repository throws.
    private func writeAnswerAsPlanned(inEntryID entryID: UUID, ofSessionID sessionID: UUID) async throws {
        let planned = try await repository.plannedTargets(
            forEntryID: entryID, includingDeleted: false)
        let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
        let now = Date.now
        for set in stored where !set.isCompleted {
            try await repository.save(Self.completed(set, at: now))
        }
        var order = (stored.map(\.order).max() ?? -1) + 1
        var position = stored.count { !$0.isWarmup }
        while true {
            let group = SessionExercise.plannedGroup(in: planned, afterWorkingSets: position)
            guard let group, let weight = group.targetWeight else { break }
            try await repository.save(
                Self.performed(
                    entryID: entryID, order: order, weight: weight, reps: group.targetReps, at: now))
            order += 1
            position += 1
        }
        try await markDone(entryID: entryID, ofSessionID: sessionID)
    }

    /// One link in ``pendingWrite``'s chain. See ``skipExercises(inEntryIDs:)``.
    private func writeSkips(inEntryIDs entryIDs: [UUID]) async {
        guard let current = session else { return }
        do {
            for entryID in entryIDs {
                let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
                let pending = stored.filter { !$0.isCompleted }
                for set in pending {
                    try await repository.deleteSet(id: set.id)
                }
                try await markDone(entryID: entryID, ofSessionID: current.id)
                // Announced only where a row went. A set nobody attempted counts towards no record
                // — it is not completed — so removing one changes nothing the cache holds, and an
                // announcement per skipped row would be a catalogue walk per tap.
                if !pending.isEmpty {
                    await records.setDidChange(inEntryID: entryID)
                }
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// Marks one entry done, where it is not already.
    ///
    /// Internal rather than private: the Log sheet's group commands chain the same mark onto their
    /// own write (`FR-17.9.4`), and a second copy of the no-op guard is a second place `G-2.4`'s
    /// conflict key can be restamped for nothing.
    ///
    /// An entry the read does not find is silently nothing, on the plan commands' rule: the row went
    /// away underneath the checklist. An entry already done is **not** written — assigning a
    /// `@Model` property marks the row changed whatever the value was, so the save would restamp
    /// `updatedAt`, which is `G-2.4`'s conflict key.
    ///
    /// - Parameters:
    ///   - entryID: The exercise.
    ///   - sessionID: The workout it belongs to.
    /// - Throws: Whatever the repository throws.
    func markDone(entryID: UUID, ofSessionID sessionID: UUID) async throws {
        let entries = try await repository.entries(forSessionID: sessionID, includingDeleted: false)
        guard let entry = entries.first(where: { $0.id == entryID }), !entry.isMarkedDone else {
            return
        }
        try await repository.save(entry.markedDone)
    }

    /// `set` completed, and every other field untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties.
    ///
    /// - Parameters:
    ///   - set: The stored row.
    ///   - moment: When it was completed.
    /// - Returns: The record to save.
    private static func completed(_ set: SetEntry, at moment: Date) -> SetEntry {
        SetEntry(
            id: set.id,
            createdAt: set.createdAt,
            updatedAt: set.updatedAt,
            deletedAt: set.deletedAt,
            entryID: set.entryID,
            order: set.order,
            weight: set.weight,
            reps: set.reps,
            rpe: set.rpe,
            rir: set.rir,
            isWarmup: set.isWarmup,
            isCompleted: true,
            targetWeight: set.targetWeight,
            targetReps: set.targetReps,
            modifiers: set.modifiers,
            notes: set.notes,
            completedAt: set.completedAt ?? moment
        )
    }

    /// One working set, performed exactly as prescribed.
    ///
    /// - Parameters:
    ///   - entryID: The exercise it belongs to.
    ///   - order: Its position among that exercise's sets.
    ///   - weight: The load prescribed.
    ///   - reps: The repetitions prescribed.
    ///   - moment: When it was logged.
    /// - Returns: The record to save.
    private static func performed(
        entryID: UUID, order: Int, weight: Weight, reps: Int, at moment: Date
    ) -> SetEntry {
        SetEntry(
            id: UUID(),
            createdAt: moment,
            updatedAt: moment,
            deletedAt: nil,
            entryID: entryID,
            order: order,
            weight: weight,
            reps: reps,
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
    }
}
