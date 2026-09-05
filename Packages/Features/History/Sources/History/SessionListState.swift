import DerivedValues
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
///
/// **Every session is here, the one in progress included.** `FR-1.5.1` is all of them, and neither
/// way of leaving one out survives its own edge case: `endedAt == nil` is not "in progress" — a
/// backdated workout never marked finished is past training with a null column — and asking the
/// training surface which session it holds would put `ActiveSessionStore`'s rule in a second place.
/// A row for a workout still being logged carries what has been logged so far.
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

    /// Which of an exercise's two names a summary lists (`FR-1.14.2`).
    ///
    /// A summary's names are strings ``SessionSummaryReader`` bakes in, so a row cannot resolve one
    /// for itself, and `FR-1.14.3`'s search over this screen matches exactly those strings. Set by
    /// the view, on ``RepositoryInterface/ExerciseNameLanguage``'s rule.
    var nameLanguage: ExerciseNameLanguage = .english

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

    /// What each exercise is called, for the summary line — empty until the catalogue is read.
    @ObservationIgnored private var names: [UUID: String] = [:]

    /// How a session becomes a row, over the catalogue this screen last read.
    private var reader: SessionSummaryReader {
        SessionSummaryReader(workouts: workouts, names: names)
    }

    /// A workout the screen has asked `FR-16.4.4`'s question about.
    struct PendingPrompt: Identifiable, Equatable {
        /// The workout being ended, and the prompt's identity — one question at a time.
        let sessionID: UUID

        /// How many of its sets nobody attempted.
        let count: Int

        /// See ``sessionID``.
        var id: UUID { sessionID }
    }

    /// Whether an extension is already running, so two scroll events do not build one page twice.
    @ObservationIgnored private var isExtending = false

    /// A workout waiting on `FR-16.4.4`'s answer, or `nil` where none is.
    ///
    /// **The count is read before the question is asked**, so the alert can name what it is about:
    /// "3 sets were not logged" is the whole of what makes the two answers meaningful.
    private(set) var pendingPrompt: PendingPrompt?

    /// Why the last attempt to end a workout failed, or `nil`. A **diagnostic**, not copy
    /// (`G-3.4`); the list is unchanged either way, so the retry is another tap at the command.
    private(set) var finishFailure: String?

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let exercises: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository
    @ObservationIgnored private let records: PersonalRecordRecomputer

    /// Builds the state over the three repositories it reads.
    ///
    /// - Parameters:
    ///   - workouts: Where the sessions, their entries and their sets come from.
    ///   - exercises: The catalogue, for the names in the summary line. A second repository rather
    ///     than a dependency on `ExerciseLibrary`, which `TR-1.3` forbids.
    ///   - settings: The single settings row, for the unit the tonnage is shown in. A third
    ///     protocol rather than a unit passed in, on `ActiveSessionStore`'s rule.
    ///   - records: The app's one recompute actor (`TR-1.6`), told when a workout ends here — its
    ///     sets start counting towards records and e1RM the moment it does (`FR-16.4.2`).
    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
        self.records = records
    }

    /// Asks `FR-16.4.4`'s question, or ends the workout where there is nothing to ask about.
    ///
    /// **A session with no pending sets is finished on the first tap.** The requirement is that a
    /// pending set is never converted silently, not that Finish is always two taps.
    ///
    /// - Parameter sessionID: The workout to end.
    func beginFinish(sessionID: UUID) async {
        finishFailure = nil
        guard let session = try? await workouts.session(id: sessionID, includingDeleted: false)
        else { return }
        do {
            let pending = try await finisher.pendingSets(in: session)
            guard !pending.isEmpty else {
                await finish(sessionID: sessionID, resolving: .keepAsFailed)
                return
            }
            pendingPrompt = PendingPrompt(sessionID: sessionID, count: pending.count)
        } catch {
            finishFailure = String(describing: error)
        }
    }

    /// Ends the workout, having answered for its pending sets (`FR-16.4.4`).
    ///
    /// The list is re-read afterwards rather than patched: the row it ends stops saying **In
    /// progress** and starts carrying the numbers it has, which is the whole visible consequence.
    ///
    /// - Parameters:
    ///   - sessionID: The workout to end.
    ///   - resolution: What to do with the sets nobody attempted.
    func finish(sessionID: UUID, resolving resolution: SessionFinish.Resolution) async {
        pendingPrompt = nil
        guard let session = try? await workouts.session(id: sessionID, includingDeleted: false)
        else { return }
        do {
            try await finisher.finish(session, at: .now, resolving: resolution)
            finishFailure = nil
        } catch {
            finishFailure = String(describing: error)
            return
        }
        await load()
    }

    /// Closes the question with the workout left open.
    func cancelFinish() {
        pendingPrompt = nil
    }

    /// How a workout is ended here — the operation both this screen and the training tab run.
    private var finisher: SessionFinish {
        SessionFinish(workouts: workouts, records: records)
    }

    /// Reads every session and summarises the first page.
    ///
    /// **Re-read on every appearance**, on `EquipmentProfilesState`'s rule: a workout finished above
    /// this screen has to be here on the way back down. A read already in flight is skipped, and an
    /// *extension* in flight is invalidated — see ``isCurrent(_:)`` — so nothing publishes over a
    /// newer answer.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        extendFailure = nil
        // An extension that started from the rows this read is about to replace will refuse to
        // publish. Clearing its flag here is what stops that refusal from also wedging the next
        // one: the flag's owner only clears it when it resumes, which may be after the user has
        // already scrolled to the bottom of the list this read produces.
        isExtending = false
        // Read again on every appearance rather than once: the preference is changed in another
        // tab, and a cached unit would relabel every row in this list wrongly.
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            sessions = Self.deduplicated(
                try await workouts.sessions(in: Self.everySession, includingDeleted: false))
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
    /// The refusal is an optimisation only — what makes a duplicate page impossible is
    /// ``isCurrent(_:)``, which every publish below goes through.
    func loadMore() async {
        guard case .loaded(let built) = phase, hasMore, !isExtending else { return }
        isExtending = true
        defer { isExtending = false }
        do {
            let extended = try await page(after: built)
            guard isCurrent(built) else { return }
            phase = .loaded(extended)
            extendFailure = nil
        } catch {
            guard isCurrent(built) else { return }
            extendFailure = String(describing: error)
        }
    }

    /// Whether the rows an extension started from are still the rows on screen.
    ///
    /// **This is what stops a slow extension from publishing over a newer read.** ``loadMore()``
    /// captures its rows before its first `await` and ``page(after:)`` reads ``sessions`` after it,
    /// so an extension that a ``load()`` overtook would otherwise splice rows from the old list onto
    /// offsets in the new one — dropping the session that read was run to pick up, and repeating the
    /// row at the seam. Both surfaces fire together on a return to this tab: the screen's `task` and
    /// the last row's `onAppear`.
    ///
    /// - Parameter built: The rows the extension started from.
    /// - Returns: Whether they are still what the screen is showing.
    private func isCurrent(_ built: [SessionSummary]) -> Bool {
        guard case .loaded(let current) = phase else { return false }
        return current == built
    }

    /// `built`, plus up to ``pageSize`` more summaries from where it left off.
    ///
    /// - Parameter built: The rows already summarised, newest first.
    /// - Returns: Those rows and the next page.
    private func page(after built: [SessionSummary]) async throws -> [SessionSummary] {
        var built = built
        for session in sessions.dropFirst(built.count).prefix(Self.pageSize) {
            built.append(try await reader.summary(for: session))
        }
        return built
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
        Self.names(in: try await exercises.exercises(includingDeleted: true), as: nameLanguage)
    }

    /// `catalogue` as a name lookup, first row winning where two share an identifier.
    ///
    /// Separate from the read above because the store cannot produce the case it defends against —
    /// a repository's `save` is keyed on the identifier — so the tiebreak is only assertable here.
    ///
    /// **The name resolved for `language`, not the English column** (`FR-1.14.2`) — a session's
    /// summary is read by a person, and `FR-1.14.3`'s search over this screen matches the strings
    /// this lookup put there.
    ///
    /// - Parameters:
    ///   - catalogue: The exercises, in the order the repository returned them.
    ///   - language: Which of an exercise's two names the screen is showing.
    /// - Returns: Each name, keyed by its identifier.
    static func names(in catalogue: [Exercise], as language: ExerciseNameLanguage) -> [UUID: String] {
        Dictionary(
            catalogue.map { ($0.id, $0.displayName(in: language)) },
            uniquingKeysWith: { first, _ in first })
    }

    /// `sessions` with at most one row per identifier, the first — the newest — kept.
    ///
    /// The same `G-2.5` argument as ``names(in:as:)``, one level up and with a sharper consequence: the
    /// list is a `ForEach` keyed on this identifier, which renders neither of a duplicated pair
    /// correctly, and the paging trigger compares against the last row's.
    ///
    /// - Parameter sessions: The sessions, newest first.
    /// - Returns: Them, less any repeat of an identifier already seen.
    static func deduplicated(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        var seen: Set<UUID> = []
        return sessions.filter { seen.insert($0.id).inserted }
    }

    /// Every session there has ever been.
    ///
    /// `WorkoutRepository` offers sessions by date range and nothing else, so "all of them" is
    /// spelled as the widest range — which both implementations answer newest-first and neither
    /// narrows. A repository method of its own would buy nothing this does not.
    ///
    /// Not `private`: ``SessionSearchState`` asks the same question and must ask it the same way.
    static let everySession = Date.distantPast...Date.distantFuture
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
