import Foundation
import RepositoryInterface

// `FR-16.1.4`'s one-tap append, in a file of its own for `ActiveSessionPlanCommands.swift`'s reason
// — `ActiveSessionCommands.swift` is near `file_length`'s warning, and this grows for a different
// reason than the set editor's writes do.

extension ActiveSessionStore {
    /// Logs the set that follows a run, by copying the last of it (`FR-16.1.4`).
    ///
    /// **The common case, where **Repeat set** is the fallback.** Both append; the difference is
    /// which set is copied. This one is attached to a group and copies *that group's* last member,
    /// so the line it sits under ticks from `× 3` to `× 4`; `FR-1.2.6`'s duplicate copies whatever
    /// was logged last on the card, whichever group that was, and opens the editor over it — which
    /// is the answer after a change of load, and the reason it stays.
    ///
    /// **Five fields, and the note is not one of them.** Load, repetitions, rating and modifiers are
    /// what makes two sets "the same" here — it is
    /// ``DerivedValues/SetGrouping/Grain/displayed``'s own list, which is what guarantees the count
    /// ticks rather than a second line appearing — and `FR-1.2.3`'s note is commentary on one set
    /// that the next one has not earned. `FR-1.2.6`'s duplicate drops it for the same reason.
    ///
    /// **Dropping it is what stops the count ticking on the one card that carries one**, and that
    /// is the honest reading rather than a defect: the note is a compared field at that grain, so a
    /// run of three sets annotated "belt on" gains a fourth that was not, and the fourth is a line
    /// of its own. Carrying the note would tick the count by asserting the lifter wrote something
    /// they did not.
    ///
    /// **Working and completed, whatever was copied.** The command is only offered on the working
    /// sets, so `isWarmup` cannot disagree in practice; it is written rather than carried so that a
    /// caller which offered it somewhere else could not silently append to the ramp.
    /// ``addSet(toEntryID:values:)`` owns `isCompleted` and `completedAt`.
    ///
    /// **The set is re-read rather than taken from the caller**, on ``logPlannedSet(inEntryID:)``'s
    /// rule: this runs at the back of ``pendingWrite``'s chain, so the card that drew the button is
    /// the one from before whatever is queued ahead of it — and an edit queued in between is
    /// exactly what would otherwise be copied stale.
    ///
    /// - Parameters:
    ///   - entryID: The exercise to log against.
    ///   - setID: The set to copy — the last member of the group the button is attached to.
    public func logNextSet(inEntryID entryID: UUID, copying setID: UUID) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeNextSet(inEntryID: entryID, copying: setID)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``logNextSet(inEntryID:copying:)``.
    ///
    /// **A source that is no longer there writes nothing and reports nothing**, which is
    /// ``logPlannedSet(inEntryID:)``'s "nothing to log" branch rather than a new rule: the set was
    /// deleted underneath the card, and a diagnostic would report a failure against a row the user
    /// can no longer see. The list is re-read either way — *why* there was nothing to copy is a fact
    /// about stored sets this command has just read and the held cards have not.
    ///
    /// A read that *fails* is reported, unlike that: the user asked for a set to be logged and none
    /// was.
    private func writeNextSet(inEntryID entryID: UUID, copying setID: UUID) async {
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            guard let source = stored.first(where: { $0.id == setID }) else {
                exercisesWriteFailure = nil
                await loadExercises()
                return
            }
            await writeAddedSet(
                toEntryID: entryID,
                values: SetEntryValues(
                    weight: source.weight,
                    reps: source.reps,
                    rpe: source.rpe,
                    isWarmup: false,
                    modifiers: source.modifiers
                )
            )
        } catch {
            exercisesWriteFailure = String(describing: error)
            await loadExercises()
        }
    }
}
