import Foundation
import PowerliftingCore
import RepositoryInterface

/// The week view's data and the reads behind it (`FR-17.11`, `NFR-17.5`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, on ``SessionListState``'s rule: which
/// week is on screen outlives nothing and no other surface has to agree about it.
///
/// **One read of the session rows, then summaries a page at a time** — the list's own shape, and for
/// its reasons. The rows alone are one query and are small; a summary needs every set under its
/// session, so building all of them up front is the eager load `NFR-1.5` cannot survive.
///
/// **The read is the whole history rather than one week's range, and that is deliberate.** Two of
/// this screen's requirements are only cheap this way: `FR-17.11.1` draws no week with nothing
/// logged, so paging backwards has to *skip* empty weeks rather than fetch them — a year off would
/// otherwise be fifty-two refused reads — and `FR-17.11.4` opens a week twelve months back, which
/// from an indexed history is a filter rather than a walk. ``CalendarState`` reads the same rows the
/// same way one screen along. What `NFR-17.5` actually forbids is a *set-history* walk, and there is
/// none here: every read below is `sessions(in:)`, the catalogue, and ``SessionSummaryReader``'s own
/// two.
@Observable
final class WeekHistoryState {
    /// What the screen has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The read is in flight.
        case loading

        /// It answered, carrying the rows summarised so far — newest first.
        case loaded([SessionSummary])

        /// The read failed, carrying the error's description — a **diagnostic**, not copy (`G-3.4`).
        /// Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// Which of an exercise's two names a row lists (`FR-1.14.2`).
    var nameLanguage: ExerciseNameLanguage = .english

    /// Why the last attempt to extend the list failed, or `nil`.
    ///
    /// Separate from ``phase`` for ``SessionListState/extendFailure``'s reason: a fourth page
    /// failing is a screen with three pages on it and a retry, not a screen with nothing on it.
    private(set) var extendFailure: String?

    /// The unit a load is shown in (`G-3.1`, `G-3.2`) — kilograms until the settings row is read.
    private(set) var displayUnit: MassUnit = .kilograms

    /// The calendar the weeks are cut in, and the one their headings must be rendered against.
    private(set) var calendar: Calendar

    /// The rows summarised so far, newest first.
    var summaries: [SessionSummary] {
        guard case .loaded(let summaries) = phase else { return [] }
        return summaries
    }

    /// Those rows, cut into calendar weeks (`FR-17.11.1`).
    var weeks: [HistoryWeekSection] {
        HistoryWeeks.sections(summaries, calendar: calendar)
    }

    /// Whether there are rows this screen has not summarised yet.
    var hasMore: Bool { summaries.count < inScope.count }

    /// The day the screen was opened on from the calendar, as a day start, or `nil` (`FR-17.11.2`).
    ///
    /// Computed rather than stored, so ``adopt(_:)`` moving the calendar moves the mark with it —
    /// a day start in one time zone is mid-day in another, and a mark left on the old one would
    /// name a row that is no longer that day's.
    var markedDay: Date? {
        anchor.map(calendar.startOfDay(for:))
    }

    /// The instant the screen was opened at, or `nil` where it is the tab's own week mode.
    ///
    /// **A raw instant rather than a week**, for ``markedDay``'s reason: which week it falls in is a
    /// question for whatever calendar is in use at the time.
    @ObservationIgnored private let anchor: Date?

    /// Every session the store holds, newest first — the order the repository already guarantees.
    @ObservationIgnored private var sessions: [WorkoutSession] = []

    /// Those of them the screen may draw: the anchor's week and everything before it.
    ///
    /// **The whole history where there is no anchor.** A screen opened at a week shows that week and
    /// pages backwards from it; the tab's mode starts at the newest row there is.
    private var inScope: [WorkoutSession] {
        guard let anchor else { return sessions }
        let cutoff = HistoryWeeks.weekStart(of: anchor, in: calendar)
        return sessions.filter { HistoryWeeks.weekStart(of: $0.date, in: calendar) <= cutoff }
    }

    /// Whether an extension is already running.
    @ObservationIgnored private var isExtending = false

    /// What each exercise is called — empty until the catalogue is read.
    @ObservationIgnored private var names: [UUID: String] = [:]

    /// How a session becomes a row, over the catalogue this screen last read.
    private var reader: SessionSummaryReader {
        SessionSummaryReader(workouts: workouts, names: names)
    }

    @ObservationIgnored private let workouts: any WorkoutRepository
    @ObservationIgnored private let exercises: any ExerciseRepository
    @ObservationIgnored private let settings: any SettingsRepository

    /// Builds the state over the three repositories it reads.
    ///
    /// - Parameters:
    ///   - workouts: Where the sessions, their entries and their sets come from.
    ///   - exercises: The catalogue, for the names in a row.
    ///   - settings: The settings row, for the unit a tonnage is shown in.
    ///   - anchor: The instant the screen was opened at — the week it falls in is the newest one
    ///     drawn, and its day is marked (`FR-17.11.2`). `nil` for the tab's own week mode, which
    ///     starts at the newest row there is.
    ///   - calendar: Which calendar decides where a week and a day begin. The view passes
    ///     `@Environment(\.calendar)` through ``adopt(_:)`` once it has one; this is what the state
    ///     uses until then, and what a test pins.
    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository,
        containing anchor: Date? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
        self.anchor = anchor
        self.calendar = calendar
    }

    /// Adopts `calendar`, if it is not the one already in use.
    ///
    /// The view calls this before ``load()``, from `@Environment(\.calendar)`. It is not the
    /// initialiser's job: a `View`'s environment is unreadable from its own `init`, which is where
    /// the state is built.
    ///
    /// Nothing is re-derived here, unlike ``CalendarState/adopt(_:)``: every week-shaped value on
    /// this screen is computed from the rows on read, so moving the calendar moves them all.
    ///
    /// - Parameter calendar: The calendar the screen is being drawn in.
    func adopt(_ calendar: Calendar) {
        guard calendar != self.calendar else { return }
        self.calendar = calendar
    }

    /// Reads every session and summarises the first page.
    ///
    /// **Re-read on every appearance**, on ``SessionListState/load()``'s rule: a workout finished
    /// above this screen has to be here on the way back down. A read already in flight is skipped,
    /// and an extension in flight is invalidated — see ``isCurrent(_:)``.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        extendFailure = nil
        // For ``SessionListState/load()``'s reason: the flag's owner only clears it when it resumes,
        // which may be after the user has already scrolled to the bottom of this read's list.
        isExtending = false
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            sessions = SessionListState.deduplicated(
                try await workouts.sessions(
                    in: SessionListState.everySession, includingDeleted: false))
            names = SessionListState.names(
                in: try await exercises.exercises(includingDeleted: true), as: nameLanguage)
            // The first page is published *with* the phase rather than before it, for the list's
            // reason: `.loaded([])` on the way past is `FR-1.13.2`'s empty state shown to a user who
            // has logged something.
            phase = .loaded(try await page(after: []))
        } catch {
            sessions = []
            phase = .failed(String(describing: error))
        }
    }

    /// Summarises the next page, if there is one (`FR-17.11.4` — a year back is paging).
    ///
    /// A failure leaves the rows already built on screen and is reported beside them.
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
    /// ``SessionListState/isCurrent(_:)``'s guard, for its reason: an extension a ``load()``
    /// overtook would otherwise splice rows from the old list onto offsets in the new one.
    private func isCurrent(_ built: [SessionSummary]) -> Bool {
        guard case .loaded(let current) = phase else { return false }
        return current == built
    }

    /// `built`, plus up to a page more summaries from where it left off.
    ///
    /// **A page of rows rather than of weeks**, which is what makes a week with nothing logged cost
    /// nothing: a section exists because rows opened it, so the empty weeks between two training
    /// blocks are never reached at all. A week can therefore arrive half-built and be completed by
    /// the next page, exactly as a month does in the list.
    ///
    /// - Parameter built: The rows already summarised, newest first.
    /// - Returns: Those rows and the next page.
    private func page(after built: [SessionSummary]) async throws -> [SessionSummary] {
        var built = built
        for session in inScope.dropFirst(built.count).prefix(SessionListState.pageSize) {
            built.append(try await reader.summary(for: session))
        }
        return built
    }
}

/// Which of `FR-1.13.1`'s states the week view is in.
///
/// A resolver rather than a chain of `if let` inside the view, on the rule every screen in this app
/// follows: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum WeekHistoryScreenState: Equatable {
    /// The read has not answered yet.
    case loading

    /// It answered, and there is nothing in scope to draw — `FR-1.13.2`'s first launch, or a week
    /// opened at the very beginning of a history with nothing before it.
    case empty

    /// There are weeks to draw.
    case ready

    /// The sessions could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameter phase: The screen's read state.
    /// - Returns: The state to draw.
    static func current(_ phase: WeekHistoryState.Phase) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded(let summaries): summaries.isEmpty ? .empty : .ready
        case .failed: .failed
        }
    }
}
