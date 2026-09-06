import Foundation
import RepositoryInterface

/// What one exercise looked like the last time it was trained, before the workout being logged
/// (`FR-1.2.10`).
struct PreviousPerformance: Equatable, Sendable {
    /// The training day it was performed on — the session's ``RepositoryInterface/WorkoutSession/date``,
    /// not when it was entered.
    let date: Date

    /// Every set logged against it that day, in ``RepositoryInterface/SetEntry/order``.
    ///
    /// **Unfiltered, and the strip filters.** The repository's rule for a set collection is that
    /// pre-filtering is a wrong answer rather than an optimisation; here the reason is smaller but
    /// the same shape — whether a warmup belongs in a comparison is the reader's question, and a
    /// value that had already dropped them could not be asked it.
    let sets: [SetEntry]

    /// The work proper, which is what "how it went last time" means.
    ///
    /// **Both of `G-1.8`'s columns, which is the partition every derived value in this app makes.**
    /// A warmup is the ramp rather than the effort being compared against, and a set that was not
    /// completed is `FR-1.2.5`'s failed one — drawn, it would put a load against zero reps under
    /// *Last time* as though it were work done. The personal record and the e1RM read the two
    /// columns together, so a strip that read one of them would compare today against a number no
    /// other screen recognises.
    var workingSets: [SetEntry] { sets.filter { !$0.isWarmup && $0.isCompleted } }

    /// The same sets as maximal *consecutive* runs of them (`FR-16.1.1`).
    ///
    /// **The filter is what makes this necessary rather than ``workingSets`` being enough.**
    /// Grouping the filtered list would join sets the dropped ones stood between: a set, a failed
    /// repeat of it and a third would read as `100 kg × 5 × 2`, a run of two that never happened.
    /// A dropped set ends the run it interrupted, so the strip counts what was consecutive on the
    /// day rather than what is consecutive after the filter.
    var workingRuns: [[SetEntry]] {
        var runs: [[SetEntry]] = []
        for set in sets {
            guard !set.isWarmup, set.isCompleted else {
                runs.append([])
                continue
            }
            if runs.isEmpty { runs.append([]) }
            runs[runs.count - 1].append(set)
        }
        return runs.filter { !$0.isEmpty }
    }
}

/// The previous performance behind every card in the workout, and whether it is known yet.
///
/// **One value rather than three properties on the store**, because the three are only ever read
/// together: which card has an answer, whether anything has looked, and whether the look failed.
/// It also puts the per-card decision — see ``state(forEntryID:)`` — somewhere a test can reach
/// without a store or a rendering.
struct PreviousPerformances: Equatable, Sendable {
    /// Keyed on the **entry**, not the exercise: the same exercise may be performed twice in one
    /// workout, and each of those cards is drawn from the same previous session.
    var byEntryID: [UUID: PreviousPerformance] = [:]

    /// Whether anything has looked yet. An exercise never trained before and one nothing has looked
    /// up are both a miss in the dictionary, and the strip says opposite things about them.
    var hasLoaded = false

    /// The last read that failed, as the error's description, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`).
    var readFailure: String?

    /// What one card's strip draws.
    ///
    /// **A failed read is ``PreviousPerformanceState/unknown`` rather than a state of its own**, and
    /// that is where this is reported rather than a decision to swallow it: one walk answers every
    /// card, so a failure is one fact — rendered once beneath the list, where the exercises' own
    /// failed write is rendered, instead of repeated inside every card in the workout.
    ///
    /// **A previous session with no work in it counts as no previous performance** — one of nothing
    /// but warmups, and one whose every working set failed, being the two ways that happens. The
    /// alternative is a strip naming a date with nothing under it, which is exactly the blank area
    /// `FR-1.2.10` is served by the insufficient-data state instead of.
    ///
    /// - Parameter entryID: The card's entry.
    /// - Returns: The state to render.
    func state(forEntryID entryID: UUID) -> PreviousPerformanceState {
        guard hasLoaded, readFailure == nil else { return .unknown }
        guard let performance = byEntryID[entryID], !performance.workingSets.isEmpty else {
            return .noneYet
        }
        return .performed(performance)
    }
}

/// Which of the "last time" strip's three states one card is in (`FR-1.2.10`, `FR-1.13.3`).
enum PreviousPerformanceState: Equatable {
    /// Nothing has looked yet, or the look failed. The strip draws nothing.
    case unknown

    /// The last time this exercise was trained.
    case performed(PreviousPerformance)

    /// It has never been trained before this workout — `FR-1.13.3`'s state, not an empty strip.
    ///
    /// Spelled `noneYet` rather than `none`, which on an enum used as an `Optional`'s wrapped type
    /// is the one case name that cannot be written unambiguously.
    case noneYet
}

/// `FR-1.2.10`'s read: what each exercise in the workout looked like the last time it was trained.
///
/// A file of its own on ``ActiveSessionCommands``' argument — the store proper is the workout's
/// lifecycle and what it holds, and this is one read with an ordering rule behind it.
extension ActiveSessionStore {
    /// Reads the previous performance behind every card in the workout (`FR-1.2.10`).
    ///
    /// **"Previous" is the repository's own order with one key inserted** — `WorkoutRepository`
    /// lists sessions newest first by `(date, id)`, and `date` is the first key of the
    /// `(session date, entry order, set order)` chronology every derived value in this app is
    /// computed against, so everything listed *after* the workout being logged is what came before
    /// it, backdating included. What that order cannot answer is two workouts on one training day;
    /// see ``chronological(_:)``.
    ///
    /// **A session's own last entry wins.** An exercise performed twice in one past workout is two
    /// entries, and the later of the two is what was done last.
    ///
    /// **Read where the exercise *list* changes, not where a set is written.** Nothing logged into
    /// the workout in progress can move this answer — that session is excluded from the walk by
    /// construction — so the per-set commands leave it alone and the cost below is paid on
    /// appearance and when an exercise is added.
    ///
    /// **The walk is unbounded and stops early**, which is ``resume()``'s trade in the other
    /// direction: one read lists the sessions, then one read per past session until every exercise
    /// has an answer. An exercise trained last week costs a session or two; one never trained
    /// before costs the whole history, and any window narrow enough to avoid that is a window a
    /// real previous session falls outside of.
    ///
    /// A read that fails costs every strip its contents and is reported once — see
    /// ``PreviousPerformances/state(forEntryID:)``.
    func loadPreviousPerformances() async {
        guard let current = session else {
            previous = PreviousPerformances()
            return
        }
        let cards = exercises
        guard !cards.isEmpty else {
            previous = PreviousPerformances(hasLoaded: true)
            return
        }
        do {
            previous = PreviousPerformances(
                byEntryID: try await performances(before: current, for: cards), hasLoaded: true)
        } catch {
            previous = PreviousPerformances(
                hasLoaded: true, readFailure: String(describing: error))
        }
    }

    /// One walk back through the history, answering every card it can.
    ///
    /// - Parameters:
    ///   - current: The workout being logged, which the walk starts below.
    ///   - cards: The exercises in it.
    /// - Returns: The previous performance for each card that has one, keyed on its entry.
    private func performances(
        before current: WorkoutSession,
        for cards: [SessionExercise]
    ) async throws -> [UUID: PreviousPerformance] {
        let history = try await repository.sessions(
            in: Date.distantPast...Date.distantFuture, includingDeleted: false)
        // Dropping *to* the current workout rather than filtering it out: a history that somehow
        // does not list it yields no previous session at all, which is the honest answer, where a
        // filter would silently compare against workouts logged after it.
        let past = Self.chronological(history).drop { $0.id != current.id }.dropFirst()
        var wanted = Set(cards.map(\.entry.exerciseID))
        var found: [UUID: PreviousPerformance] = [:]
        for session in past where !wanted.isEmpty {
            let entries = try await repository.entries(
                forSessionID: session.id, includingDeleted: false)
            for entry in entries.reversed() where wanted.contains(entry.exerciseID) {
                wanted.remove(entry.exerciseID)
                found[entry.exerciseID] = PreviousPerformance(
                    date: session.date,
                    sets: try await repository.sets(forEntryID: entry.id, includingDeleted: false)
                )
            }
        }
        return Dictionary(
            uniqueKeysWithValues: cards.compactMap { card in
                found[card.entry.exerciseID].map { (card.id, $0) }
            })
    }

    /// The history newest first, with two workouts on one training day in the order they happened.
    ///
    /// **The repository's order with a key inserted, not a second ordering.** `sessions(in:)` sorts
    /// by `(date, id)` descending and `date` is a training *day*, so two workouts on it carry the
    /// same value and their relative order falls to a `UUID` — which says nothing about which came
    /// first. The walk above reads that order as chronology, so without this an evening session
    /// drops the morning one it exists to compare against, on the spelling of an identifier and
    /// therefore about half the time.
    ///
    /// ``RepositoryInterface/WorkoutSession/startedAt`` is the only column that separates two
    /// workouts inside a day, so it goes second; `date` stays first, and the identifier stays last
    /// so the result is still a total order over rows a user could otherwise not tell apart.
    ///
    /// **A session never tracked live sorts earliest in its day.** It carries no start time, and
    /// nothing about it claims to have happened after a workout that does.
    ///
    /// - Parameter sessions: The history, in the order the repository returned it.
    /// - Returns: The same sessions, newest first.
    private static func chronological(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions
            .map { (key: ($0.date, $0.startedAt ?? .distantPast, $0.id.uuidString), session: $0) }
            .sorted { $0.key > $1.key }
            .map(\.session)
    }
}
