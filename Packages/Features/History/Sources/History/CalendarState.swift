import Foundation
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
/// **No session is summarised here at all** (`FR-17.11.2`). The grid marks days and nothing more —
/// a day's tap pushes ``AppNavigation/HistoryRoute/week(containing:)``, whose own state reads the
/// rows. Building thirty-one summaries to draw thirty-one dots would be the eager load `NFR-1.5`
/// cannot survive, and the dots never needed them.
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

    /// The screen's read state.
    private(set) var phase: Phase = .idle

    /// The days training was logged on, as day starts in ``calendar``.
    private(set) var trainingDays: Set<Date> = []

    /// The month on screen, laid out.
    private(set) var grid: MonthGrid

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

    /// The earliest and latest month either chevron will reach, as month starts.
    @ObservationIgnored private var bounds: ClosedRange<Date>

    /// The instant the screen opened on. The month containing it is always in ``bounds``.
    @ObservationIgnored private let today: Date

    /// The month ``today`` falls in, as a month start in the calendar currently in use.
    private var currentMonth: Date {
        calendar.dateInterval(of: .month, for: today)?.start ?? calendar.startOfDay(for: today)
    }

    @ObservationIgnored private let workouts: any WorkoutRepository

    /// Builds the state over the one repository it reads.
    ///
    /// **One, since `FR-17.11.2`.** The catalogue and the settings row were the day section's — a
    /// summary needs an exercise's name and a unit for its tonnage — and the section is now a screen
    /// of its own with its own reads. A grid that marks days needs neither.
    ///
    /// - Parameters:
    ///   - workouts: Where the sessions come from.
    ///   - calendar: Which calendar decides where a month, a week and a day begin. The view passes
    ///     `@Environment(\.calendar)` through ``adopt(_:)`` once it has one; this is what the state
    ///     uses until then, and what a test pins.
    ///   - today: The instant the grid opens on, and the far end of its forward bound. A parameter
    ///     rather than `.now` inside, so a test does not assert against the day it runs.
    init(
        workouts: any WorkoutRepository,
        calendar: Calendar = .autoupdatingCurrent,
        today: Date = .now
    ) {
        self.workouts = workouts
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
    /// - Parameter calendar: The calendar the screen is being drawn in.
    func adopt(_ calendar: Calendar) {
        guard calendar != self.calendar else { return }
        self.calendar = calendar
        grid = MonthGrid(containing: grid.month, in: calendar)
        index(sessions)
    }

    /// Reads every session and marks the days they were trained on.
    ///
    /// **Re-read on every appearance**, on ``SessionListState/load()``'s rule: a workout finished
    /// above this screen has to be marked here on the way back down. A read already in flight is
    /// skipped.
    ///
    func load() async {
        guard phase != .loading else { return }
        phase = .loading
        do {
            // **Not deduplicated**, unlike every other read of this query in the module: nothing
            // here is keyed on a session identifier since `FR-17.11.2`, and a day's mark is a `Set`
            // of day starts — so `G-2.5`'s two rows under one identifier collapse to one mark on
            // their own. The screen that draws rows is the one that owes the de-duplication.
            sessions = try await workouts.sessions(in: Self.everySession, includingDeleted: false)
            index(sessions)
            phase = .loaded
        } catch {
            sessions = []
            index([])
            phase = .failed(String(describing: error))
        }
    }

    /// Moves the grid `months` months, within ``bounds``.
    ///
    /// - Parameter months: How far to move. Negative is earlier.
    func showMonth(offsetBy months: Int) {
        let target = grid.month(offsetBy: months, in: calendar)
        guard bounds.contains(target) else { return }
        grid = MonthGrid(containing: target, in: calendar)
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
        trainingDays = Set(sessions.map { calendar.startOfDay(for: $0.date) })
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
