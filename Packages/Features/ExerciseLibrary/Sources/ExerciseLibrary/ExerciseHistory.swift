import DerivedValues
import Foundation
import PowerliftingCore
import RepositoryInterface

/// One training day's work on one exercise, as `FR-1.5.2` groups it.
///
/// **Keyed on the session, and one group even where the exercise was performed twice that day.**
/// Two entries for one exercise in one workout are two positions in the session, not two days — the
/// requirement groups by session, so the sets run together in `(entry order, set order)`.
struct ExerciseSessionHistory: Identifiable, Equatable, Sendable {
    /// The session this work belongs to.
    let id: UUID

    /// The training day it was performed on — the session's `date`, not when it was entered.
    let date: Date

    /// Its sets, in `(entry order, set order)`.
    ///
    /// **Unfiltered, and the rows draw the distinctions.** Warmups and failed sets are what happened
    /// on the day, and `PreviousPerformance`'s rule applies here for the same reason: whether the
    /// ramp belongs in what is being read is the reader's question, and a value that had already
    /// dropped them could not be asked it.
    let sets: [SetEntry]

    /// `FR-16.1.1`'s runs, as the section draws them — one line per run of identical sets.
    ///
    /// **At ``DerivedValues/SetGrouping/Grain/displayed``, which is `FR-16.1.2` rather than a
    /// default taken.** A history row draws the load, the reps, the rating, the warmup word and the
    /// failed mark, so a run that merged across any of them would be a line asserting one member's
    /// fact about all of them — a warmup and a working set at the same load being the plainest.
    ///
    /// **A run stops at an entry boundary, which this reader is the reason for.** ``sets`` runs two
    /// entries together where the exercise was performed twice in the day, and those sets were not
    /// adjacent in the session; the grouping compares the entry, so the boundary is kept.
    var groups: [SetGroup] { SetGrouping.groups(sets, at: .displayed) }
}

/// The exercise-detail screen's history section, and the walk behind it (`FR-1.5.2`).
///
/// **Its own state rather than three more properties on ``ExerciseDetailState``**, on that type's
/// own rule taken one step further: a failed workout read must not cost the screen the exercise, and
/// the cheapest way to guarantee that is for the two reads to be two states with two phases. It also
/// keeps `FR-1.1.6`'s notes editor — a draft, two failure slots and a serialized write chain — out
/// of a type whose whole job is a read.
///
/// **Two reads open the walk, and then one per session scanned.** `WorkoutRepository` can list every
/// set logged against an exercise, and it can list sessions, and it has nothing that joins the two:
/// a set names its *entry*, and only an entry names its session. So the sets come back in one read
/// (which is also the total, and therefore the walk's own stopping condition), the sessions in a
/// second, and the walk reads entries per session until it has grouped every set it was given.
///
/// **The second read is conditional on the first, and that is not a micro-optimisation.** Reading
/// every session in the store is what this section costs a screen that may have nothing to show, and
/// the exercise-detail screen is reached from a catalogue of them.
///
/// **A page is a number of sessions, not of sets.** A session's worth of work is what a reader scans
/// — a group of one set and a group of nine are one glance each — and `FR-1.5.2`'s unit is the
/// session. See ``pageSize``.
///
/// **The walk is unbounded and stops early**, which is `ActiveSessionStore.loadPreviousPerformances()`'s
/// trade and the same one: an exercise trained last week costs a session or two, and one last trained
/// two hundred sessions ago costs two hundred reads to show its three groups. What makes that
/// tolerable rather than merely accepted is the stopping condition — the walk knows how many sets it
/// is looking for, so it never scans past the oldest one, and an exercise with no history at all
/// costs nothing beyond the first read.
@Observable
final class ExerciseHistoryState {
    /// What the section has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The first read is in flight.
        case loading

        /// The sessions grouped so far, newest first.
        case loaded([ExerciseSessionHistory])

        /// The read failed, carrying the error's description — a **diagnostic**, not copy (`G-3.4`).
        /// Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// How many sessions are grouped per page.
    ///
    /// Small, unlike the session list's twenty, because this is a *section* rather than a screen:
    /// each group is a date and up to a dozen rows, and a section that opened with twenty of them
    /// would bury `FR-1.1.5`'s archive control and the two derived sections under it. Five is enough
    /// to answer "how has this lift been going" without the screen becoming the history screen.
    static let pageSize = 5

    /// The section's read state.
    private(set) var phase: Phase = .idle

    /// The last extension that failed, as the error's description, or `nil`. A **diagnostic**, not
    /// copy (`G-3.4`).
    private(set) var extendFailure: String?

    /// Whether there is history the walk has not reached yet.
    ///
    /// **Exact, not a guess**, and that is what the first read buys: it returns every set ever logged
    /// against this exercise, so the walk knows the total and can say whether what it has grouped is
    /// all of it. A stored property rather than a read-through of ``cursor``, which is not observed.
    private(set) var hasMore = false

    /// The unit a load is shown in (`G-3.1`, `G-3.2`).
    ///
    /// **Kilograms until the settings row has been read** — the schema's own default, on
    /// `SessionListState`'s reasoning: a load with no unit on it is worse than one showing the
    /// majority default, and a failure here is not something this section can say anything useful
    /// about.
    ///
    /// **A read that fails leaves the last unit read in place** rather than reverting to the
    /// default: on a re-read the preference was already answered once, and relabelling every row on
    /// screen because the second answer did not arrive would be a worse lie than the stale one.
    private(set) var displayUnit: MassUnit = .kilograms

    /// The groups built so far, or none while the first read has not answered.
    ///
    /// A read-through of ``phase`` rather than a second stored property: two would be two answers to
    /// what the section is showing.
    var groups: [ExerciseSessionHistory] {
        guard case .loaded(let groups) = phase else { return [] }
        return groups
    }

    /// Which exercise this history is of.
    let exerciseID: UUID

    /// Where the walk has got to. See ``Cursor``.
    ///
    /// **Not observed, and it holds no groups.** Those live in ``phase`` and nowhere else; this is
    /// the bookkeeping that lets the next page start where the last one stopped.
    @ObservationIgnored private var cursor = Cursor()

    /// Whether an extension is already running, so two taps do not build one page twice.
    @ObservationIgnored private var isExtending = false

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the state over the exercise it is about and the two repositories it reads.
    ///
    /// - Parameters:
    ///   - exerciseID: Which exercise's history to show.
    ///   - workouts: Where the sets, the sessions and the entries joining them come from.
    ///   - settings: The single settings row, for the unit a load is shown in. A second protocol
    ///     rather than a unit passed in, on `SessionListState`'s rule.
    init(
        exerciseID: UUID,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository
    ) {
        self.exerciseID = exerciseID
        self.workouts = workouts
        self.settings = settings
    }

    /// Reads this exercise's sets and the history they fall in, and groups the first page.
    ///
    /// **Re-read on every appearance**, on `SessionListState`'s rule: a set logged in another tab, or
    /// edited on a past session's screen, has to be here on the way back.
    ///
    /// **A read already in flight is skipped, and that is an optimisation only** — two overlapping
    /// reads each build a complete page from their own walk, so the later publish is simply the
    /// answer. What is *not* optional is invalidating an **extension** in flight: that one resumes
    /// holding rows from the history it started in and would splice them onto this read's. See
    /// ``isCurrent(_:)``.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        extendFailure = nil
        // An extension that started from the groups this read is about to replace will refuse to
        // publish. Clearing the flag here is what stops that refusal from also wedging the next one,
        // for the reason `SessionListState.load()` gives.
        isExtending = false
        // Read again on every appearance rather than once: the preference is changed in another tab,
        // and a cached unit would relabel every row here wrongly.
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            // The sets first, and deliberately: it is the cheap question — an exercise nothing has
            // been logged against is answered by this read alone, and the empty cursor below is
            // what keeps that promise. Reading every session in the store to discover that none of
            // them is wanted is the eager read this walk is paged to avoid.
            let logged = Self.deduplicated(
                try await workouts.sets(forExerciseID: exerciseID, includingDeleted: false))
            var start = Cursor()
            if !logged.isEmpty {
                start = Cursor(
                    sessions: Self.chronological(
                        Self.deduplicated(
                            try await workouts.sessions(
                                in: Self.everySession, includingDeleted: false))),
                    byEntry: Dictionary(grouping: logged, by: \.entryID),
                    remaining: logged.count
                )
            }
            // Published with the phase rather than before it, on `SessionListState`'s rule: a
            // `.loaded([])` set on the way past is `FR-1.13.3`'s "nothing logged yet" on screen for
            // as long as the walk takes, which is the one thing this section must not say to a user
            // who has logged something.
            let built = try await walk(&start)
            cursor = start
            hasMore = start.hasMore
            phase = .loaded(built)
        } catch {
            cursor = Cursor()
            hasMore = false
            phase = .failed(String(describing: error))
        }
    }

    /// Groups the next page, if there is one.
    ///
    /// A failure leaves the groups already built on screen and is reported beside them: the fourth
    /// page failing is a section with three pages in it and a retry, not an empty section.
    ///
    /// **Re-entrancy is refused rather than serialised**, on `SessionListState.loadMore()`'s
    /// argument — and, as there, the refusal is an optimisation only. What makes a duplicated page
    /// impossible is ``isCurrent(_:)``.
    func loadMore() async {
        guard case .loaded(let built) = phase, hasMore, !isExtending else { return }
        isExtending = true
        defer { isExtending = false }
        // A copy: the walk advances it across `await`s, and a `load()` that overtakes this one must
        // not find its own cursor rewound to where this extension started.
        var advanced = cursor
        do {
            let extended = built + (try await walk(&advanced))
            guard isCurrent(built) else { return }
            cursor = advanced
            hasMore = advanced.hasMore
            phase = .loaded(extended)
            extendFailure = nil
        } catch {
            guard isCurrent(built) else { return }
            extendFailure = String(describing: error)
        }
    }

    /// Whether the groups an extension started from are still the groups on screen.
    ///
    /// **This is what stops a slow extension from publishing over a newer read**, and the failure it
    /// prevents is `SessionListState.isCurrent(_:)`'s: an extension a ``load()`` overtook would
    /// otherwise append groups walked from the old history onto the new one's, repeating a session
    /// and skipping the one the newer read was run to pick up.
    ///
    /// - Parameter built: The groups the extension started from.
    /// - Returns: Whether they are still what the section is showing.
    private func isCurrent(_ built: [ExerciseSessionHistory]) -> Bool {
        guard case .loaded(let current) = phase else { return false }
        return current == built
    }

    /// Scans forward from `cursor` until ``pageSize`` sessions have been grouped, or the history is
    /// accounted for.
    ///
    /// **A session with no sets of this exercise costs a read and produces no group**, and does not
    /// count against the page: the page is what the reader sees, not what the walk did.
    ///
    /// - Parameter cursor: Where to resume; advanced past everything this call consumed, whether or
    ///   not it produced a group.
    /// - Returns: The page's groups, newest first.
    private func walk(_ cursor: inout Cursor) async throws -> [ExerciseSessionHistory] {
        var page: [ExerciseSessionHistory] = []
        while page.count < Self.pageSize, cursor.hasMore {
            let session = cursor.sessions[cursor.scanned]
            cursor.scanned += 1
            // `includingDeleted: false` is the contract's argument rather than a filter that can
            // fire: a deleted entry's sets are deleted with it, so its id was never in `byEntry` to
            // be matched. It stays because the alternative reads as a deliberate exception.
            let entries = try await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
            // The entries in `order`, which is what the repository returns them in, and each one's
            // sets in the order the first read gave them — together, `(entry order, set order)`.
            var sets: [SetEntry] = []
            for entry in entries {
                if let logged = cursor.byEntry.removeValue(forKey: entry.id) {
                    sets.append(contentsOf: logged)
                }
            }
            guard !sets.isEmpty else { continue }
            cursor.remaining -= sets.count
            page.append(
                ExerciseSessionHistory(id: session.id, date: session.date, sets: sets))
        }
        return page
    }

    /// The history newest first, with two workouts on one training day in the order they happened.
    ///
    /// **The repository's order with one key inserted, not a second ordering**, and the argument is
    /// `ActiveSessionStore.chronological(_:)`'s: `sessions(in:)` sorts by `(date, id)` descending,
    /// `date` is a training *day*, and two workouts on it therefore fall to a `UUID` — which says
    /// nothing about which came first. Here the consequence is two groups carrying the same date in
    /// an order the reader cannot account for. `startedAt` is the only column that separates them, so
    /// it goes second; a session never tracked live sorts earliest in its day, since nothing about it
    /// claims to have happened after one that does.
    ///
    /// **The third consumer of `(session date, entry order, set order)`**, after T-1.27 and the
    /// personal-record calculator. A fourth is the signal to pull this into a shared helper rather
    /// than hand-roll it again.
    ///
    /// - Parameter sessions: The history, in the order the repository returned it.
    /// - Returns: The same sessions, newest first.
    static func chronological(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions
            .map { (key: ($0.date, $0.startedAt ?? .distantPast, $0.id.uuidString), session: $0) }
            .sorted { $0.key > $1.key }
            .map(\.session)
    }

    /// `rows` with at most one per identifier, the first kept.
    ///
    /// `G-2.5` forbids unique constraints, so two rows may carry one id — and both collections this
    /// is applied to are walked as though an id picked out one row: the sets become a `ForEach` and a
    /// dictionary key, and a repeated session would be scanned twice and grouped twice.
    ///
    /// **Assertable only here, not through the walk**, which is `SessionListState.names(in:as:)`'s
    /// position: a repository's `save` is keyed on the identifier, so no store this app writes can
    /// produce the case this defends against. What can is a store it did not write — a restored
    /// backup, or a sync that landed two rows — and a read must not be able to crash on one.
    ///
    /// - Parameter rows: The rows, in the order the repository returned them.
    /// - Returns: Them, less any repeat of an identifier already seen.
    static func deduplicated<Row: StoredRecord>(_ rows: [Row]) -> [Row] {
        var seen: Set<UUID> = []
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// Every session there has ever been — `SessionListState`'s spelling, for its reason.
    private static let everySession = Date.distantPast...Date.distantFuture

    /// Where the walk has got to, and what it is still looking for.
    ///
    /// A value rather than four properties on the state, so an extension can advance a *copy* across
    /// its awaits and commit it only if the groups it started from are still on screen.
    struct Cursor {
        /// The whole history, newest first.
        var sessions: [WorkoutSession] = []

        /// The sets not yet grouped, keyed on the entry that names them, each list in `set order`.
        var byEntry: [UUID: [SetEntry]] = [:]

        /// How many of those are left — ``byEntry``'s total, kept as a count so the stopping
        /// condition is not a dictionary walk per session.
        var remaining = 0

        /// How many sessions have been read.
        var scanned = 0

        /// Whether there is anything left to find, and anywhere left to look.
        ///
        /// **Both halves, and the second is load-bearing rather than defensive.** A store whose sets
        /// outlive the session that owned them — which the cascade forbids and a restored backup
        /// could still produce — leaves `remaining` above zero with no session left to assign it to.
        /// A walk that checked only the count would not merely offer a "show earlier" that never
        /// finishes: its next step is ``sessions`` at ``scanned``, and there is no such element.
        var hasMore: Bool { remaining > 0 && scanned < sessions.count }
    }
}

/// Which of `FR-1.13.1`'s states the history section is in.
///
/// A resolver rather than a chain of `if let` inside the view, on the rule every screen in this app
/// follows: which state was chosen is a unit test's question, and what it looks like is a snapshot's.
///
/// **No offline state and no empty one, both deliberately.** A logged set is a local row (`G-2.1`,
/// `G-2.3`), so there is no fetch to be offline for — the argument the rest of this screen makes. And
/// the state for "this exercise has never been trained" is `FR-1.13.3`'s insufficient-data rather
/// than `FR-1.13.2`'s empty: nothing is missing from a list here, the derived display simply has
/// nothing to derive from yet, which is the distinction that component exists to draw.
enum ExerciseHistoryScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and nothing has ever been logged against this exercise (`FR-1.13.3`).
    case noneYet

    /// There is history to show.
    case ready

    /// It could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The section's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: ExerciseHistoryState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(let groups): groups.isEmpty ? .noneYet : .ready
        case .failed: .failed
        }
    }
}
