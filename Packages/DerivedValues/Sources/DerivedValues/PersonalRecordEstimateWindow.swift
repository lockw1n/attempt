import Foundation
import PowerliftingCore
import RepositoryInterface

/// `FR-1.7.1`'s window: which of an exercise's entries it admits, and what to say when the sets it
/// admits produce no estimate.
///
/// A file of its own rather than more of ``PersonalRecordRecomputer``, which had reached SwiftLint's
/// length ceiling — ``PersonalRecordSourceLinks``' reason. It is the same actor and the same
/// isolation.
extension PersonalRecordRecomputer {
    /// The entries of this exercise that fall inside the lookback window (`FR-1.7.1`).
    ///
    /// **Read forwards from the sessions, not backwards from the sets**, and that is what bounds the
    /// walk. Dating every set costs two reads per session the exercise was ever trained in, which is
    /// unbounded in the history; one ranged read plus one entry read per session inside the window is
    /// bounded by the *window*, so a ten-year history costs what a three-month one does.
    ///
    /// It also settles which date the window reads: the session's, the same one
    /// ``DatedRecord/achievedAt`` reports. A filter on a set's own timestamps would pull a set
    /// corrected today into the window on behalf of a workout performed last year.
    ///
    /// Deleted sessions and entries are excluded: a discarded workout is not current work.
    func entryIDsInWindow(forExerciseID exerciseID: UUID) async throws -> Set<UUID> {
        let sessions = try await workouts.sessions(
            in: lookback.range(from: now()), includingDeleted: false)
        var entryIDs: Set<UUID> = []
        for session in sessions {
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries where entry.exerciseID == exerciseID { entryIDs.insert(entry.id) }
        }
        return entryIDs
    }

    /// Why there is no estimate (`FR-1.13.3`).
    ///
    /// **The nearest miss, not the commonest one**: a lifter whose warmups sit beside one twelve-rep
    /// working set is owed the sentence about the rep range. `E1RMRefusal`'s ordering is what
    /// "nearest" means, and it lives there rather than here.
    ///
    /// - Parameters:
    ///   - hasSets: Whether anything at all has been logged against the exercise.
    ///   - inWindow: The in-window sets, none of which produced an estimate.
    ///   - estimator: The calculator whose refusals these are — the same one that was asked.
    func absence(
        hasSets: Bool, inWindow: [(SetEntry, SetRecord)], under estimator: E1RMCalculator
    ) -> EstimateAbsence {
        guard hasSets else { return .noSetsLogged }
        let refusals = inWindow.compactMap { pair -> E1RMRefusal? in
            guard case .refused(let why) = estimator.outcome(for: pair.1) else { return nil }
            return why
        }
        guard let nearest = refusals.max() else { return .noneInWindow }
        return .refused(nearest)
    }
}
