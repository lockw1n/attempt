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
/// **Two kinds of read, because the two halves are cached differently.** ``repMaxes(forExerciseID:)``
/// answers from `TR-0.3.9`'s cache whenever the stored `computationVersion` is the one this build
/// computes under, so the common read costs no walk at all (`G-1.5`: a stale value is invalidated by
/// version mismatch, not by recomputing eagerly). ``estimatedMax(forExerciseID:)`` always walks,
/// because an estimate depends on a formula setting and one scalar cannot carry a setting — which is
/// also what makes `FR-1.7.3`'s retroactive recalculation free. They also read different sets: a rep
/// max is all-time (`FR-1.6.1`) where an estimate reads only `FR-1.7.1`'s lookback window, so an
/// exercise can hold a year-old 5RM and no current estimate at all — and when it holds neither, the
/// estimate says which of those it is (``EstimateAbsence``).
public actor PersonalRecordRecomputer {
    /// The sets to compute over, and the entries and sessions a record is dated from.
    ///
    /// Internal rather than private only so `FR-1.6.2`'s link resolution can live in its own file —
    /// this type had outgrown SwiftLint's length ceiling. Nothing outside this module can see it.
    let workouts: any WorkoutRepository

    /// The scheme-record cache (`TR-0.3.9`, `TR-16.1`).
    ///
    /// Internal rather than private on ``workouts``' rule, so the reads over it can live in their
    /// own file.
    let cache: any PersonalRecordCacheRepository

    /// The formula estimates are produced under (`TR-0.3.8`, `FR-1.7.2`).
    private var formula: E1RMFormulaID

    /// How far back an estimate looks (`FR-1.7.1`).
    ///
    /// Internal rather than private, on ``workouts``' rule, so the window's own arithmetic can live
    /// in its own file. Nothing outside this module can see it.
    var lookback: E1RMLookback

    /// What "now" is when the window is measured — injectable, so a boundary can be asserted rather
    /// than waited for.
    ///
    /// Internal for ``lookback``'s reason.
    let now: @Sendable () -> Date

    /// The subscribers ``changes()`` handed a stream to, keyed by a token their termination carries.
    private var subscribers: [UUID: AsyncStream<RecordChange>.Continuation] = [:]

    /// The latest cache-writing recompute started per exercise, so an older one can tell that it is
    /// no longer the answer.
    ///
    /// **An actor serialises, which is not the same as ordering its results.** Two recomputes of one
    /// exercise interleave at their `await` points, so the row is written by whichever *finishes*
    /// last — and measured, the one that finishes last is the one holding the older sets. A counter
    /// rather than a lock, because what is missing is not exclusion but a way for a call to know its
    /// own work has been superseded; a lock would serialise two walks that need not both happen. One
    /// entry per exercise ever recomputed and never removed: an exercise is a catalogue row, so the
    /// map is bounded by the catalogue rather than by the training history.
    private var writeGenerations: [UUID: Int] = [:]

    /// Builds the recomputer over the two repositories it reads and writes.
    ///
    /// **No catalogue among them, since `D-16.1`.** It was held for one column — `FR-1.7.5`'s
    /// manual override — and a record is now what the lifter's sets say, with nothing to read from
    /// the exercise row.
    ///
    /// - Parameters:
    ///   - workouts: Sessions, their entries and their sets.
    ///   - cache: Where the N-rep maxes are stored between recomputes.
    ///   - formula: The formula estimates start under, until ``formulaDidChange(to:)`` moves it.
    ///   - lookback: The window estimates read, until ``lookbackDidChange(to:)`` moves it.
    ///   - now: What the window is measured back from.
    public init(
        workouts: any WorkoutRepository,
        cache: any PersonalRecordCacheRepository,
        formula: E1RMFormulaID = .defaultFormula,
        lookback: E1RMLookback = .default,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.workouts = workouts
        self.cache = cache
        self.formula = formula
        self.lookback = lookback
        self.now = now
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
    ///
    /// Internal rather than private on ``workouts``' rule: a trigger may live in its own file.
    func publish(_ change: RecordChange) {
        for continuation in subscribers.values { continuation.yield(change) }
    }

    /// The formula estimates are currently produced under.
    public func formulaInForce() -> E1RMFormulaID { formula }

    /// The window estimates are currently read over.
    public func lookbackInForce() -> E1RMLookback { lookback }

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
        await refreshRecords(forExerciseID: entry.exerciseID)
    }

    /// The session trigger: a whole session was discarded or restored (`FR-1.6.4`, `FR-1.2.12`).
    ///
    /// **The sixth writer, and it is not a writer of a set column** — which is why
    /// ``setDidChange(inEntryID:)``'s five call sites do not cover it. Discarding a workout
    /// soft-deletes the session and cascades to every entry and set under it (`G-1.3`), so records
    /// the discarded sets held stop standing without any set column being written. Left unhooked,
    /// the cache keeps a record whose source set is deleted, and `FR-1.6.2`'s link navigates to it.
    ///
    /// **Every exercise the session touched, once each.** A session names a bounded handful of
    /// entries and two of them can name the same exercise, so the walk is per distinct exercise —
    /// still `FR-1.6.4`'s scope rather than a catalogue pass.
    ///
    /// A failure is swallowed for ``setDidChange(inEntryID:)``'s reason: the session is already
    /// discarded, and the cache is stale rather than wrong.
    ///
    /// - Parameter sessionID: The session whose sets moved. Read including deleted rows, since the
    ///   ordinary caller has just deleted it.
    public func sessionDidChange(id sessionID: UUID) async {
        guard
            let entries = try? await workouts.entries(
                forSessionID: sessionID, includingDeleted: true)
        else { return }
        for exerciseID in Set(entries.map(\.exerciseID)) {
            await refreshRecords(forExerciseID: exerciseID)
        }
    }

    /// What both set-mutation triggers actually do: rewrite the cache, then announce.
    ///
    /// **`FR-1.7.1`'s window is not read here, and that is the point of the method existing.** An
    /// estimate depends on a setting no cache can carry, so a trigger computing one would throw it
    /// away — and computing it costs a ranged session read plus one entry read per session inside
    /// the window, on the path that runs behind every logged set (`NFR-1.6`). The subscribers this
    /// wakes re-read the estimate for themselves, which is where the window belongs.
    ///
    /// A failure is swallowed, for ``setDidChange(inEntryID:)``'s reason.
    ///
    /// - Parameter exerciseID: The exercise whose sets moved.
    private func refreshRecords(forExerciseID exerciseID: UUID) async {
        guard (try? await walked(exerciseID, writingCache: true)) != nil else { return }
        publish(.exercise(exerciseID))
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

    /// The other settings trigger: the lookback window changed (`FR-1.7.1`).
    ///
    /// ``formulaDidChange(to:)``'s shape exactly, and for its reasons — a window moves no rep max, so
    /// nothing is invalidated and every subscriber is told to read the estimate again. One already in
    /// force publishes nothing.
    ///
    /// - Parameter lookback: The window now chosen.
    public func lookbackDidChange(to lookback: E1RMLookback) {
        guard lookback != self.lookback else { return }
        self.lookback = lookback
        publish(.everyExercise)
    }

    /// The third settings trigger: a recent-PR preference moved (`FR-16.3.1`, `FR-16.3.2`,
    /// `FR-16.3.4`).
    ///
    /// **It publishes unconditionally, where the other two compare first**, because this actor does
    /// not hold the preference. A formula and a window are in force *here* — they are what an
    /// estimate is computed under — so a redundant announcement is one this type can recognise. The
    /// feed's scope lives on the settings row and is read by the screen, so all this can say is that
    /// the row was written; the caller writing it is the one that knows whether anything changed.
    ///
    /// Nothing is invalidated, on ``formulaDidChange(to:)``'s rule: the cache holds cells, which read
    /// no setting. What is stale is which of them a screen draws.
    public func recentRecordsPreferencesDidChange() {
        publish(.everyExercise)
    }

    /// The fourth trigger: an exercise's training max was written (`FR-15.1.4`, `FR-15.1.8`).
    ///
    /// **Nothing here is invalidated, and no record moved.** A training max is what a *future* load
    /// is read against; the sets already logged are unchanged, so the cache is untouched and the
    /// only thing stale is what a screen draws beside a number — `FR-15.1.8`'s line under a tile,
    /// and `FR-16.7.1`'s percentage. This actor is the app's one announcement channel (`TR-1.5`),
    /// which is why a repository write reaches a screen in another tab through it.
    ///
    /// **``RecordChange/exercise(_:)`` rather than ``RecordChange/everyExercise``**, on
    /// `FR-1.6.4`'s scope: one exercise's number moved.
    ///
    /// It publishes unconditionally, on ``recentRecordsPreferencesDidChange()``'s rule — the number
    /// is not in force here, so this actor cannot tell a redundant write from a real one.
    ///
    /// - Parameter exerciseID: The exercise whose training max was written.
    public func trainingMaxDidChange(forExerciseID exerciseID: UUID) {
        publish(.exercise(exerciseID))
    }

    // MARK: - The computation

    /// Both halves, from the one walk ``walked(_:writingCache:)`` performed.
    ///
    /// Internal rather than private on ``workouts``' rule, so the reads can live in their own file.
    func recomputed(
        _ exerciseID: UUID, writingCache: Bool
    ) async throws -> ExerciseRecords {
        let walk = try await walked(exerciseID, writingCache: writingCache)
        return ExerciseRecords(
            exerciseID: exerciseID,
            repMaxes: walk.repMaxes,
            schemeRecords: walk.schemeRecords,
            estimate: try await estimate(over: walk))
    }

    /// One walk of the exercise's sets, `FR-1.6.1`'s all-time rep maxes, and the cache written if
    /// asked.
    ///
    /// **The estimate is not part of this**, so that the callers which discard one do not pay for
    /// `FR-1.7.1`'s window — see ``refreshRecords(forExerciseID:)`` and the cache-miss path of
    /// ``repMaxes(forExerciseID:)``. What it keeps hold of is everything ``estimate(over:)`` needs
    /// to compute one over the same sets, so asking for both still costs one walk.
    ///
    /// **A set the analytical type refuses is left out of the computation rather than failing it.**
    /// `SetEntry` stores what was logged and `SetRecord` validates, so a row carrying a value this
    /// build considers out of range — a newer version's, or a corrupt one's — would otherwise cost
    /// the user every record for that exercise rather than the one set. ``Walk/analysed`` is the
    /// one filtered sequence both halves index into, which is what keeps `PersonalRecord`'s offsets
    /// pointing at the set that actually holds the record.
    ///
    /// Internal rather than private on ``workouts``' rule, so the reads can live in their own file.
    func walked(_ exerciseID: UUID, writingCache: Bool) async throws -> Walk {
        // Claimed before the first `await`, and only by a call that intends to write: two reads that
        // never touch the row cannot supersede each other.
        let generation = writingCache ? claimWriteGeneration(exerciseID) : 0
        let stored = try await workouts.sets(forExerciseID: exerciseID, includingDeleted: false)
        let analysed = stored.compactMap { set in (try? set.setRecord()).map { (set, $0) } }

        let estimator = E1RMCalculator(formula)
        let calculator = PersonalRecordCalculator(e1rm: estimator)

        // All-time, per `FR-1.6.1`, and every cell of `FR-16.2.1`'s table from the same runs.
        let computed = SchemeRecordCalculator().records(
            in: SchemeRuns.runs(over: stored, offsetsInto: analysed))
        let dates = await sessionDates(
            forEntryIDs: Set(computed.map { analysed[$0.setOffset].0.entryID }))
        let schemeRecords = computed.map { record in
            DatedSchemeRecord(
                scheme: record.scheme,
                record: dated(
                    PersonalRecord(weight: record.weight, setOffset: record.setOffset),
                    over: analysed,
                    using: dates),
                previous: record.previousWeight)
        }
        // Derived from the table rather than computed beside it: two passes over one definition are
        // two places for `FR-1.6.1` and `FR-16.2.1` to start disagreeing about the same column.
        let repMaxes = schemeRecords.filter { $0.scheme.sets == 1 }.map {
            DatedRepMax(reps: $0.scheme.reps, record: $0.record)
        }

        // Refused rather than written where a newer recompute of this exercise has started since:
        // the value is still returned, because the caller asked for what *these* sets produce and
        // that is what it computed. See ``writeGenerations``.
        if writingCache, writeGenerations[exerciseID] == generation {
            try await cache.replacePersonalRecords(
                forExerciseID: exerciseID,
                with: schemeRecords.map {
                    PersonalRecordCacheValues(
                        repCount: $0.scheme.reps,
                        setCount: $0.scheme.sets,
                        weight: $0.record.weight,
                        sourceSetID: $0.record.sourceSetID,
                        achievedAt: $0.record.achievedAt,
                        previousWeight: $0.previous,
                        computationVersion: PersonalRecordCalculator.computationVersion)
                })
        }

        return Walk(
            exerciseID: exerciseID,
            stored: stored,
            analysed: analysed,
            estimator: estimator,
            calculator: calculator,
            repMaxes: repMaxes,
            schemeRecords: schemeRecords)
    }

    /// `FR-1.7.1`'s estimate, over the sets `walk` already read.
    ///
    /// The only read it adds is the window's own — the sets are the walk's, so asking for the
    /// estimate never walks the history a second time.
    ///
    /// **There is no way past it** (`D-16.1`). An estimate is what the lifter's sets say, and the
    /// one number they enter themselves is the training max, which lives in a table of its own.
    private func estimate(over walk: Walk) async throws -> EstimatedMax {
        // The filter preserves the repository's order, which is what keeps "ties resolve to the
        // earlier set" meaning the same thing over the subsequence.
        let window =
            walk.stored.isEmpty ? [:] : try await entryDatesInWindow(forExerciseID: walk.exerciseID)
        let inWindow = walk.analysed.filter { window[$0.0.entryID] != nil }

        guard let computed = walk.calculator.bestE1RM(in: inWindow.map(\.1)) else {
            return EstimatedMax(
                absence: absence(
                    hasSets: !walk.stored.isEmpty, inWindow: inWindow, under: walk.estimator),
                formula: formula,
                lookback: lookback)
        }
        let current = dated(computed, over: inWindow, using: window)
        return EstimatedMax(
            record: current,
            previous: previous(before: current, over: inWindow, using: window, by: walk.calculator),
            formula: formula,
            lookback: lookback)
    }

    /// What one walk of an exercise's sets produced, and what an estimate over the same sets needs.
    ///
    /// Carries the two calculators as well as the rows because both are built from the formula in
    /// force at the moment of the walk: rebuilding them in ``estimate(over:)`` would let a formula
    /// change landing between the two halves report a reason the rep maxes were not computed under.
    ///
    /// Internal rather than private on ``workouts``' rule: the reads in their own file take a walk's
    /// two halves off it. Nothing outside this module can see it.
    struct Walk {
        let exerciseID: UUID

        /// Every live set of this exercise, as stored.
        let stored: [SetEntry]

        /// The subset this build can analyse, paired with its analytical value.
        let analysed: [(SetEntry, SetRecord)]

        let estimator: E1RMCalculator
        let calculator: PersonalRecordCalculator

        /// `FR-1.6.1`'s all-time rep maxes, dated — the `sets == 1` column of ``schemeRecords``.
        let repMaxes: [DatedRepMax]

        /// `FR-16.2.1`'s whole table, dated.
        let schemeRecords: [DatedSchemeRecord]
    }

    /// The record with the set at its offset resolved to an identity and a date.
    ///
    /// **The offset is an index into `analysed`, not into what the repository returned**, and the
    /// two differ whenever a set was refused — see ``recomputed(_:writingCache:)``.
    func dated(
        _ record: PersonalRecord,
        over analysed: [(SetEntry, SetRecord)],
        using dates: [UUID: Date]
    ) -> DatedRecord {
        let set = analysed[record.setOffset].0
        return DatedRecord(
            weight: record.weight, sourceSetID: set.id, achievedAt: day(of: set, using: dates))
    }

    /// The session date behind each of `entryIDs`, for the ones that resolve.
    ///
    /// **At most sixty-one entries, however long the history is.** Only a set that actually holds a
    /// record is looked up, and `FR-16.2.1`'s table is `repRange × setRange` cells plus one
    /// estimate; a walk over the exercise's sessions to date them is what `NFR-1.6` puts out of
    /// reach. In practice it is far fewer — one run fills up to sixty cells and is one entry.
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

    /// Claims the next cache-writing generation for `exerciseID`. See ``writeGenerations``.
    private func claimWriteGeneration(_ exerciseID: UUID) -> Int {
        let next = (writeGenerations[exerciseID] ?? 0) + 1
        writeGenerations[exerciseID] = next
        return next
    }
}
