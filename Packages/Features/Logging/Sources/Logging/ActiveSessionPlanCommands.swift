import Foundation
import PowerliftingCore
import RepositoryInterface

// `FR-15.3`'s two writes against the workout in progress, in a file of their own for
// `ActiveSessionCommands.swift`'s reason — that file is at `file_length`'s warning, and these grow
// for a different reason than the set commands do.

extension ActiveSessionStore {
    /// Checks one exercise off, or takes the check back (`FR-15.3.4`).
    ///
    /// **One action for the whole exercise, never one per set.** How many sets were logged against
    /// it is a different fact, already on the card: this is the lifter saying they are finished
    /// with the movement, which they are entitled to do three sets into a planned five, and equally
    /// entitled to do having logged nothing at all — see ``SessionExercise/isSkipped``.
    ///
    /// **A toggle rather than two commands**, because the control is one checkbox and the value
    /// arrives already flipped.
    ///
    /// - Parameters:
    ///   - entryID: The exercise, by its entry.
    ///   - isDone: What it becomes.
    public func markExercise(id entryID: UUID, isDone: Bool) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeMarkedExercise(id: entryID, isDone: isDone)
        }
        pendingWrite = write
        await write.value
    }

    /// Logs the next planned set exactly as the routine prescribed it (`NFR-15.3`, `FR-15.3.1`).
    ///
    /// **The one-tap half of "start to first set logged in two taps".** The other route to the same
    /// set — **Add set**, opening the editor pre-filled — is one tap more, which is the tap that
    /// puts the inclusive reading of `NFR-15.3` over budget. This command spends none: what the
    /// plan named is what is written.
    ///
    /// **Nothing is written where the plan named no load** (`FR-15.2.2`). A blank-weight group
    /// prescribes the reps and leaves the load to the lifter, so there is no set to log without
    /// asking — the card offers the pre-filled editor there instead, and the caller is what decides
    /// that. Guarded here as well so the command cannot invent a zero.
    ///
    /// **The plan and the sets are both re-read**, on every command here's rule: this runs at the
    /// back of ``pendingWrite``'s chain, so the held list is the one from before whatever is queued
    /// ahead of it — and *which* group is next is a function of how many working sets are already
    /// stored.
    ///
    /// - Parameter entryID: The exercise to log against.
    public func logPlannedSet(inEntryID entryID: UUID) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writePlannedSet(inEntryID: entryID)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``markExercise(id:isDone:)``.
    ///
    /// **An entry the read does not find is silently nothing**, on the set commands' rule: the row
    /// went away underneath the card, and a diagnostic would report a failure against an exercise
    /// the user can no longer see. The list is re-read either way, which is what sweeps it off.
    ///
    /// **An entry already in that state is not written**, and that is `G-2.4` rather than tidiness:
    /// assigning a `@Model` property marks the row changed whatever the value was, so the save
    /// would restamp `updatedAt` — the conflict key — and a no-op local write would outrank a real
    /// remote edit.
    private func writeMarkedExercise(id entryID: UUID, isDone: Bool) async {
        guard let current = session else { return }
        do {
            let stored = try await repository.entries(forSessionID: current.id, includingDeleted: false)
            if let entry = stored.first(where: { $0.id == entryID }), entry.isMarkedDone != isDone {
                try await repository.save(Self.marked(entry, isDone: isDone))
            }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }

    /// One link in ``pendingWrite``'s chain. See ``logPlannedSet(inEntryID:)``.
    ///
    /// A read that fails is reported, unlike the two "row is gone" cases above: the user asked for
    /// a set to be logged and none was, which is exactly what `exercisesWriteFailure` is beside the
    /// command for.
    private func writePlannedSet(inEntryID entryID: UUID) async {
        do {
            let planned = try await repository.plannedTargets(
                forEntryID: entryID, includingDeleted: false)
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            let group = SessionExercise.plannedGroup(
                in: planned, afterWorkingSets: stored.count { !$0.isWarmup })
            guard let group, let weight = group.targetWeight else {
                // The list is re-read even though nothing was written, on the check-off's rule:
                // *why* there was nothing to log is a fact about stored sets this command has just
                // read and the held list has not.
                exercisesWriteFailure = nil
                await loadExercises()
                return
            }
            await writeAddedSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: weight, reps: group.targetReps, rpe: nil, isWarmup: false)
            )
        } catch {
            exercisesWriteFailure = String(describing: error)
            await loadExercises()
        }
    }

    /// `entry` with its check-off flipped and every other field untouched.
    ///
    /// Rebuilt rather than mutated, the record being a value with `let` properties; the three
    /// timestamps are carried across because the write path is an upsert that stamps `updatedAt`
    /// itself.
    ///
    /// - Parameters:
    ///   - entry: The stored row.
    ///   - isDone: What it becomes.
    /// - Returns: The record to save.
    private static func marked(_ entry: ExerciseEntry, isDone: Bool) -> ExerciseEntry {
        ExerciseEntry(
            id: entry.id,
            createdAt: entry.createdAt,
            updatedAt: entry.updatedAt,
            deletedAt: entry.deletedAt,
            sessionID: entry.sessionID,
            exerciseID: entry.exerciseID,
            order: entry.order,
            notes: entry.notes,
            isMarkedDone: isDone
        )
    }
}
