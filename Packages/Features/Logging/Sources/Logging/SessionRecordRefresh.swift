import DerivedValues
import Foundation

// `NFR-1.2`'s half of the record pipeline: the recompute behind a logged set, and the badge it
// publishes when it lands. Its own file for `ActiveSessionNextSet.swift`'s reason —
// `ActiveSessionStore.swift` is the workout's lifecycle and had reached `file_length`'s ceiling,
// and this grows with the budget rather than with the workout.

extension ActiveSessionStore {
    /// Tells the recomputer a set moved, and re-reads the badge when it has (`FR-1.6.4`, `NFR-1.2`).
    ///
    /// **It returns before the walk starts, which is the requirement it exists for.** `NFR-1.2`
    /// budgets the wait between the tap and the row appearing, and the walk behind a logged set is
    /// `NFR-1.6`'s separate and five times larger allowance; a command that awaited it was spending
    /// one inside the other. What the lifter loses is the badge for the tap that earned it, for as
    /// long as the walk takes.
    ///
    /// **Chained, so two taps recompute in the order they were made** — the actor would serialise
    /// them anyway, but the badge re-reads would not, and the second tap's is the one that should
    /// stand.
    ///
    /// **The write chain is awaited before the walk, not after it**, so the recompute reads the
    /// store the command left rather than one it is halfway through — the answer that logs five sets
    /// has written two of them when this task first runs. It also settles the other way round: the
    /// marks are published after the write, so a re-read cannot overwrite a fresher answer with one
    /// taken before the recompute landed.
    ///
    /// **A workout that has been swapped underneath drops its refresh.** The marks are keyed on sets
    /// this session holds, so publishing them against another workout would be
    /// ``forgetExercises()``'s claim undone.
    ///
    /// - Parameter entryID: The exercise entry the set was written against.
    func announceSetChange(inEntryID entryID: UUID) {
        let sessionID = session?.id
        let previous = recordRefresh
        recordRefresh = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await self.pendingWrite?.value
            await self.records.setDidChange(inEntryID: entryID)
            guard self.session?.id == sessionID else { return }
            await self.refreshRecordMarks()
        }
    }

    /// Re-reads ``personalRecords`` over the exercises currently held.
    ///
    /// A workout with no exercises read yet is left alone rather than marked loaded: an empty answer
    /// there would say the workout holds no records, which is ``SessionRecordMarks/hasLoaded``'s own
    /// distinction.
    private func refreshRecordMarks() async {
        guard session != nil, !exercises.isEmpty else { return }
        personalRecords = await SessionRecordMarks.read(over: exercises, from: records)
    }

    /// Waits for ``announceSetChange(inEntryID:)``'s chain to have published what it owes.
    ///
    /// **A test's settle point, and the only supported one.** The badge is no longer part of the
    /// command that logged the set, so an assertion about it that ran on the command's own `await`
    /// would be asserting on a race. Internal: nothing on screen waits for a badge.
    func settleRecordRefresh() async {
        await recordRefresh?.value
    }
}
