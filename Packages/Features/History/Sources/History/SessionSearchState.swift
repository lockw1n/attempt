import Foundation
import PowerliftingCore
import RepositoryInterface

/// The History tab's search mode and the read behind it (`FR-1.5.4`).
///
/// **A second state beside ``SessionListState`` rather than a mode of it**, on the rule this module
/// already follows twice: a screen's state owns one question, and browsing and searching are two —
/// with two different read shapes, two different answers to "is there more", and four states each.
/// Folding them would put a paging cursor and a whole-history index on one object where every method
/// would have to ask which of the two it was serving.
///
/// **Search reads the whole history, once, and only once a query is typed.** `FR-1.5.4` asks for
/// *every* session containing a term, so nothing short of every session's entries and sets can
/// answer it — the walk is the requirement rather than an implementation choice. What `NFR-1.5` is
/// protected by is that it is a **different operation from scrolling**: the browse list still pages
/// and still reads nothing as it scrolls, this runs only when the search field is non-empty, and
/// once it has run, every keystroke after it filters values in memory with no repository call and no
/// debounce to get wrong (`ExerciseListState`'s argument, one level up). How long the walk takes at
/// `NFR-1.5`'s 15,000 sets is T-1.83's to measure.
///
/// **The index is dropped when the search field is emptied**, and rebuilt on the next search. It is
/// a picture of the store taken at a moment, and a workout logged between two searches has to appear
/// in the second — the same reason ``SessionListState/load()`` re-reads on every appearance. It is
/// also the largest thing this module holds — every session's summary and every set note in the
/// history — so leaving it behind for a screen that stopped reading it is the memory `NFR-1.5` is
/// about.
@Observable
final class SessionSearchState {
    /// What the search mode has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been searched — the field is empty, or was just emptied.
        case idle

        /// The walk over the history is in flight.
        case indexing

        /// It finished. Every session, summarised and with its notes, newest first.
        case indexed([IndexedSession])

        /// One of the reads refused, carrying the error's description — a **diagnostic**, not copy
        /// (`G-3.4`). Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// What the user typed into the search field (`FR-1.5.4`). Bound to `.searchable`.
    var query: String = ""

    /// The mode's read state.
    private(set) var phase: Phase = .idle

    /// Which of an exercise's two names the indexed summaries carry (`FR-1.14.2`, `FR-1.14.3`).
    ///
    /// What makes an exercise-name match here a match on the name the result actually shows. Set by
    /// the view before the walk, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    var nameLanguage: ExerciseNameLanguage = .english

    /// The unit a load is shown in (`G-3.1`, `G-3.2`).
    ///
    /// Read here rather than taken from the list's state, on `ExerciseHistoryState`'s rule: this
    /// object answers for itself, so a screen that reached search without the list having read
    /// anything still labels its numbers.
    private(set) var displayUnit: MassUnit = .kilograms

    /// Whether the user has typed something worth searching for.
    ///
    /// **This is the mode switch**, and it is the search *field* rather than the results: a query
    /// that matched nothing is still a search, and the screen must say so rather than fall back to
    /// the unsearched list.
    var isSearching: Bool { !SessionSearch.trimmed(query).isEmpty }

    /// The sessions the query was found in, newest first.
    ///
    /// Derived on read rather than stored, for ``SessionListState/summaries``' reason: two
    /// properties would be two answers to what the screen is showing, and this one has to change on
    /// a keystroke that no read follows.
    var results: [SessionMatch] {
        guard case .indexed(let sessions) = phase else { return [] }
        return SessionSearch.results(in: sessions, matching: SessionSearch.trimmed(query))
    }

    /// Which walk the screen is waiting for. Bumped by ``load()`` and by ``dropIndex()``.
    ///
    /// **This is what stops a walk the user has moved on from publishing over a newer one.** The
    /// screen's trigger cancels the old walk and starts the next without waiting for the first to
    /// unwind, and a repository read that does not honour cancellation is still in flight when it
    /// does — so whatever that walk publishes on its way out lands on a screen that has since asked
    /// a different question. ``SessionListState/isCurrent(_:)`` is the same rule over the list's
    /// rows; a walk has no rows to compare, so it carries a token instead.
    @ObservationIgnored private var walk = 0

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let exercises: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the state over the three repositories it reads.
    ///
    /// - Parameters:
    ///   - workouts: The sessions, their entries and their sets — all three levels, because a
    ///     per-set note is only reachable through the third.
    ///   - exercises: The catalogue, for the names a query is matched against and the summary line
    ///     shows. A second repository rather than a dependency on `ExerciseLibrary` (`TR-1.3`).
    ///   - settings: The settings row, for the unit a result's tonnage is shown in.
    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
    }

    /// Indexes the history if a search is running, and does nothing otherwise.
    ///
    /// **The screen's only trigger**, driven by ``isSearching`` so that it fires on the keystroke
    /// that starts a search and on a return to a screen left mid-search — and not on every keystroke
    /// after either, the flag not having changed. Emptying the field lands on the other branch,
    /// which is the only thing that drops the index.
    func loadIfSearching() async {
        guard isSearching else {
            dropIndex()
            return
        }
        await load()
    }

    /// Drops the index and abandons any walk still in flight.
    ///
    /// **Both ways out of search mode come through here**, ``clear()``'s button and the search
    /// field's own, because both empty the field and it is the field ``loadIfSearching()`` keys on.
    /// Bumping the token is the other half of it: a walk suspended in a read that never noticed the
    /// cancellation would otherwise publish, on the next redraw, an index nothing is waiting for.
    func dropIndex() {
        walk &+= 1
        phase = .idle
    }

    /// Reads and indexes every session.
    ///
    /// Also the retry on the failed state, which is why it is callable directly.
    ///
    /// **A cancelled walk publishes nothing.** The walk is the longest read in this module and the
    /// cheapest way out of it is the user emptying the field; a half-built index published as
    /// `.indexed` would answer the next query with part of the history and look exactly like a
    /// complete answer.
    ///
    /// **A second walk supersedes the first rather than being refused**, which is where this parts
    /// company with ``SessionListState/load()``. A guard that returned early while one was in flight
    /// would do nothing at all on the keystroke that restarts a search — the walk it deferred to
    /// having already been cancelled — and leave the screen on a spinner no later keystroke could
    /// clear, the trigger's identity not having changed. The token is what makes starting a second
    /// safe.
    func load() async {
        walk &+= 1
        let token = walk
        phase = .indexing
        // Re-read on every search rather than caching: the preference is changed in another tab.
        if let unit = try? await settings.settings().displayUnit, isCurrent(token) {
            displayUnit = unit
        }
        do {
            // The same three rules the list reads under, spelled once: the widest range, live rows
            // only (`G-1.3`), and at most one row per identifier (`G-2.5`).
            let sessions = SessionListState.deduplicated(
                try await workouts.sessions(in: SessionListState.everySession, includingDeleted: false))
            let names = SessionListState.names(
                in: try await exercises.exercises(includingDeleted: true), as: nameLanguage)
            let reader = SessionSummaryReader(workouts: workouts, names: names)

            var indexed: [IndexedSession] = []
            indexed.reserveCapacity(sessions.count)
            for session in sessions {
                guard isCurrent(token) else { return }
                indexed.append(try await reader.indexed(for: session))
            }
            guard isCurrent(token) else { return }
            phase = .indexed(indexed)
        } catch {
            guard isCurrent(token) else { return }
            phase = .failed(String(describing: error))
        }
    }

    /// Whether the walk `token` belongs to is still the one the screen is waiting for.
    ///
    /// **Every publish in ``load()`` goes through this**, the refusal included: a walk that failed
    /// after the user moved on would otherwise put `FR-1.13.1`'s error state over results a later
    /// walk had already delivered. The two clauses are the two ways a walk goes stale — another
    /// started, or the field emptied — and cancellation on its own, with no successor, is what makes
    /// the in-loop check an early exit rather than the whole mechanism.
    ///
    /// - Parameter token: The walk's token, taken before its first `await`.
    /// - Returns: Whether it may still publish.
    private func isCurrent(_ token: Int) -> Bool {
        token == walk && !Task.isCancelled
    }

    /// Empties the search field — the action on the "nothing matched" state.
    ///
    /// The index goes with it, by way of ``dropIndex()`` on the redraw that follows: emptying the
    /// field is what the screen's trigger keys on, and this button is only one of the two things
    /// that does it.
    func clear() {
        query = ""
    }
}

/// Which of `FR-1.13.1`'s states the search results are in.
///
/// A resolver rather than a chain of `if let` inside the view, on the rule every screen in this app
/// follows: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum SessionSearchScreenState: Equatable {
    /// The walk has not answered yet.
    case loading

    /// It answered, and no session contains the query.
    ///
    /// **A history with nothing in it lands here too**, and that is deliberate rather than a missing
    /// fifth state: "no session matches that" is true of an empty store, and the action — clearing
    /// the field — returns the user to the list's own empty state, which says the other thing.
    case empty

    /// There are results to show.
    case ready

    /// The history could not be read; a retry may work.
    case failed

    /// Which state a phase and its results are.
    ///
    /// - Parameters:
    ///   - phase: The mode's read state.
    ///   - hasResults: Whether the current query matched anything.
    /// - Returns: The state to draw.
    static func current(_ phase: SessionSearchState.Phase, hasResults: Bool) -> Self {
        switch phase {
        case .idle, .indexing: .loading
        case .indexed: hasResults ? .ready : .empty
        case .failed: .failed
        }
    }
}
