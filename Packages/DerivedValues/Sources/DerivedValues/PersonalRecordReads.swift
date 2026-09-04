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
    /// **An empty cache is recomputed**, because a table cannot tell "nothing has computed this yet"
    /// from "this exercise holds no records"; the walk it costs is the cheap one, since an exercise
    /// with no sets has no entries to fetch them through.
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

    /// One exercise's cached rows, or `nil` where this build did not compute all of them (`G-1.5`).
    ///
    /// **Empty counts as "not current"**, because a table cannot tell "nothing has computed this
    /// yet" from "this exercise holds no records"; the walk it costs is the cheap one, since an
    /// exercise with no sets has no entries to fetch them through.
    private func currentCache(_ exerciseID: UUID) async throws -> [PersonalRecordCache]? {
        let cached = try await cache.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        let current =
            !cached.isEmpty
            && cached.allSatisfy {
                $0.computationVersion == PersonalRecordCalculator.computationVersion
            }
        return current ? cached : nil
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
    /// - Parameter limit: How many entries to return, counted in PR-setting *sets* rather than in
    ///   cached rows.
    /// - Returns: The feed, newest first.
    /// - Throws: Whatever the repository throws reading the cache.
    public func recentRecords(limit: Int) async throws -> [RecentRecord] {
        RecentRecord.feed(
            from: try await cache.personalRecords(includingDeleted: false), limit: limit)
    }
}

/// One cached row as the reads hand it on.
extension PersonalRecordCache {
    /// The record this row holds, with its source set and its day.
    var dated: DatedRecord {
        DatedRecord(weight: weight, sourceSetID: sourceSetID, achievedAt: achievedAt)
    }
}
