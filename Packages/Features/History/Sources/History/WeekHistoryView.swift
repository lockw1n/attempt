import AppNavigation
import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The history read a calendar week at a time (`FR-17.11`), as a screen of its own.
///
/// The view half of `TR-1.2`'s pattern — it holds ``WeekHistoryState`` in `@State`, reads its phase,
/// and decides nothing a test would want to ask about.
///
/// **Pushed from a calendar day** (`FR-17.11.2`): the week containing that day is the newest one
/// drawn and the day itself is marked. The tab's own week mode draws ``WeekHistoryContent``
/// directly, inside the list screen's scroller, so that the two are the same body over the same
/// state rather than two answers to what a week looks like.
public struct WeekHistoryView: View {
    @State private var state: WeekHistoryState

    /// The locale the exercise names in a row are resolved in (`FR-1.14.2`).
    @Environment(\.locale) private var locale

    /// Where a week and a day begin — the viewer's, not this module's.
    @Environment(\.calendar) private var calendar

    /// Builds the screen over the repositories its state reads.
    ///
    /// - Parameters:
    ///   - workouts: The sessions, their entries and their sets.
    ///   - exercises: The catalogue, for the names in a row.
    ///   - settings: The settings row, for the unit a tonnage is shown in.
    ///   - containing: The day the screen was opened at, whose week is the newest one drawn and
    ///     whose own rows are marked (`FR-17.11.2`).
    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository,
        containing day: Date
    ) {
        _state = State(
            initialValue: WeekHistoryState(
                workouts: workouts, exercises: exercises, settings: settings, containing: day))
    }

    /// Whichever of the screen's states is current.
    public var body: some View {
        ScrollView {
            WeekHistoryContent(state: state)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(HistoryStrings.weekTitle))
        .task {
            // The environment's calendar before the read, for ``CalendarView``'s reason: every week
            // boundary on this screen is computed in it.
            state.adopt(calendar)
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
    }
}

/// The week view's four states (`FR-1.13.1`), each one of T-1.09's shared components.
///
/// **A view over the state rather than a `@ViewBuilder` on either host**, because there are two
/// hosts: the pushed screen above and the History tab's own week mode, which draws this inside the
/// list screen's scroller. A second copy would be a second answer to what an empty week view says.
///
/// **No offline state and no insufficient-data state**, for ``SessionListView``'s reasons: a session
/// is a local row (`G-2.1`, `G-2.3`), and a row carries the same defensible zeros the log's does.
struct WeekHistoryContent: View {
    /// The screen's data.
    let state: WeekHistoryState

    /// The shell's navigation position, for the empty state's action. Optional and read rather than
    /// required, on ``SessionListView``'s rule: a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// The state that is current.
    var body: some View {
        switch WeekHistoryScreenState.current(state.phase) {
        case .loading:
            LoadingStateView()
        case .failed:
            // The screen's own phase switch, so the retry is the accent (`T-16.17`'s rule).
            ErrorStateView(
                headline: Text(HistoryStrings.weekErrorHeadline),
                message: Text(HistoryStrings.weekErrorMessage),
                retryEmphasis: .primary,
                retry: { Task { await state.load() } }
            )
        case .empty:
            EmptyStateView(
                symbolName: "calendar",
                headline: Text(HistoryStrings.weekEmptyHeadline),
                message: Text(HistoryStrings.weekEmptyMessage),
                action: StateAction(
                    Text(HistoryStrings.weekEmptyAction), emphasis: .primary
                ) {
                    // A tab switch that drops Train to its root, not a push — `D-8`'s one place a
                    // workout is logged. That root is the week, which is what the label names
                    // (`FR-17.8.5`).
                    navigation?.showTrain()
                }
            )
        case .ready:
            weeks
        }
    }

    /// The weeks, and whatever the next page has to say.
    private var weeks: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            WeekHistoryList(
                weeks: state.weeks,
                unit: state.displayUnit,
                markedDay: state.markedDay,
                // The foot of the list coming into view is the list running out, which is the only
                // signal a `LazyVStack` gives — and `FR-17.11.4`'s "a year back is paging". Asked of
                // the foot rather than of the last row for ``SessionMonthList/reachedEnd``'s reason.
                reachedEnd: { Task { await state.loadMore() } }
            )

            if state.extendFailure != nil {
                // The shared error component beneath the weeks rather than in place of them: what
                // did load is still on screen and still correct, so the retry steps down
                // (`T-16.17`'s rule for a failure beside the content).
                ErrorStateView(
                    message: Text(HistoryStrings.weekMoreErrorMessage),
                    retryEmphasis: .secondary,
                    retry: { Task { await state.loadMore() } }
                )
            }
        }
    }
}

/// The weeks themselves: `FR-17.11.1`'s date-range headings, and the days trained under each.
///
/// **A view of its own rather than a `@ViewBuilder`**, on ``SessionMonthList``'s rule: a screen
/// builds its state over three repositories and a reference must not need one, so what a reference
/// renders has to be a type that takes values.
struct WeekHistoryList: View {
    /// The rows, already cut into calendar weeks (`FR-17.11.1`).
    let weeks: [HistoryWeekSection]

    /// The unit every tonnage here is shown in (`G-3.1`).
    let unit: MassUnit

    /// The day the screen was opened on, whose rows are marked (`FR-17.11.2`), or `nil`.
    var markedDay: Date?

    /// Called when the foot of the list comes into view, so the caller can page (`FR-17.11.4`).
    var reachedEnd: () -> Void = {}

    /// Which locale the headings, days, names and numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The calendar the headings are drawn in — the same one the sections were cut in.
    @Environment(\.calendar) private var calendar

    /// One section per week, newest first.
    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.lg.points) {
            ForEach(weeks) { week in
                GroupedSection(Text(range(of: week))) {
                    ForEach(week.summaries) { summary in
                        row(summary)
                    }
                }
            }

            // The paging trigger, and the only lazily realised thing in this stack that is *below*
            // the rows — ``SessionMonthList``'s foot, keyed the same way and for the same reason.
            Color.clear
                .frame(height: Spacing.xxs.points)
                .id(weeks.last?.summaries.last?.id)
                .onAppear(perform: reachedEnd)
        }
    }

    /// One day's row, marked where it is the day the screen was opened on.
    ///
    /// **The mark is a ring and a spoken trait, never a tint** (`G-4.5`) — the two signals
    /// ``CalendarDayCell`` used to carry for the same fact, which is where this screen took the
    /// day's tap from. It is a stroke rather than a fill, so it spends none of `FR-16.6.4`'s one
    /// accent.
    ///
    /// - Parameter summary: The session the row describes.
    /// - Returns: The row.
    @ViewBuilder private func row(_ summary: SessionSummary) -> some View {
        let isMarked = markedDay.map { calendar.isDate(summary.date, inSameDayAs: $0) } ?? false
        SessionSummaryRow(
            summary: summary,
            unit: unit,
            // The heading has just said the week's range; the row owes the weekday and the day.
            date: .dayOfMonth,
            // `FR-17.11.1`: on this screen a session with no program stamp says so in words rather
            // than by drawing nothing, because the week is read as a plan carried out.
            position: .always,
            destination: Route.history(.session(sessionID: summary.id))
        )
        .padding(isMarked ? Spacing.xs.points : 0)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.control.points, style: .continuous)
                .strokeBorder(ColorToken.brandAccent, lineWidth: 2)
                .opacity(isMarked ? 1 : 0)
                // **Load-bearing, and measured on the simulator**: a `Shape` in an overlay takes
                // hits over its whole frame, so without this the ring drawn *over* the row's own
                // `NavigationLink` swallows every tap — and the marked row is precisely the one a
                // reader arrived to open (`FR-17.11.2`, `FR-17.11.4`). A ring is decoration; it
                // must never be the thing under the thumb.
                .allowsHitTesting(false)
        )
        .accessibilityAddTraits(isMarked ? [.isSelected] : [])
    }

    /// The week's two ends as one heading (`FR-17.11.1`).
    ///
    /// **The year is on the far end only, until the week straddles one.** A range is conventionally
    /// written that way and a heading that said 2026 twice would spend half its width on it — but a
    /// week beginning in December and ending in January reads as *both* ends being the later year,
    /// which is a wrong date rather than a terse one. So the near end grows a year exactly when the
    /// two ends disagree about it, and only then.
    ///
    /// Rendered to a string rather than handed to `Text(_:format:)`, for ``CalendarDayCell``'s
    /// measured reason: SwiftUI re-resolves a date style's time zone out of the environment, which
    /// would undo the binding to the calendar the weeks were cut in.
    ///
    /// - Parameter week: The section.
    /// - Returns: The heading.
    private func range(of week: HistoryWeekSection) -> LocalizedStringResource {
        let sameYear = calendar.isDate(week.start, equalTo: week.end, toGranularity: .year)
        let opening = sameYear ? AppFormat.dayAndMonth(locale: locale) : AppFormat.date(locale: locale)
        return HistoryStrings.weekRange(
            from: week.start.formatted(AppFormat.resolved(opening, in: calendar)),
            to: week.end.formatted(
                AppFormat.resolved(AppFormat.date(locale: locale), in: calendar)))
    }
}
