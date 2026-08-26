import Foundation
import PowerliftingCore
import RepositoryInterface

/// Recomputes one exercise's personal records and estimated maximum, off the main actor (`TR-1.5`,
/// `TR-1.6`, `FR-1.6.1`, `FR-1.6.4`).
///
/// **An actor, and nothing observable lives on it.** `@Observable` records reads on whichever actor
/// performs them, so a store held here would notify SwiftUI from a background actor; the surface is
/// `async` functions returning `Sendable` values, and ``ExerciseRecordsState`` is what a screen
/// binds to. An in-flight recompute is abandoned by the *state*, which holds the task — this cannot
/// know that a newer request made its work irrelevant.
///
/// **One exercise at a time, always** (`FR-1.6.4`). Nothing here recomputes a catalogue: a set
/// belongs to one exercise, records are never compared across exercises, and a full-catalogue pass
/// on every logged set is the shape `NFR-1.6` rules out. ``formulaDidChange(to:)`` is not an
/// exception — it recomputes nothing at all, it says the estimates are stale.
///
/// **Two reads, because the two halves are cached differently.** ``repMaxes(forExerciseID:)``
/// answers from `TR-0.3.9`'s cache whenever the stored `computationVersion` is the one this build
/// computes under, so the common read costs no walk at all (`G-1.5`: a stale value is invalidated by
/// version mismatch, not by recomputing eagerly). ``estimatedMax(forExerciseID:)`` always walks,
/// because an estimate depends on a formula setting and one scalar cannot carry a setting — which is
/// also what makes `FR-1.7.3`'s retroactive recalculation free.
public actor PersonalRecordRecomputer {
    /// The sets to compute over, and the entries and sessions a record is dated from.
    private let workouts: any WorkoutRepository

    /// The N-rep max cache (`TR-0.3.9`).
    private let cache: any PersonalRecordCacheRepository

    /// The formula estimates are produced under (`TR-0.3.8`, `FR-1.7.2`).
    private var formula: E1RMFormulaID

    /// The subscribers ``changes()`` handed a stream to, keyed by a token their termination carries.
    private var subscribers: [UUID: AsyncStream<RecordChange>.Continuation] = [:]

    /// Builds the recomputer over the two repositories it reads and writes.
    ///
    /// - Parameters:
    ///   - workouts: Sessions, their entries and their sets.
    ///   - cache: Where the N-rep maxes are stored between recomputes.
    ///   - formula: The formula estimates start under, until ``formulaDidChange(to:)`` moves it.
    public init(
        workouts: any WorkoutRepository,
        cache: any PersonalRecordCacheRepository,
        formula: E1RMFormulaID = .defaultFormula
    ) {
        self.workouts = workouts
        self.cache = cache
        self.formula = formula
    }

    // MARK: - Publication

    /// A stream of what has been recomputed, for as long as the caller holds it (`TR-1.5`).
    ///
    /// **One stream per subscriber, not one shared one.** Several screens read the same derived
    /// value at once — a PR list, a badge on the set being logged, a dashboard tile — and an
    /// `AsyncStream` has a single consumer, so a shared one would deliver each change to whichever
    /// screen happened to be awaiting it.
    ///
    /// Finishing or discarding the stream unregisters it; a subscriber that goes away without doing
    /// either leaks one continuation until the process ends, which is what `onTermination` is for.
    public func changes() -> AsyncStream<RecordChange> {
        let (stream, continuation) = AsyncStream<RecordChange>.makeStream()
        let token = UUID()
        subscribers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.endSubscription(token) }
        }
        return stream
    }

    /// How many live subscriptions ``changes()`` has handed out.
    ///
    /// Internal rather than public: nothing in the app has a use for the number, and a test that
    /// publishes before its subscriber is registered asserts on an announcement nobody heard — which
    /// is a race that passes far more often than it fails.
    var subscriberCount: Int { subscribers.count }

    /// Drops a terminated subscriber's continuation.
    private func endSubscription(_ token: UUID) {
        subscribers[token] = nil
    }

    /// Tells every subscriber what moved.
    private func publish(_ change: RecordChange) {
        for continuation in subscribers.values { continuation.yield(change) }
    }

    // MARK: - Reads

    /// One exercise's N-rep maxes, from the cache when it is current (`FR-1.6.1`, `G-1.5`).
    ///
    /// **An empty cache is recomputed**, because a table cannot tell "nothing has computed this yet"
    /// from "this exercise holds no records". The walk it costs is the cheap one — an exercise with
    /// no sets has no entries to fetch them through.
    ///
    /// **Every row has to match, not just one.** A partially-written cache — a bumped version
    /// landing mid-write, or a restore of a backup taken under older rules — would otherwise be read
    /// as current on the strength of whichever row was checked.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The records, ascending by rep count.
    /// - Throws: Whatever the repositories throw reading the cache, or recomputing.
    public func repMaxes(forExerciseID exerciseID: UUID) async throws -> [DatedRepMax] {
        let cached = try await cache.personalRecords(
            forExerciseID: exerciseID, includingDeleted: false)
        let current =
            !cached.isEmpty
            && cached.allSatisfy {
                $0.computationVersion == PersonalRecordCalculator.computationVersion
            }
        guard current else { return try await recompute(forExerciseID: exerciseID).repMaxes }
        return cached.map {
            DatedRepMax(
                reps: $0.repCount,
                record: DatedRecord(
                    weight: $0.weight, sourceSetID: $0.sourceSetID, achievedAt: $0.achievedAt))
        }
    }

    /// One exercise's best estimated one-rep maximum under the formula in force (`FR-1.7.1`).
    ///
    /// Never cached and never read from the cache — see this type's note, and
    /// `PersonalRecordCacheEntity`, which says why the column does not exist.
    ///
    /// - Parameter exerciseID: The exercise.
    /// - Returns: The estimate, or `nil` when no set yielded one.
    /// - Throws: Whatever the repository throws reading the exercise's sets.
    public func estimatedMax(forExerciseID exerciseID: UUID) async throws -> DatedRecord? {
        try await recomputed(exerciseID, writingCache: false).bestE1RM
    }

    /// The formula estimates are currently produced under.
    public func formulaInForce() -> E1RMFormulaID { formula }

    // MARK: - Triggers

    /// Recomputes one exercise and stores the result (`FR-1.6.4`, `TR-1.6`).
    ///
    /// - Parameter exerciseID: The exercise whose sets moved.
    /// - Returns: What the recompute produced — both halves, from the one walk.
    /// - Throws: Whatever the repositories throw reading the sets or writing the cache.
    @discardableResult
    public func recompute(forExerciseID exerciseID: UUID) async throws -> ExerciseRecords {
        let records = try await recomputed(exerciseID, writingCache: true)
        publish(.exercise(exerciseID))
        return records
    }

    /// The set-mutation trigger: a set under `entryID` was logged, edited, marked or deleted
    /// (`FR-1.6.4`, `TR-1.6`).
    ///
    /// **Every writer of a set column calls this, and it takes the entry rather than the exercise**
    /// — an entry is what a set names, so this is the identifier every call site already has, and
    /// resolving it here is what stops five call sites each doing it slightly differently.
    ///
    /// **A failure is swallowed and nothing is published.** This runs behind the user's write: the
    /// set is already stored, and failing the logging of a set because a derived value could not be
    /// refreshed would cost the user data to protect a number that is recomputed anyway (`G-1.4`).
    /// The cache keeps whatever it held, so it is stale rather than wrong, and the next mutation
    /// retries.
    ///
    /// - Parameter entryID: The exercise entry the changed set belongs to.
    public func setDidChange(inEntryID entryID: UUID) async {
        guard let entry = try? await workouts.entry(id: entryID, includingDeleted: true) else {
            return
        }
        _ = try? await recompute(forExerciseID: entry.exerciseID)
    }

    /// The settings trigger: the e1RM formula changed (`FR-1.6.4`, `FR-1.7.3`, `TR-1.6`).
    ///
    /// **This is the point `T-1.43` wires the formula picker into**, and it is deliberately not a
    /// recompute. Nothing needs invalidating: the cache holds N-rep maxes, which read no setting at
    /// all, and an estimate is computed on every read. What the app has to do is *re-read*, which is
    /// what ``RecordChange/everyExercise`` tells every subscriber to do.
    ///
    /// A formula that is already in force publishes nothing — a redundant announcement would make
    /// every screen in the app walk its exercise's history for an answer that cannot have moved.
    ///
    /// - Parameter formula: The formula now chosen.
    public func formulaDidChange(to formula: E1RMFormulaID) {
        guard formula != self.formula else { return }
        self.formula = formula
        publish(.everyExercise)
    }

    // MARK: - The computation

    /// One walk, both calculators, and the cache written if asked.
    ///
    /// **A set the analytical type refuses is left out of the computation rather than failing it.**
    /// `SetEntry` stores what was logged and `SetRecord` validates, so a row carrying a value this
    /// build considers out of range — a newer version's, or a corrupt one's — would otherwise cost
    /// the user every record for that exercise rather than the one set. Both arrays are built from
    /// the same filtered sequence, which is what keeps `PersonalRecord`'s offsets pointing at the
    /// set that actually holds the record.
    private func recomputed(
        _ exerciseID: UUID, writingCache: Bool
    ) async throws -> ExerciseRecords {
        let stored = try await workouts.sets(forExerciseID: exerciseID, includingDeleted: false)
        let analysed = stored.compactMap { set in (try? set.setRecord()).map { (set, $0) } }

        let calculator = PersonalRecordCalculator(e1rm: E1RMCalculator(formula))
        let computed = calculator.records(in: analysed.map(\.1))

        let holding =
            computed.repMaxes.map { analysed[$0.record.setOffset].0 }
            + (computed.bestE1RM.map { [analysed[$0.setOffset].0] } ?? [])
        let dates = await sessionDates(forEntryIDs: Set(holding.map(\.entryID)))

        let repMaxes = computed.repMaxes.map { repMax in
            DatedRepMax(
                reps: repMax.reps,
                record: dated(repMax.record, over: analysed, using: dates))
        }
        let bestE1RM = computed.bestE1RM.map { dated($0, over: analysed, using: dates) }

        if writingCache {
            try await cache.replacePersonalRecords(
                forExerciseID: exerciseID,
                with: repMaxes.map {
                    PersonalRecordCacheValues(
                        repCount: $0.reps,
                        weight: $0.record.weight,
                        sourceSetID: $0.record.sourceSetID,
                        achievedAt: $0.record.achievedAt,
                        computationVersion: PersonalRecordCalculator.computationVersion)
                })
        }

        return ExerciseRecords(
            exerciseID: exerciseID, repMaxes: repMaxes, bestE1RM: bestE1RM, formula: formula)
    }

    /// The record with the set at its offset resolved to an identity and a date.
    ///
    /// **The offset is an index into `analysed`, not into what the repository returned**, and the
    /// two differ whenever a set was refused — see ``recomputed(_:writingCache:)``.
    private func dated(
        _ record: PersonalRecord,
        over analysed: [(SetEntry, SetRecord)],
        using dates: [UUID: Date]
    ) -> DatedRecord {
        let set = analysed[record.setOffset].0
        return DatedRecord(
            weight: record.weight,
            sourceSetID: set.id,
            achievedAt: dates[set.entryID] ?? set.completedAt ?? set.createdAt)
    }

    /// The session date behind each of `entryIDs`, for the ones that resolve.
    ///
    /// **At most eleven entries, however long the history is.** Only a set that actually holds a
    /// record is looked up, and there are ten rep maxes and one estimate; a walk over the exercise's
    /// sessions to date the same eleven is what `NFR-1.6` puts out of reach.
    ///
    /// **Deleted entries and sessions are read**, for the reason the repository's own set ordering
    /// reads them: the row is wanted for its date rather than for itself, and a live set under a
    /// deleted session is a foreign row whose record still has to be dated.
    ///
    /// A row that will not resolve is simply absent, and the caller falls back to the set's own
    /// timestamps rather than to a sentinel.
    private func sessionDates(forEntryIDs entryIDs: Set<UUID>) async -> [UUID: Date] {
        var dates: [UUID: Date] = [:]
        for entryID in entryIDs {
            guard let entry = try? await workouts.entry(id: entryID, includingDeleted: true),
                let session = try? await workouts.session(
                    id: entry.sessionID, includingDeleted: true)
            else { continue }
            dates[entryID] = session.date
        }
        return dates
    }
}
