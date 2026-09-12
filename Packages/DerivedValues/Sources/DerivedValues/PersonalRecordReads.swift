import Foundation
import PowerliftingCore
import RepositoryInterface

/// ``PersonalRecordRecomputer``'s reads (`FR-1.6.1`, `FR-1.6.5`, `FR-1.7.1`, `FR-16.2.1`).
///
/// **Their own file for the reason `FR-1.6.2`'s link resolution has one**: the actor had outgrown
/// SwiftLint's length ceiling, and `TR-16.1`'s second dimension added a third read to it. Nothing
/// about the boundary is semantic — an extension of an actor is isolated to it.
extension PersonalRecordRecomputer {
    /// One exercise's N-rep maxes, from the cache when it is current (`FR-1.6.1`, `G-1.5`).
    ///
    /// **An empty cache is recomputed and a marked one is not** (`OUT-17.4`). A table can now tell
    /// "nothing has computed this yet" from "this exercise holds no records", because a walk that
    /// finds nothing writes ``RepositoryInterface/PersonalRecordCacheMarker``'s row to say so — so
    /// an exercise trained only for warmups, or only past the rep range, stops walking its whole
    /// history on every read. `T-1.40`'s reasoning for the old answer was sound about the exercise
    /// it considered, one with no sets at all, and that is the one case the marker does not change.
    ///
    /// **A miss recomputes but announces nothing.** Publication belongs to the triggers below. A
    /// read that published would be told to read again by every subscriber it woke, and an exercise
    /// holding no records caches nothing to stop the next pass — so what looks like a slow path is an
    /// unbounded loop, for exactly the exercises that hold no records.
    ///
    /// **Every row has to match, not just one.** A partially-written cache — a bumped version landing
    /// mid-write, or a restore of a backup taken under older rules — would otherwise read as current
    /// on the strength of whichever row was checked. See ``currentCache(_:)``.
    ///
    /// **The `sets == 1` column of `FR-16.2.1`'s table and nothing else.** A rep max is the one-set
    /// scheme, so the filter is the definition rather than a narrowing of it — and it is what keeps
    /// every `FR-1.6.x` reader, the badge included, seeing exactly the ten rows it always did.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The records, ascending by rep count.
    /// - Throws: Whatever the repositories throw reading the cache, or recomputing.
    public func repMaxes(forExerciseID exerciseID: UUID) async throws -> [DatedRepMax] {
        guard let cached = try await currentCache(exerciseID) else {
            return try await walked(exerciseID, writingCache: true).repMaxes
        }
        return cached.filter { $0.setCount == 1 }.map {
            DatedRepMax(reps: $0.repCount, record: $0.dated)
        }
    }

    /// One exercise's whole scheme table, from the cache when it is current (`FR-16.2.1`, `G-1.5`).
    ///
    /// ``repMaxes(forExerciseID:)``'s shape exactly, and every note on it applies — this is the
    /// unfiltered read of the same rows, and the two never disagree because there is one table.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The records, ascending by ``DatedSchemeRecord/scheme``.
    /// - Throws: Whatever the repositories throw reading the cache, or recomputing.
    public func schemeRecords(forExerciseID exerciseID: UUID) async throws -> [DatedSchemeRecord] {
        guard let cached = try await currentCache(exerciseID) else {
            return try await walked(exerciseID, writingCache: true).schemeRecords
        }
        return cached.map {
            DatedSchemeRecord(scheme: $0.scheme, record: $0.dated, previous: $0.previousWeight)
        }
    }

    /// One exercise's cached records, or `nil` where this build did not compute them (`G-1.5`).
    ///
    /// **Empty is still "not current", and an empty answer is not empty rows** (`OUT-17.4`). A walk
    /// that finds no record writes ``RepositoryInterface/PersonalRecordCacheMarker``'s row, so the
    /// table distinguishes the two: no rows at all means nothing has computed this exercise, and the
    /// marker alone means something has and there is nothing to hold. The marker is stripped here,
    /// so the callers above see the empty list rather than a row claiming a record it does not hold.
    private func currentCache(_ exerciseID: UUID) async throws -> [PersonalRecordCache]? {
        let cached = try await cache.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        let current =
            !cached.isEmpty
            && cached.allSatisfy {
                $0.computationVersion == PersonalRecordCalculator.computationVersion
            }
        return current ? cached.filter { !$0.isConfirmedZero } : nil
    }

    /// One exercise's best estimate, under the formula and window in force (`FR-1.7.1`).
    ///
    /// Never cached and never read from the cache — see this type's note, and
    /// `PersonalRecordCacheEntity`, which says why the column does not exist.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The estimate, or why there is none — see ``EstimatedMax``.
    /// - Throws: Whatever the repository throws reading the exercise's sets.
    public func estimatedMax(forExerciseID exerciseID: UUID) async throws -> EstimatedMax {
        try await recomputed(exerciseID, writingCache: false).estimate
    }

    /// `FR-1.6.5`'s global feed: the most recent PR-setting sets, across every exercise.
    ///
    /// **The cache is read and nothing is recomputed** — the one read here that cannot fall back to a
    /// walk, deliberately. A miss on one exercise is answered by recomputing it because a walk of one
    /// exercise's sets is what `NFR-1.6` budgets; a miss here would be a walk of the whole catalogue
    /// on the screen the app launches into. What a row this build did not compute costs the feed is
    /// written on ``RecentRecord/feed(from:limit:)``.
    ///
    /// **The filter's exercise scope is applied to the cached rows and its scheme and baseline
    /// rules to the grouped events** — and neither reads a set history. `FR-17.3.1` withdrew the
    /// threshold that did, so this read is bounded by the cache whatever the scope is (`NFR-17.2`):
    /// the widest configuration `FR-16.3.4`'s offer can write costs one cache read on the tab the
    /// app launches into, where it used to cost a walk of every exercise it had to reach.
    ///
    /// - Parameters:
    ///   - limit: How many entries to return, counted in PR-setting *runs* rather than in cached
    ///     rows, and counted *after* filtering — five entries means five the lifter can read.
    ///   - filter: What the feed is narrowed to (`FR-16.3.1`, `FR-17.3.2`, `FR-16.3.4`).
    /// - Returns: The feed, newest first.
    /// - Throws: Whatever the repository throws reading the cache.
    public func recentRecords(
        limit: Int, filter: RecentRecordsFilter = .unfiltered
    ) async throws -> [RecentRecord] {
        guard limit > 0 else { return [] }
        // The markers are dropped before anything groups: every confirmed-zero exercise's row names
        // the same set, so a feed that kept them would read one event holding all of them.
        let cached = try await cache.personalRecords(includingDeleted: false)
            .filter { !$0.isConfirmedZero }
        let scoped =
            filter.exerciseIDs.map { ids in cached.filter { ids.contains($0.exerciseID) } } ?? cached
        // Grouped without a bound, because the bound counts what survives: a limit applied here
        // would be a limit on candidates, and a scope that filtered nine of ten would draw one row.
        let events = RecentRecord.feed(from: scoped, limit: Int.max)
        return Array(events.lazy.filter(filter.admits).prefix(limit))
    }
}

/// One cached row as the reads hand it on.
extension PersonalRecordCache {
    /// The record this row holds, with its source set and its day.
    var dated: DatedRecord {
        DatedRecord(weight: weight, sourceSetID: sourceSetID, achievedAt: achievedAt)
    }
}
