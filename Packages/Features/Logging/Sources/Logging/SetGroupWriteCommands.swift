import Foundation
import RepositoryInterface

// `FR-17.1`'s Log sheet writes a *group*, and this is the chain it writes on — a file of its own
// for `DayAnswerCommands.swift`'s reason: those are the circle and the skip, these are the sheet's.

extension ActiveSessionStore {
    /// Writes an N-set group against a checklist row and marks it done (`FR-17.9.4`, `NFR-17.3`).
    ///
    /// **One command, one announcement, one re-read — not N of each.** `addSet(toEntryID:values:)`
    /// called N times would announce to the recomputer N times and re-read the whole list N times,
    /// which is what `NFR-17.3` exists to forbid: the sheet answers a whole exercise, so the write
    /// is one link on the chain however many sets it holds.
    ///
    /// **The done mark is chained onto it rather than issued after it** (`FR-17.9.3`): a save that
    /// wrote the sets and left the row unanswered would be a checklist disagreeing with its own
    /// history the moment the screen re-read.
    ///
    /// - Parameters:
    ///   - entryID: The exercise being answered.
    ///   - rows: What was done, one entry per set, in order.
    public func logGroup(inEntryID entryID: UUID, rows: [SetEntryValues]) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeLoggedGroup(inEntryID: entryID, rows: rows)
        }
        pendingWrite = write
        await write.value
    }

    /// Rewrites an answered row's group to what the sheet now says (`FR-17.7.5`).
    ///
    /// The rewrite itself is ``SetGroupRewrite``'s; what this adds is the chain, the diagnostic and
    /// the re-read. The done mark is chained on for ``logGroup(inEntryID:rows:)``'s reason — a row
    /// being corrected is a row that stays answered, and a mark already set is not written.
    ///
    /// - Parameters:
    ///   - entryID: The exercise whose group is being rewritten.
    ///   - rows: What it becomes, in order.
    public func rewriteGroup(inEntryID entryID: UUID, rows: [SetEntryValues]) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeRewrittenGroup(inEntryID: entryID, rows: rows)
        }
        pendingWrite = write
        await write.value
    }

    /// Appends an N-set group to a card in a free workout (`FR-17.1.1`).
    ///
    /// **``logGroup(inEntryID:rows:)`` without the done mark**, which is the whole difference: a
    /// free workout has no checklist row to answer, and `FR-1.2.13` reads whether a card is
    /// finished off the sets themselves.
    ///
    /// - Parameters:
    ///   - entryID: The exercise to log against.
    ///   - rows: What was done, one entry per set, in order.
    public func addSets(toEntryID entryID: UUID, rows: [SetEntryValues]) async {
        let previous = pendingWrite
        let write = Task { [weak self] in
            await previous?.value
            await self?.writeLoggedGroup(inEntryID: entryID, rows: rows, markingDone: false)
        }
        pendingWrite = write
        await write.value
    }

    /// One link in ``pendingWrite``'s chain. See ``logGroup(inEntryID:rows:)``.
    ///
    /// **A refusal part-way through keeps what landed** (`NFR-1.8`): the rows written before it
    /// stay written, the diagnostic is reported once rather than per row, and the announcement
    /// still goes out — sets that landed can have moved a record whether or not the rest did. The
    /// re-read then draws exactly the rows that exist.
    ///
    /// **A row being answered loses its pending members first** (`FR-16.4.4`, `Q-17.6`), which is
    /// ``skipExercises(inEntryIDs:)``' rule rather than a new one: a set nobody attempted is the
    /// question the sheet has just answered, so leaving it beside the answer would double the work
    /// and hand `FR-16.4.4` a set to resolve at the end of a day that has none. Soft, like every
    /// deletion here (`G-1.3`). A completed member is left alone — that is work the lifter logged
    /// separately, and this command appends beside it.
    ///
    /// **Only where the row is being marked done.** A free workout has no checklist row and keeps
    /// `FR-16.4.4`'s question, so ``addSets(toEntryID:rows:)`` writes beside its pending sets
    /// rather than through them.
    private func writeLoggedGroup(
        inEntryID entryID: UUID, rows: [SetEntryValues], markingDone: Bool = true
    ) async {
        guard let current = session else { return }
        var written = 0
        do {
            let stored = try await repository.sets(forEntryID: entryID, includingDeleted: false)
            if markingDone {
                for pending in stored where !pending.isCompleted {
                    try await repository.deleteSet(id: pending.id)
                }
            }
            var order = (stored.map(\.order).max() ?? -1) + 1
            let moment = Date.now
            for values in rows {
                try await repository.save(
                    SetGroupRewrite.logged(values, entryID: entryID, order: order, at: moment))
                order += 1
                written += 1
            }
            if markingDone { try await markDone(entryID: entryID, ofSessionID: current.id) }
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        if written > 0 { announceSetChange(inEntryID: entryID) }
        await loadExercises()
    }

    /// One link in ``pendingWrite``'s chain. See ``rewriteGroup(inEntryID:rows:)``.
    private func writeRewrittenGroup(inEntryID entryID: UUID, rows: [SetEntryValues]) async {
        guard let current = session else { return }
        do {
            let changed = try await SetGroupRewrite(repository: repository)
                .rewrite(inEntryID: entryID, to: rows)
            // Announced before the entry is marked done, not after: the sets have already moved by
            // here, and a `markDone` that throws would otherwise leave the cache holding records for
            // sets that are gone with nothing left to tell it (`FR-1.6.4`). It is the order
            // ``SetGroupRewrite`` itself used to announce in, and the one ``PastSessionState`` keeps.
            if changed { announceSetChange(inEntryID: entryID) }
            try await markDone(entryID: entryID, ofSessionID: current.id)
            exercisesWriteFailure = nil
        } catch {
            exercisesWriteFailure = String(describing: error)
        }
        await loadExercises()
    }
}
