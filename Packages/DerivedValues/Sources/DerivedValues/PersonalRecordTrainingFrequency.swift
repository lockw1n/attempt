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
}
