import Foundation
import PowerliftingCore
import RepositoryInterface

/// The calendar's data and the reads behind it (`FR-1.5.3`).
///
/// **A screen's state rather than one of `TR-1.2`'s stores**, for ``SessionListState``'s reason:
/// which month is on screen outlives nothing and no other surface has to agree about it.
///
/// **One read answers every month.** The session rows are a single query and are small — three
/// years is a few hundred of them, and none of their sets are touched to mark a day — so the whole
/// history is read once and indexed by day. Paging the grid by month would be a repository call per
/// chevron tap for no less work.
///
/// **The day index is the calendar's, and it is rebuilt when the calendar changes.** A session's
/// `date` is written as `Calendar.current.startOfDay(for:)` by the one screen in this app that
/// creates one, but a row that arrived by sync or restore was not written here — and the device's
/// own time zone moves. So every session is normalised through ``calendar`` on the way into the
/// index rather than trusted to be a day start already.
///
/// **A day's sessions are summarised only when that day is selected.** A month has at most thirty-one
/// training days and a summary needs every set under its session; building them all to draw
/// thirty-one dots would be the eager load `NFR-1.5` cannot survive, and the dots do not need them.
@Observable
final class CalendarState {
    /// What the grid has to show, as one value rather than three flags.
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case idle

        /// The read is in flight.
        case loading

        /// It answered. How many training days there are is ``trainingDays``'.
        case loaded

        /// The read failed, carrying the error's description — a **diagnostic**, not copy (`G-3.4`).
        /// Recoverable: ``load()`` runs again from here, which is the retry.
        case failed(String)
    }

    /// What the day's own section under the grid has to show.
    enum DayPhase: Equatable {
        /// No day is selected — the section is not drawn at all.
        case none

        /// The selected day's sessions are being summarised.
        case loading

        /// They are ready, newest first.
        case loaded([SessionSummary])

        /// One of the reads refused. A **diagnostic**, not copy (`G-3.4`); the retry is selecting
        /// the same day again.
        case failed(String)
    }

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// Which of an exercise's two names a day's summary lists (`FR-1.14.2`).
    ///
    /// Set by the view before the read, for the reason ``SessionListState/nameLanguage`` gives.
    var nameLanguage: ExerciseNameLanguage = .english

    /// The days training was logged on, as day starts in ``calendar``.
    private(set) var trainingDays: Set<Date> = []

    /// The month on screen, laid out.
    private(set) var grid: MonthGrid

    /// The day the user picked, as a day start, or `nil` while none is.
    private(set) var selectedDay: Date?

    /// What that day's section is showing.
    private(set) var day: DayPhase = .none

    /// The unit a load is shown in (`G-3.1`, `G-3.2`).
    ///
    /// Kilograms until the settings row has been read, and after a read that failed — the schema's
    /// own default, for the reason ``SessionListState/displayUnit`` gives.
    private(set) var displayUnit: MassUnit = .kilograms

    /// The calendar the grid, the index and the bounds are all computed in.
    private(set) var calendar: Calendar

    /// Whether there is an earlier month worth showing.
    ///
    /// **The history plus the current month, and nothing beyond it in either direction.** A calendar
    /// that walked backwards forever would offer a hundred empty grids before the first training
    /// day; one that walked forwards would offer a future nothing can be logged into. Both chevrons
    /// stop where there is something to see.
    var canShowEarlierMonth: Bool { grid.month > bounds.lowerBound }

    /// Whether there is a later month worth showing.
    var canShowLaterMonth: Bool { grid.month < bounds.upperBound }

    /// Every session the store holds, newest first — the order the repository already guarantees.
    @ObservationIgnored private var sessions: [WorkoutSession] = []

    /// The sessions of each training day, keyed by day start in ``calendar``.
    @ObservationIgnored private var sessionsByDay: [Date: [WorkoutSession]] = [:]

    /// The earliest and latest month either chevron will reach, as month starts.
    @ObservationIgnored private var bounds: ClosedRange<Date>

    /// The instant the screen opened on. The month containing it is always in ``bounds``.
    @ObservationIgnored private let today: Date

    /// The month ``today`` falls in, as a month start in the calendar currently in use.
    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: today)?.start ?? calendar.startOfDay(for: today)
    }

    /// What each exercise is called, for a day's summary lines — empty until the catalogue is read.
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
    ///   - exercises: The catalogue, for the names in a day's summary lines.
    ///   - settings: The settings row, for the unit a tonnage is shown in.
    ///   - calendar: Which calendar decides where a month, a week and a day begin. The view passes
    ///     `@Environment(\.calendar)` through ``adopt(_:)`` once it has one; this is what the state
    ///     uses until then, and what a test pins.
    ///   - today: The instant the grid opens on, and the far end of its forward bound. A parameter
    ///     rather than `.now` inside, so a test does not assert against the day it runs.
    init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository,
        calendar: Calendar = .autoupdatingCurrent,
        today: Date = .now
    ) {
        self.workouts = workouts
        self.exercises = exercises
        self.settings = settings
        self.calendar = calendar
        self.today = today
        let opening = MonthGrid(containing: today, in: calendar)
        grid = opening
        bounds = opening.month...opening.month
    }

    /// Re-derives everything month-shaped in `calendar`, if it is not the one already in use.
    ///
    /// The view calls this before ``load()``, from `@Environment(\.calendar)`. It is not the
    /// initialiser's job: a `View`'s environment is unreadable from its own `init`, which is where
    /// the state is built.
    ///
    /// **The selection is dropped rather than translated.** A day start in one time zone is mid-day
    /// in another, so the day the user picked may no longer be a key of the index — and a section
    /// headed with one date showing another date's sessions is worse than a closed section.
    ///
    /// - Parameter calendar: The calendar the screen is being drawn in.
    func adopt(_ calendar: Calendar) {
        guard calendar != self.calendar else { return }
        self.calendar = calendar
        grid = MonthGrid(containing: grid.month, in: calendar)
        selectedDay = nil
        day = .none
        index(sessions)
    }

    /// Reads every session and marks the days they were trained on.
    ///
    /// **Re-read on every appearance**, on ``SessionListState/load()``'s rule: a workout finished
    /// above this screen has to be marked here on the way back down. A read already in flight is
    /// skipped.
    ///
    /// The selection survives a re-read where the day still has sessions, and is dropped where it
    /// does not — a day whose last session was deleted elsewhere is no longer a day to show.
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        // Read again on every appearance rather than once: the preference is changed in another
        // tab, and a cached unit would relabel every number under the grid wrongly.
        if let unit = try? await settings.settings().displayUnit {
            displayUnit = unit
        }
        do {
            // Deduplicated on the way in, for the reason ``SessionListState/deduplicated(_:)``
            // gives one screen along: a day's section is a `ForEach` keyed on the session
            // identifier, and `G-2.5` is what lets a store hold two rows under one.
            sessions = SessionListState.deduplicated(
                try await workouts.sessions(in: Self.everySession, includingDeleted: false))
            names = try await exerciseNames()
            index(sessions)
            phase = .loaded
        } catch {
            sessions = []
            index([])
            phase = .failed(String(describing: error))
        }
        // Through ``select(_:)`` rather than around it: a day whose last session was deleted
        // elsewhere is no longer in the index, and that method already closes the section for
        // exactly that case. A second test of the same condition here would be one that no
        // behaviour depends on.
        if let selectedDay {
            await select(selectedDay)
        }
    }

    /// Moves the grid `months` months, within ``bounds``.
    ///
    /// The selection is kept: a day stays selected while its own month is on screen and is simply
    /// not drawn while another is, so stepping away and back does not cost the user the section
    /// they opened.
    ///
    /// - Parameter months: How far to move. Negative is earlier.
    func showMonth(offsetBy months: Int) {
        let target = grid.month(offsetBy: months, in: calendar)
        guard bounds.contains(target) else { return }
        grid = MonthGrid(containing: target, in: calendar)
    }

    /// Summarises the sessions logged on `date`, and opens the section under the grid.
    ///
    /// **A day with no training clears the selection instead**, which is what makes a tap on an
    /// empty cell inert: there is no session to name, so there is nothing to open and nothing to
    /// push. The view does not make such a cell a control either; this is the same refusal one
    /// level down, so that neither half alone is load-bearing.
    ///
    /// - Parameter date: Any instant in the day to open.
    func select(_ date: Date) async {
        let start = calendar.startOfDay(for: date)
        guard let logged = sessionsByDay[start], !logged.isEmpty else {
            clearSelection()
            return
        }
        selectedDay = start
        day = .loading
        let reader = reader
        do {
            var summaries: [SessionSummary] = []
            for session in logged {
                summaries.append(try await reader.summary(for: session))
            }
            // A slower selection must not publish over a newer one — the user can tap a second day
            // while the first is still being summarised.
            guard selectedDay == start else { return }
            day = .loaded(summaries)
        } catch {
            guard selectedDay == start else { return }
            day = .failed(String(describing: error))
        }
    }

    /// Closes the day section.
    func clearSelection() {
        selectedDay = nil
        day = .none
    }

    /// Whether `date`'s day has training logged on it.
    ///
    /// - Parameter date: Any instant in the day.
    /// - Returns: Whether the grid marks it.
    func hasTraining(on date: Date) -> Bool {
        trainingDays.contains(calendar.startOfDay(for: date))
    }

    /// Rebuilds the day index, the marked days and the month bounds from `sessions`.
    ///
    /// - Parameter sessions: Every session the store holds, newest first.
    private func index(_ sessions: [WorkoutSession]) {
        sessionsByDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        trainingDays = Set(sessionsByDay.keys)
        // Anchored on the month the screen *opened* on rather than the one it is showing. Using
        // the visible month would let a walk backwards drag the range with it, and the forward
        // chevron would then stop short of today.
        bounds = Self.bounds(over: trainingDays, containing: currentMonth, in: calendar)
        // The month the grid opened on may now be outside the range — it cannot be, since the range
        // is built to contain it — but a month reached by a chevron before a re-read shrank the
        // history can be. Left there, the chevron pointing back into the range reads as enabled and
        // refuses every step, `showMonth(offsetBy:)` rejecting each target as out of bounds.
        //
        // **Clamped to the nearest end rather than snapped to one of them.** The user was reading
        // the oldest month they could reach; the oldest one that survives is the smaller move, and
        // the far end is a jump to today for a deletion that happened years from it.
        if !bounds.contains(grid.month) {
            let nearest = min(max(grid.month, bounds.lowerBound), bounds.upperBound)
            grid = MonthGrid(containing: nearest, in: calendar)
        }
    }

    /// The month range the chevrons may reach: every month with training in it, plus `anchor`'s.
    ///
    /// - Parameters:
    ///   - days: The training days, as day starts.
    ///   - anchor: A month that is always in range — the one the screen opened on, which is the
    ///     current month.
    ///   - calendar: The calendar the months are taken in.
    /// - Returns: The earliest and latest month, as month starts.
    private static func bounds(
        over days: some Collection<Date>, containing anchor: Date, in calendar: Calendar
    ) -> ClosedRange<Date> {
        let months = days.compactMap { calendar.dateInterval(of: .month, for: $0)?.start } + [anchor]
        // `anchor` is in the array, so neither reduction can be empty.
        return (months.min() ?? anchor)...(months.max() ?? anchor)
    }

    /// The catalogue as a name lookup.
    ///
    /// Deleted and archived rows included, and duplicate identifiers resolved, for the reasons
    /// ``SessionListState/names(in:)`` gives — it is that same lookup, over the same catalogue.
    ///
    /// - Returns: Each exercise's name, keyed by its identifier.
    private func exerciseNames() async throws -> [UUID: String] {
        SessionListState.names(
            in: try await exercises.exercises(includingDeleted: true), as: nameLanguage)
    }

    /// Every session there has ever been — ``SessionListState``'s range, for its reason.
    private static let everySession = Date.distantPast...Date.distantFuture
}

/// Which of `FR-1.13.1`'s states the calendar is in.
///
/// A resolver rather than a chain of `if let` inside the view, on the rule every screen in this app
/// follows: which state was chosen is a unit test's question, and what it looks like is a
/// snapshot's.
enum CalendarScreenState: Equatable {
    /// The read has not answered yet.
    case loading

    /// It answered, and nothing has ever been logged — `FR-1.13.2`'s first launch.
    ///
    /// **An empty state rather than an empty grid**, and the two are different claims: a grid with
    /// no marks on it says *this month* had no training, which is a fact about a month and invites
    /// the user to go looking through earlier ones. There are none.
    case empty

    /// There is training to mark.
    case ready

    /// The sessions could not be read; a retry may work.
    case failed

    /// Which state a phase is.
    ///
    /// - Parameters:
    ///   - phase: The screen's read state.
    ///   - trainingDays: How many days have been marked.
    /// - Returns: The state to draw.
    static func current(_ phase: CalendarState.Phase, trainingDays: Int) -> Self {
        switch phase {
        case .idle, .loading: .loading
        case .loaded: trainingDays == 0 ? .empty : .ready
        case .failed: .failed
        }
    }
}
