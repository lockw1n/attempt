import Foundation
import PowerliftingCore
import RepositoryInterface

/// How much of each exercise the lifter has actually been doing lately (`FR-16.5.1`).
///
/// A file of its own rather than more of ``PersonalRecordRecomputer``, on
/// ``PersonalRecordEstimateWindow``'s reason: same actor, same isolation, one length ceiling.
extension PersonalRecordRecomputer {
    /// Every exercise with a completed working set inside the lookback window, most-trained first.
    ///
    /// **Most-trained means the most completed working sets, not the most sessions.** A lifter who
    /// squats twice a week for five sets is doing more squatting than one who benches three times
    /// for two, and the set is the unit the rest of this module already counts training in —
    /// ``Tonnage/counts(_:)`` is the same population `FR-1.9.5`'s week and `FR-1.5.1`'s session are
    /// summed over, so "trained" means one thing in the app.
    ///
    /// **The one cross-exercise walk in this actor, and its caller is what keeps it off `NFR-1.6`'s
    /// path.** Everything else here computes one exercise at a time by design; this answers a
    /// question about all of them, so it is read only where the dashboard has to choose lifts for a
    /// lifter who never has — a configured selection carries its identifiers on the settings row and
    /// never asks. The walk itself is the window's, not the history's: one ranged session read plus
    /// an entry read per session and a set read per entry, all bounded by ``E1RMLookback``.
    ///
    /// **Ties break on the identifier, and that is a tiebreak rather than a claim.** Two exercises
    /// trained equally often are equally good answers; what matters is that the same lifter gets the
    /// same tile on every launch rather than whichever order the store happened to return.
    ///
    /// Deleted sessions, entries and sets are excluded — a discarded workout is not training done.
    ///
    /// - Returns: The exercise identifiers, most completed working sets first.
    public func mostTrainedExerciseIDs() async throws -> [UUID] {
        let sessions = try await workouts.sessions(
            in: lookback.range(from: now()), includingDeleted: false)
        var counts: [UUID: Int] = [:]
        for session in sessions {
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries {
                let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                let performed = sets.count(where: Tonnage.counts)
                if performed > 0 { counts[entry.exerciseID, default: 0] += performed }
            }
        }
        return counts.keys.sorted { left, right in
            let (first, second) = (counts[left] ?? 0, counts[right] ?? 0)
            return first == second ? left.uuidString < right.uuidString : first > second
        }
    }

    /// When each exercise was last trained, for the picker's **Trained** section (`FR-16.5.3`).
    ///
    /// **The same walk and the same window as ``mostTrainedExerciseIDs()``, answering the other
    /// question about it.** That one ranks by how much; this one reports when. They are separate
    /// functions rather than one returning both because their callers are separate — the tiles
    /// choose lifts and never ask for a date, and the picker dates rows it does not rank — and a
    /// caller paying for an answer it discards is how a bounded read stops being bounded.
    ///
    /// **A session's *date* rather than the instant a set was written**, which is
    /// ``E1RMLookback``'s distinction and matters for the same reason: a set corrected today
    /// belongs to the workout it was performed in, so a history edit must not date an exercise to
    /// the day it was edited.
    ///
    /// **Bounded by the lookback window, so the section it fills is bounded too.** An exercise
    /// trained before the window is absent here and falls to the picker's remainder — which is the
    /// same population `FR-16.5.1` calls "has history", and the picker promises to open on exactly
    /// what the tiles chose. An unbounded read would make the two disagree and would put a full
    /// walk of the log behind a tap.
    ///
    /// A completed working set is what counts, ``Tonnage/counts(_:)``'s population — an exercise
    /// warmed up and abandoned was not trained. Deleted rows are excluded throughout.
    ///
    /// - Returns: The most recent session date per exercise, for exercises trained in the window.
    public func lastTrainedDates() async throws -> [UUID: Date] {
        let sessions = try await workouts.sessions(
            in: lookback.range(from: now()), includingDeleted: false)
        var latest: [UUID: Date] = [:]
        for session in sessions {
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries {
                let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
                guard sets.contains(where: Tonnage.counts) else { continue }
                if let seen = latest[entry.exerciseID], seen >= session.date { continue }
                latest[entry.exerciseID] = session.date
            }
        }
        return latest
    }
}
