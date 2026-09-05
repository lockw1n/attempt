import DerivedValues
import Foundation
import RepositoryInterface

/// The two ways a workout in progress ends, and the sets nobody attempted that Finish has to be
/// answered for first (`FR-1.2.11`, `FR-1.2.12`, `FR-16.4.1`, `FR-16.4.4`).
///
/// **A file of its own rather than the foot of `ActiveSessionStore.swift`**, which had reached
/// SwiftLint's file ceiling: the store grows as the workout gains state, and this grows as the
/// question at the end of one gains answers.
extension ActiveSessionStore {
    /// The sets of the workout in progress nobody has attempted yet (`FR-16.4.1`).
    ///
    /// **Read from the repository rather than off ``exercises``**, and that is what makes the
    /// refusal below true rather than merely usual: the cards are a projection this store drops
    /// while still holding the workout — ``adopt(sessionID:)`` and ``resume()`` both end with a
    /// `forgetExercises()` — and a count taken from them would read *nothing pending* in exactly
    /// that window and end the workout silently, which is the one thing `FR-16.4.4` forbids. It is
    /// also the read the history card's Finish runs, so the two surfaces cannot disagree about what
    /// a workout still owes an answer for.
    ///
    /// - Returns: Its pending sets, oldest first, or none where no workout is held.
    /// - Throws: Whatever the repository throws reading the entries or their sets.
    public func pendingSets() async throws -> [SetEntry] {
        guard let current = session, current.endedAt == nil else { return [] }
        return try await finisher.pendingSets(in: current)
    }

    /// How a workout is ended here — the operation the history card runs too.
    private var finisher: SessionFinish {
        SessionFinish(workouts: repository, records: records)
    }

    /// Finishes the workout in progress (`FR-1.2.11`), answering for its pending sets
    /// (`FR-16.4.4`).
    ///
    /// The row stays: finishing is what `endedAt` records, and a finished session is the history
    /// every later track reads. What ends is this store holding it — ``resume()`` will not find it
    /// again, which is the whole of "incomplete sessions resume on next launch".
    ///
    /// **A workout holding pending sets is not finished without an answer, and the refusal is here
    /// rather than only on the screen.** `FR-16.4.4` is that the conversion is never silent, and a
    /// guard the caller owns is a guard a second caller can forget: without an answer this returns
    /// with the workout untouched and still held, and ``ActiveSessionStore/pendingSetCount`` set to
    /// what the read found — which is what puts the alert in front of the lifter rather than a
    /// session quietly full of missed lifts. A read that fails is a diagnostic, never an empty
    /// answer: a workout is not ended on a count nothing could take.
    ///
    /// A write that fails keeps the workout held and reports the failure, so the next tap is another
    /// attempt at the same command rather than a lost session.
    ///
    /// - Parameter resolution: What to do with the sets nobody attempted, or `nil` where there are
    ///   none to answer for.
    public func finish(resolving resolution: SessionFinish.Resolution? = nil) async {
        guard let current = session, current.endedAt == nil else { return }
        do {
            let pending = try await pendingSets()
            guard
                let resolution = pending.isEmpty
                    ? SessionFinish.Resolution.keepAsFailed : resolution
            else {
                notePendingSets(pending.count)
                return
            }
            notePendingSets(0)
            // The resolution, the end and the record announcement are one operation below this
            // store, because the history card finishes a stale session by exactly the same rule
            // and `TR-1.3` forbids it depending on this package.
            let ended = try await finisher.finish(current, at: .now, resolving: resolution)
            guard let stored = try await repository.session(id: ended.id, includingDeleted: false)
            else {
                throw RepositoryError.recordNotFound(id: ended.id)
            }
            adopt(stored: stored)
        } catch {
            report(error)
            return
        }
        guard let finished = session else { return }
        releaseHeldSession()
        // After the clear, which retires every diagnostic: this one is about the workout that
        // has just ended rather than the one now held (none).
        await advanceProgramRun(after: finished)
    }

    /// Discards the workout in progress (`FR-1.2.12`).
    ///
    /// **Soft, like every deletion here** (`G-1.3`): the repository stamps `deletedAt` and cascades
    /// to the entries and sets underneath, and nothing is removed from the store until an explicit
    /// purge runs. The confirmation `FR-1.2.12` asks for is the screen's — a store cannot ask.
    ///
    /// **The cascade is why this announces** (`FR-1.6.4`). Every set the workout logged stops
    /// standing at once without a single set column being written, so none of ``setWriter``'s five
    /// hooks fires and a record the discarded work set would survive its own source set.
    public func discard() async {
        guard let current = session else { return }
        do {
            try await repository.deleteSession(id: current.id)
            await records.sessionDidChange(id: current.id)
            releaseHeldSession()
        } catch {
            report(error)
        }
    }
}
