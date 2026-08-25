import Foundation
import PowerliftingCore
import RepositoryInterface

/// The session list's data and the reads behind it (`FR-1.5.1`, `NFR-1.5`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on `EquipmentProfilesState`'s rule:
/// nothing here outlives the screen, and a past session is a fact no other surface has to agree
/// about.
///
/// **Sessions are read whole; summaries are built a page at a time.** The session rows alone are one
/// query and are small — three years is a few hundred of them — but a summary needs every set under
/// its session, and building all of them up front is the eager per-row load `NFR-1.5` cannot
/// survive. So the rows are summarised in ``pageSize`` chunks as the list is scrolled, and a
/// summary, once built, is a value: **scrolling reads nothing**. Whether that reaches 60fps at
/// 15,000 sets is T-1.83's to measure; what this shape buys is that the answer is not already no.
///
/// **A failure to extend does not cost the screen what it has.** The first page failing is a screen
/// with nothing on it; the fourth page failing is a screen with three pages on it and a retry, which
/// is why the two are separate properties rather than one phase.
@Observable
final class SessionListState {
    /// What the screen has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The first read is in flight.
        case loading

        /// The sessions summarised so far, newest first.
        case loaded([SessionSummary])

        /// The read failed, carrying the error's description — a **diagnostic**, not copy (`G-3.4`).
        /// Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// How many sessions are summarised per page.
    ///
    /// Enough to fill any screen this app runs on at the largest Dynamic Type size, so the list is
    /// never scrollable-but-short and the extension is never the first thing a user waits for.
    static let pageSize = 20

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// The last extension that failed, as the error's description, or `nil`. A **diagnostic**, not
    /// copy (`G-3.4`).
    private(set) var extendFailure: String?

    /// The rows built so far, or none while the first read has not answered.
    ///
    /// A read-through of ``phase`` rather than a second stored property, for the reason
    /// `EquipmentProfilesState` gives: two would be two answers to what the screen is showing.
    var summaries: [SessionSummary] {
        guard case .loaded(let summaries) = phase else { return [] }
        return summaries
    }

    /// Whether there are sessions left to summarise.
    var hasMore: Bool { summaries.count < sessions.count }

    /// The unit a load is shown in (`G-3.1`, `G-3.2`).
    ///
    /// **Kilograms until the settings row has been read, and after a read that failed** — the
    /// schema's own default, and the reasoning is `ActiveSessionStore`'s: a tonnage with no unit on
    /// it is worse than one showing the majority default, and a failure here is not something this
    /// screen can say anything useful about.
    private(set) var displayUnit: MassUnit = .kilograms

    /// Every session the store holds, newest first — the order the repository already guarantees.
    @ObservationIgnored private var sessions: [WorkoutSession] = []

    /// What each exercise is called, for the summary line.
    @ObservationIgnored private var names: [UUID: String] = [:]

    /// Whether an extension is already running, so two scroll events do not build one page twice.
    @ObservationIgnored private var isExtending = false

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let exercises: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the state over the three repositories it reads.
    ///
    /// - Parameters:
    ///   - workouts: Where the sessions, their entries and their sets come from.
    ///   - exercises: The catalogue, for the names in the summary line. A second repository rather
    ///     than a dependency on `ExerciseLibrary`, which `TR-1.3` forbids.
    ///   - settings: The single settings row, for the unit the tonnage is shown in. A third
    ///     protocol rather than a unit passed in, on `ActiveSessionStore`'s rule.
    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
    }

    /// Reads every session and summarises the first page.
    ///
    /// **Re-read on every appearance**, on `EquipmentProfilesState`'s rule: a workout finished above
    /// this screen has to be here on the way back down. Only a read already in flight is skipped, so
    /// nothing publishes over a newer answer.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        extendFailure = nil
        // Read again on every appearance rather than once: the preference is changed in another
        // tab, and a cached unit would relabel every row in this list wrongly.
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            sessions = try await workouts.sessions(
                in: Self.everySession, includingDeleted: false)
            names = try await exerciseNames()
            // The first page is published *with* the phase rather than before it. A `.loaded([])`
            // set on the way past is an empty list on screen for as long as the page takes to
            // build, and `FR-1.13.2`'s "nothing logged yet" is the one thing this screen must not
            // say to a user who has logged something.
            phase = .loaded(try await page(after: []))
        } catch {
            sessions = []
            phase = .failed(String(describing: error))
        }
    }

    /// Summarises the next page, if there is one.
    ///
    /// Called as the last row appears. A failure leaves the rows already built on screen and is
    /// reported beside them.
    ///
    /// **Re-entrancy is refused rather than serialised.** Every step below is `await`, so a second
    /// caller arriving mid-page would read the same row count as the first and build one page twice.
    func loadMore() async {
        guard case .loaded(let built) = phase, hasMore, !isExtending else { return }
        isExtending = true
        defer { isExtending = false }
        do {
            phase = .loaded(try await page(after: built))
            extendFailure = nil
        } catch {
            extendFailure = String(describing: error)
        }
    }

    /// `built`, plus up to ``pageSize`` more summaries from where it left off.
    ///
    /// - Parameter built: The rows already summarised, newest first.
    /// - Returns: Those rows and the next page.
    private func page(after built: [SessionSummary]) async throws -> [SessionSummary] {
        var built = built
        for session in sessions.dropFirst(built.count).prefix(Self.pageSize) {
            built.append(try await summary(for: session))
        }
        return built
    }

    /// One session's row: its exercises, its working sets and what they weighed.
    ///
    /// - Parameter session: The session to summarise.
    /// - Returns: The row.
    private func summary(for session: WorkoutSession) async throws -> SessionSummary {
        let entries = try await workouts.entries(
            forSessionID: session.id, includingDeleted: false)

        var exerciseNames: [String] = []
        var seen: Set<UUID> = []
        var setCount = 0
        var tonnage = Weight.zero

        for entry in entries {
            if seen.insert(entry.exerciseID).inserted {
                exerciseNames.append(names[entry.exerciseID] ?? Self.unnamedExercise)
            }
            let sets = try await workouts.sets(forEntryID: entry.id, includingDeleted: false)
            setCount += sets.count(where: Tonnage.counts)
            tonnage += Tonnage.of(sets)
        }

        return SessionSummary(
            id: session.id,
            date: session.date,
            exerciseNames: exerciseNames,
            setCount: setCount,
            tonnage: tonnage,
            notes: session.notes
        )
    }

    /// The catalogue as a name lookup.
    ///
    /// **Archived and soft-deleted exercises are included.** A session logged against an exercise
    /// the user has since retired still happened, and a row that could not name it would be a hole
    /// in the history rather than a tidy list (`G-1.3`).
    ///
    /// **Duplicate identifiers keep the first row.** `G-2.5` forbids unique constraints, so two rows
    /// may carry one id; `Dictionary(uniqueKeysWithValues:)` traps on exactly that, and a store this
    /// app did not write must not be able to crash a read.
    ///
    /// - Returns: Each exercise's name, keyed by its identifier.
    private func exerciseNames() async throws -> [UUID: String] {
        let catalogue = try await exercises.exercises(includingDeleted: true)
        return Dictionary(catalogue.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// What a row calls an exercise whose catalogue row is gone.
    ///
    /// Not localized, and not shown: the read above includes deleted rows, so this is reachable only
    /// from a store missing a row a session references — a dangling reference the repository refuses
    /// to create. An empty name renders as nothing rather than as a translated apology for a case
    /// that cannot happen.
    private static let unnamedExercise = ""

    /// Every session there has ever been.
    ///
    /// `WorkoutRepository` offers sessions by date range and nothing else, so "all of them" is
    /// spelled as the widest range — which both implementations answer newest-first and neither
    /// narrows. A repository method of its own would buy nothing this does not.
    private static let everySession = Date.distantPast...Date.distantFuture
}

/// Which of `FR-1.13.1`'s states the session list is in.
///
/// A resolver rather than a chain of `if let` inside the view, on the rule every screen in this app
/// follows: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum SessionListScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and nothing has been logged — `FR-1.13.2`'s first launch, whose action is the
    /// only thing that makes a session.
    case empty

    /// There are sessions to show.
    case ready

    /// The list could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: SessionListState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(let summaries): summaries.isEmpty ? .empty : .ready
        case .failed: .failed
        }
    }
}
