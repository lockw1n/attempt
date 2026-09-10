import AppNavigation
import DesignSystem
import Localization
import RepositoryInterface
import SwiftUI

/// A month grid of the days training was logged on (`FR-1.5.3`).
///
/// The view half of `TR-1.2`'s pattern — it holds ``CalendarState`` in `@State`, reads its phase,
/// and decides nothing a test would want to ask about.
///
/// **A marked day pushes its week** (`FR-17.11.2`), rather than opening a section beneath the grid.
/// A day can hold two workouts, so a cell cannot name a session — and the week that day falls in is
/// the screen that can, listing every day around it with its program position. An unmarked cell is
/// inert without a special case: it is not a control at all.
public struct CalendarView: View {
    @State private var state: CalendarState

    /// The shell's navigation position, for the empty state's action. Optional and read rather than
    /// required, on `SessionListView`'s rule: a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Where a month, a week and a day begin — the viewer's, not this module's.
    @Environment(\.calendar) private var calendar

    /// Builds the screen over the repositories its state reads.
    ///
    /// - Parameters:
    ///   - workouts: The sessions the grid marks days from.
    public init(workouts: any WorkoutRepository) {
        _state = State(initialValue: CalendarState(workouts: workouts))
    }

    /// Whichever of the screen's states is current.
    public var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(HistoryStrings.calendarTitle))
        .task {
            // The environment's calendar before the read, not after: the grid, the day index and
            // the month bounds are all computed in it, and re-deriving them costs a second pass.
            state.adopt(calendar)
            await state.load()
        }
    }

    /// The screen's four states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state and no insufficient-data state, and both are decisions.** A session is a
    /// local row, so there is no fetch to be offline for (`G-2.1`, `G-2.3`); and a month with no
    /// training in it is not short of data — it is an accurate picture of a month off, which is a
    /// thing a lifter wants to see rather than an apology for a derived value that cannot be
    /// computed.
    @ViewBuilder private var content: some View {
        switch CalendarScreenState.current(state.phase, trainingDays: state.trainingDays.count) {
        case .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(HistoryStrings.calendarErrorHeadline),
                message: Text(HistoryStrings.calendarErrorMessage),
                retryEmphasis: .primary,
                retry: { Task { await state.load() } }
            )
        case .empty:
            EmptyStateView(
                symbolName: "calendar",
                headline: Text(HistoryStrings.calendarEmptyHeadline),
                message: Text(HistoryStrings.calendarEmptyMessage),
                action: StateAction(
                    Text(HistoryStrings.calendarEmptyAction), emphasis: .primary
                ) {
                    // A tab switch that drops Train to its root, not a push — `D-8`'s one place a
                    // workout is logged. That root is the week, which is what the label names.
                    navigation?.showTrain()
                }
            )
        case .ready:
            calendarBody
        }
    }

    /// The month's controls and its grid.
    private var calendarBody: some View {
        VStack(alignment: .leading, spacing: Spacing.xl.points) {
            MonthHeader(
                month: state.grid.month,
                calendar: calendar,
                canShowEarlier: state.canShowEarlierMonth,
                canShowLater: state.canShowLaterMonth,
                step: { state.showMonth(offsetBy: $0) }
            )
            MonthGridView(
                grid: state.grid,
                trainingDays: state.trainingDays,
                calendar: calendar
            )
        }
    }
}

/// The month on screen and the two ways off it.
///
/// A separate view so a reference can render it without a repository behind it.
struct MonthHeader: View {
    /// The month being shown, as its first instant.
    let month: Date

    /// The calendar the month was taken in — and the one its name has to be rendered in, a
    /// `Date.FormatStyle` otherwise resolving against the device's own.
    let calendar: Calendar

    /// Whether there is an earlier month worth stepping to.
    let canShowEarlier: Bool

    /// Whether there is a later one.
    let canShowLater: Bool

    /// Steps the grid by that many months.
    let step: (Int) -> Void

    /// Which locale the month name renders for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The two chevrons, with the month between them.
    var body: some View {
        HStack(spacing: Spacing.md.points) {
            chevron(
                "chevron.left",
                label: HistoryStrings.calendarEarlier,
                by: -1,
                enabled: canShowEarlier
            )
            // Rendered rather than handed to `Text(_:format:)`, for the reason
            // ``CalendarDayCell`` gives: SwiftUI would re-resolve the time zone out of the
            // environment and undo the binding.
            Text(verbatim: renderedMonth)
                .font(Typography.cardTitle.font)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            chevron(
                "chevron.right",
                label: HistoryStrings.calendarLater,
                by: 1,
                enabled: canShowLater
            )
        }
        .frame(maxWidth: .infinity)
    }

    /// The month's name, rendered in ``calendar`` rather than handed to `Text(_:format:)`.
    ///
    /// SwiftUI re-resolves a date style's time zone out of the environment, which would undo the
    /// binding — the same trap ``CalendarDayCell`` documents.
    private var renderedMonth: String {
        month.formatted(AppFormat.resolved(AppFormat.month(locale: locale), in: calendar))
    }

    /// One step control.
    ///
    /// - Parameters:
    ///   - symbol: The glyph to draw.
    ///   - label: What VoiceOver reads instead — the glyph names nothing (`G-4.2`).
    ///   - months: How far the tap moves the grid.
    ///   - enabled: Whether there is anything that way. **Disabled rather than absent**: a control
    ///     that vanishes at the end of the history moves the month name under the thumb that was
    ///     reaching for it.
    /// - Returns: The button.
    private func chevron(
        _ symbol: String, label: LocalizedStringResource, by months: Int, enabled: Bool
    ) -> some View {
        Button {
            step(months)
        } label: {
            Image(systemName: symbol)
                .font(Typography.actionLabel.font)
                // G-4.3's 44pt, on a control whose glyph is a third of that.
                .frame(
                    minWidth: TouchTarget.standard.points,
                    minHeight: TouchTarget.standard.points)
        }
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }
}

/// One month as seven columns of days (`FR-1.5.3`).
///
/// Takes values rather than the state, so a reference can render it without a repository behind it.
///
/// **A `VStack` of `HStack`s, not a `LazyVGrid`.** A month is at most forty-two cells and every one
/// of them is on screen, so laziness buys nothing — and `TR-1.12`'s `ImageRenderer` harness has no
/// scroll position to lay a lazy container out against, which is the same reason `SessionListView`
/// snapshots its card rather than its list.
///
/// **The grid is the one place in this app that clamps Dynamic Type.** Seven columns cannot reflow
/// into a stack without ceasing to be a calendar, and at `accessibility3` a two-digit numeral in a
/// seventh of the screen's width has nowhere to go. Everything under the grid — the day's heading
/// and its summary cards, which is where the content actually is — scales without a limit.
struct MonthGridView: View {
    /// The month, laid out.
    let grid: MonthGrid

    /// The days training was logged on, as day starts in ``calendar``.
    let trainingDays: Set<Date>

    /// The calendar the grid was laid out in.
    let calendar: Calendar

    /// Which locale the headings and numerals render for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The column headings, then the weeks.
    var body: some View {
        VStack(spacing: Spacing.xs.points) {
            headings
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: Spacing.xs.points) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        cell(day)
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The seven column headings, in the calendar's own week order.
    ///
    /// **Hidden from VoiceOver.** They are one or two characters — two `T`s and two `S`s in English
    /// — and every cell beneath them names its own weekday in full, so reading them out would be
    /// seven ambiguous letters before any content (`G-4.2`).
    private var headings: some View {
        HStack(spacing: Spacing.xs.points) {
            ForEach(
                Array(AppFormat.weekdayInitials(in: calendar, locale: locale).enumerated()),
                id: \.offset
            ) { _, initial in
                Text(verbatim: initial)
                    .font(Typography.caption.font)
                    .foregroundStyle(ColorToken.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// One cell — a day of this month, or the padding before or after it.
    ///
    /// - Parameter day: The day start, or `nil` for padding.
    @ViewBuilder private func cell(_ day: Date?) -> some View {
        if let day {
            CalendarDayCell(
                day: day,
                calendar: calendar,
                hasTraining: trainingDays.contains(day)
            )
        } else {
            // A cell rather than a `Spacer`: the columns have to line up under their headings, and
            // padding that collapsed would move every day in the first week.
            Color.clear
                .frame(minHeight: TouchTarget.standard.points)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
    }
}

/// Where a marked day's tap goes (`FR-17.11.2`).
///
/// **A named function rather than a `Route` built inline in ``CalendarDayCell``**, because the edge
/// `DOD-17.11` is about is otherwise assertable only by running the app: a `NavigationLink`'s value
/// is not readable from a test, so what the cell *hands* it is the one half a unit test can pin.
/// The cell's own refusal to be a control at all on an untrained day stays where it is — this says
/// only where a tap that does happen lands.
enum CalendarDayDestination {
    /// The week `day` falls in, with `day` marked.
    ///
    /// - Parameter day: The day the cell draws, as its first instant in the grid's calendar.
    /// - Returns: The route the cell pushes.
    static func route(for day: Date) -> Route {
        .history(.week(containing: day))
    }
}

/// One day of the grid.
///
/// **A marked day carries three signals, none of them colour** (`G-4.5`): a filled surface behind
/// the numeral, a dot beneath it, and a VoiceOver label that says so in a word.
///
/// **An unmarked day is not a control.** There is no week to open on it, so there is nothing to tap:
/// the cell is static text, and no gesture on it can navigate anywhere.
///
/// **No selected state since `FR-17.11.2`.** A tap leaves this screen for the day's week, so there
/// is never a day held open under the grid for a ring to mark.
struct CalendarDayCell: View {
    /// The day, as its first instant.
    let day: Date

    /// The calendar the day was taken in. **Not decoration**: a `Date.FormatStyle` renders against
    /// the device's own calendar and time zone unless bound, so a cell that did not bind would
    /// label a UTC grid drawn one hour west with the previous day — every cell, and the first with
    /// the last day of the month before.
    ///
    /// The binding also has to survive SwiftUI, which re-resolves a date style's time zone out of
    /// the environment: both the numeral and the spoken label below are therefore rendered to a
    /// string here rather than handed to `Text(_:format:)`.
    let calendar: Calendar

    /// Whether training was logged on it.
    let hasTraining: Bool

    /// Which locale the numeral and the spoken date render for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// A link where there is a week to open, and a numeral where there is not.
    var body: some View {
        if hasTraining {
            NavigationLink(value: CalendarDayDestination.route(for: day)) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(HistoryStrings.calendarDayTrained(date: spokenDate)))
                .accessibilityAddTraits(.isButton)
        } else {
            face
                .accessibilityElement()
                .accessibilityLabel(Text(HistoryStrings.calendarDayUntrained(date: spokenDate)))
        }
    }

    /// What the cell draws: the numeral, its marker, and whatever the state around it adds.
    private var face: some View {
        VStack(spacing: Spacing.xxs.points) {
            Text(verbatim: renderedDay)
                .font(Typography.numericValue.font)
                .foregroundStyle(hasTraining ? ColorToken.textPrimary : ColorToken.textSecondary)
                // One line, shrunk a little rather than truncated: a two-digit day clipped to one
                // digit is a wrong date, where a slightly smaller one is the same date.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Circle()
                .fill(ColorToken.brandAccent)
                .frame(width: Spacing.xs.points, height: Spacing.xs.points)
                .opacity(hasTraining ? 1 : 0)
        }
        // G-4.3's 44pt, as a height floor plus the column's whole width. **Not a width floor**: a
        // seven-column grid with one would be 332pt wide before any padding, which overflows a
        // 320pt measure and clips the last column. The width is a seventh of the screen instead —
        // comfortably past 44pt on every device this app runs on, and the narrower reference
        // measure is what proves the layout does not depend on that.
        .frame(minHeight: TouchTarget.standard.points)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.control.points, style: .continuous)
                .fill(ColorToken.surfaceRaised)
                .opacity(hasTraining ? 1 : 0)
        )
    }

    /// The day's number, in ``calendar``.
    private var renderedDay: String {
        day.formatted(AppFormat.resolved(AppFormat.dayOfMonth(locale: locale), in: calendar))
    }

    /// The day named in full, for the label VoiceOver reads in place of one or two digits.
    private var spokenDate: String {
        day.formatted(AppFormat.resolved(AppFormat.fullDate(locale: locale), in: calendar))
    }
}
