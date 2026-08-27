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
    /// The entries of this exercise that fall inside the lookback window (`FR-1.7.1`), each with the
    /// day its session was performed on.
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
    /// **It reports the day as well as the membership**, which is what makes `FR-1.9.1`'s delta free:
    /// the session row is already in hand here, so dating every in-window set costs nothing, where
    /// asking for the dates afterwards would be two reads per set.
    func entryDatesInWindow(forExerciseID exerciseID: UUID) async throws -> [UUID: Date] {
        let sessions = try await workouts.sessions(
            in: lookback.range(from: now()), includingDeleted: false)
        var dates: [UUID: Date] = [:]
        for session in sessions {
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries where entry.exerciseID == exerciseID {
                dates[entry.id] = session.date
            }
        }
        return dates
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

    /// `FR-1.9.1`'s "previous value": the best estimate this exercise held **before the day the
    /// current one was set**, or `nil` when it held none.
    ///
    /// **A day and not a set**, which is the whole of the definition. The alternative — the
    /// next-best set — would report a ranking *within* one session as a change over time, so a
    /// lifter whose top single and back-off single were both logged on Tuesday would be told their
    /// maximum moved between them. Excluding the whole day makes the delta answer the question a
    /// tile is actually asking: what did this number just replace.
    ///
    /// **It is read over the same window and never outside it** (`FR-1.7.1`). A value from before
    /// the window is one the tile has not shown for months, and a delta against it would compare
    /// today's number with one this app stopped displaying — the window's own rule, applied to the
    /// comparison as well as to the number.
    ///
    /// **An estimate that was matched and not beaten has none**, which follows from the tie rule
    /// rather than from this one: `PersonalRecordCalculator` resolves a tie to the *earlier* set, so
    /// a repeated best keeps the day it first appeared on and nothing precedes it. That is the
    /// honest reading — the number has not moved since the day it was set.
    ///
    /// It costs no read: the sets and their days are the ones the estimate was computed over.
    func previous(
        before current: DatedRecord,
        over inWindow: [(SetEntry, SetRecord)],
        using dates: [UUID: Date],
        by calculator: PersonalRecordCalculator
    ) -> DatedRecord? {
        let earlier = inWindow.filter { day(of: $0.0, using: dates) < current.achievedAt }
        guard let best = calculator.bestE1RM(in: earlier.map(\.1)) else { return nil }
        return dated(best, over: earlier, using: dates)
    }

    /// The day a set belongs to — its session's, or its own timestamps where the session did not
    /// resolve. ``dated(_:over:using:)``'s fallback, as one expression both callers share.
    func day(of set: SetEntry, using dates: [UUID: Date]) -> Date {
        dates[set.entryID] ?? set.completedAt ?? set.createdAt
    }
}
