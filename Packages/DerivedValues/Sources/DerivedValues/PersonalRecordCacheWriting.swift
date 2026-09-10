import Foundation
import PowerliftingCore
import RepositoryInterface

/// What ``PersonalRecordRecomputer`` writes to `TR-0.3.9`'s cache, and the one trigger that walks
/// more than a handful of exercises (`G-1.5`, `OUT-17.4`, `FR-1.11.4`).
///
/// **Their own file for `PersonalRecordReads.swift`'s reason** — the actor had outgrown SwiftLint's
/// length ceiling again. Nothing about the boundary is semantic; an extension of an actor is
/// isolated to it.
extension PersonalRecordRecomputer {
    /// The bulk trigger: many sessions' worth of sets landed at once (`FR-1.11.4`, `FR-1.6.4`).
    ///
    /// **One walk per exercise, whatever it took to get here**, which is the whole of why it exists.
    /// A restore writes hundreds of sessions and ``sessionDidChange(id:)`` per session is
    /// `O(sessions × per-exercise walk)` — an exercise trained fifty times walked fifty times, each
    /// walk longer than the last as the store fills. Measured over the author's log it was worse than
    /// superlinear: five times the sets cost twenty-one times the time. A caller that knows every
    /// exercise it touched before it announces anything can pay one walk each instead.
    ///
    /// **The caller supplies the exercises, not the sessions**, because resolving sessions to
    /// exercises here would be the same fan-out one layer down — and a restore is holding the entries
    /// already.
    ///
    /// Each failure is swallowed and each success announced separately, on
    /// ``setDidChange(inEntryID:)``'s rule: one exercise that will not recompute is one stale cache,
    /// not a failed restore.
    ///
    /// - Parameter exerciseIDs: Every exercise whose sets moved. Duplicates cost nothing; the set is
    ///   what is walked.
    public func exercisesDidChange(ids exerciseIDs: some Sequence<UUID>) async {
        for exerciseID in Set(exerciseIDs) {
            await refreshRecords(forExerciseID: exerciseID)
        }
    }

    /// What a walk's table is written to the cache as (`G-1.5`, `OUT-17.4`).
    ///
    /// **A table with no cells writes one row, not none.** The marker is what lets the next read
    /// tell "computed, and there is nothing" from "nothing has computed this", which is the whole of
    /// what stops an exercise with a history and no qualifying record walking it on every read —
    /// see ``repMaxes(forExerciseID:)``. It carries this build's version like every other row, so
    /// nothing has to drop it separately when the rules move.
    ///
    /// Internal rather than private: the walk that calls it is in the actor's own file.
    ///
    /// - Parameter schemeRecords: What the walk found.
    /// - Returns: The rows to store — one per cell, or the marker.
    static func cacheValues(for schemeRecords: [DatedSchemeRecord]) -> [PersonalRecordCacheValues] {
        guard !schemeRecords.isEmpty else {
            return [.confirmedZero(computationVersion: PersonalRecordCalculator.computationVersion)]
        }
        return schemeRecords.map {
            PersonalRecordCacheValues(
                repCount: $0.scheme.reps,
                setCount: $0.scheme.sets,
                weight: $0.record.weight,
                sourceSetID: $0.record.sourceSetID,
                achievedAt: $0.record.achievedAt,
                previousWeight: $0.previous,
                computationVersion: PersonalRecordCalculator.computationVersion)
        }
    }
}
