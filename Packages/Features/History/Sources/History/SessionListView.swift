import AppNavigation
import DerivedValues
import DesignSystem
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The History tab's root: every session logged, newest first (`FR-1.5.1`), and `FR-1.5.4`'s search
/// over the same history as a mode of it.
///
/// The view half of `TR-1.2`'s pattern — it holds ``SessionListState`` in `@State`, reads its phase,
/// and decides nothing a test would want to ask about.
///
/// **A `ScrollView` and a `LazyVStack`, not a `List`**, for `ExerciseListView`'s two reasons:
/// `TR-1.12`'s harness draws a placeholder for anything UIKit-backed, so a `List` screen snapshots
/// as a grey box; and a card layout is `Card`'s, not a `List`'s insets and separators. The
/// `LazyVStack` is also what makes the paging work — a row that has not been laid out has not asked
/// for the next page.
public struct SessionListView: View {
    @State private var state: SessionListState

    /// The locale the exercise names in a summary are resolved in (`FR-1.14.2`), handed to both
    /// states before their reads.
    @Environment(\.locale) private var locale

    /// The calendar `FR-16.6.3`'s month headings are cut and drawn in.
    ///
    /// **The device's own, read from the environment rather than defaulted**, on
    /// ``Localization/AppFormat/resolved(_:in:)``'s rule: a month boundary computed in one calendar
    /// and a heading rendered in another are a whole day apart, and binding to the environment is
    /// also what lets a reference pin the calendar it was recorded in.
    @Environment(\.calendar) private var calendar

    /// `FR-1.5.4`'s search over the same history, as a mode of this screen rather than a screen of
    /// its own — the field belongs to this list, and a pushed search would be a second place the
    /// History tab's sessions are listed.
    @State private var search: SessionSearchState

    /// The shell's navigation position, for the empty state's action.
    ///
    /// Optional and read rather than required, on `ExerciseListView`'s rule: a `StateAction` is a
    /// closure, and a preview or a snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the screen over the repositories its state reads.
    ///
    /// - Parameters:
    ///   - workouts: The sessions, their entries and their sets.
    ///   - exercises: The catalogue, for the names in a summary line.
    ///   - settings: The settings row, for the unit the tonnage is shown in.
    ///   - records: The app's one recompute actor (`TR-1.6`), told when a workout is ended here.
    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository,
        records: PersonalRecordRecomputer
    ) {
        _state = State(
            initialValue: SessionListState(
                workouts: workouts, exercises: exercises, settings: settings, records: records))
        _search = State(
            initialValue: SessionSearchState(
                workouts: workouts, exercises: exercises, settings: settings))
    }

    /// The search field, and whichever of the screen's states is current.
    ///
    /// `.searchable` rather than a `TextField`, for `ExerciseListView`'s three reasons: it is the
    /// system's search affordance, it is placed by the enclosing `NavigationStack`, and it keeps a
    /// UIKit-backed control out of the body a snapshot renders.
    public var body: some View {
        @Bindable var search = search
        return ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .searchable(text: $search.query, prompt: Text(HistoryStrings.searchPrompt))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // `FR-1.5.3`'s calendar, as a sibling of this list rather than a mode of it: the
                // two answer different questions (*what did I do* against *which days did I
                // train*) and neither is a filter on the other.
                NavigationLink(value: Route.history(.calendar)) {
                    Label {
                        Text(HistoryStrings.listCalendar)
                    } icon: {
                        Image(systemName: "calendar")
                    }
                }
            }
        }
        // `load()` on every appearance, not once: a workout finished in the Train tab has to be
        // here on the way back.
        .task {
            state.nameLanguage = ExerciseNameLanguage(locale)
            await state.load()
        }
        // The search's only trigger, keyed on *whether* a search is running rather than on what was
        // typed: it fires on the keystroke that starts one and on a return to a screen left
        // mid-search, and emptying the field cancels the walk rather than starting another. Every
        // keystroke in between filters the index in memory — there is no read to debounce.
        .task(id: search.isSearching) {
            search.nameLanguage = ExerciseNameLanguage(locale)
            await search.loadIfSearching()
        }
    }

    /// The screen's three states (`FR-1.13.1`), each one of T-1.09's shared components.
    ///
    /// **No offline state and no insufficient-data state, and both are decisions.** A session is a
    /// local row, so there is no fetch to be offline for (`G-2.1`, `G-2.3`); and while the tonnage
    /// *is* derived, a session with nothing weighable in it still has a date, its exercises and its
    /// set count — the row is not short of data, it is reporting a zero it can defend. What it does
    /// not do is *explain* the sets it left out; that is `FR-1.13.3`'s gap and it is owed copy the
    /// dashboard owes too.
    @ViewBuilder private var content: some View {
        if search.isSearching {
            results
        } else {
            browse
        }
    }

    /// The unsearched list's three states (`FR-1.13.1`), each one of T-1.09's shared components.
    @ViewBuilder private var browse: some View {
        switch SessionListScreenState.current(state.phase) {
        case .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(HistoryStrings.errorHeadline),
                message: Text(HistoryStrings.errorMessage),
                retry: { Task { await state.load() } }
            )
        case .empty:
            EmptyStateView(
                symbolName: "figure.strengthtraining.traditional",
                headline: Text(HistoryStrings.emptyHeadline),
                message: Text(HistoryStrings.emptyMessage),
                action: StateAction(Text(HistoryStrings.emptyAction)) {
                    // A tab switch that drops Train to its root, not a push — `D-8`'s one place a
                    // workout is logged.
                    navigation?.startWorkout()
                }
            )
        case .ready:
            sessions
        }
    }

    /// The search mode's four states (`FR-1.13.1`, `FR-1.5.4`), again all T-1.09's.
    ///
    /// **No offline and no insufficient-data state**, for the browse list's own reasons: a session
    /// is a local row (`G-2.1`, `G-2.3`), and a result carries the same defensible zeros a list row
    /// does. What is new here is the fourth: a query that matched nothing is not the list's
    /// `Empty` — the history may be full — so it has its own copy and its own way out.
    @ViewBuilder private var results: some View {
        switch SessionSearchScreenState.current(search.phase, hasResults: !search.results.isEmpty) {
        case .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(HistoryStrings.searchErrorHeadline),
                message: Text(HistoryStrings.searchErrorMessage),
                retry: { Task { await search.load() } }
            )
        case .empty:
            EmptyStateView(
                symbolName: "magnifyingglass",
                headline: Text(HistoryStrings.noMatchesHeadline),
                message: Text(HistoryStrings.noMatchesMessage),
                action: StateAction(Text(HistoryStrings.noMatchesAction)) {
                    search.clear()
                }
            )
        case .ready:
            matches
        }
    }

    /// The matching sessions, each saying why it is here.
    ///
    /// **No paging.** The walk behind a search has already read every session — that is what
    /// `FR-1.5.4`'s "every session containing it" costs — so there is nothing left to fetch and the
    /// `LazyVStack` is here for the rows it does not lay out rather than for the reads it defers.
    private var matches: some View {
        LazyVStack(spacing: Spacing.md.points) {
            ForEach(search.results) { result in
                NavigationLink(value: Route.history(.session(sessionID: result.id))) {
                    SessionSummaryCard(
                        summary: result.summary, unit: search.displayUnit, match: result.match)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The rows, cut into `FR-16.6.3`'s months, and whatever the next page has to say.
    ///
    /// The list itself is ``SessionMonthList`` — a type rather than a builder here, so a reference
    /// can render exactly what this screen draws. What stays on the screen is the two failures that
    /// stand beside it and the question `FR-16.4.4` asks.
    private var sessions: some View {
        VStack(alignment: .leading, spacing: Spacing.lg.points) {
            if state.finishFailure != nil {
                // `FR-1.13.1`'s shared component, with the list left standing beside it: a workout
                // that would not end costs this screen nothing, and the retry is another tap on the
                // row's own **Finish workout**. Above the rows because that is where a lifter who
                // has just tapped one is looking.
                ErrorStateView(message: Text(HistoryStrings.sessionFinishError))
            }

            SessionMonthList(
                months: months,
                unit: state.displayUnit,
                // The paging trigger: the last row appearing is the list running out, which is the
                // only signal a `LazyVStack` gives. It is answered here rather than in the list
                // because a month's last row is not the log's. It fires once per row —
                // `loadMore()` refuses a second caller and refuses to run at all once the rows are
                // exhausted.
                appeared: { summary in
                    guard summary.id == state.summaries.last?.id else { return }
                    Task { await state.loadMore() }
                },
                finish: { summary in
                    Task { await state.beginFinish(sessionID: summary.id) }
                }
            )

            if state.extendFailure != nil {
                // The shared error component beneath the rows rather than in place of them: the
                // sessions that did load are still on screen and still correct, and the retry is
                // another scroll at the same edge, so the button is the one that asks again.
                ErrorStateView(
                    message: Text(HistoryStrings.moreErrorMessage),
                    retry: { Task { await state.loadMore() } }
                )
            }
        }
        .alert(
            Text(HistoryStrings.sessionPendingTitle(state.pendingPrompt?.count ?? 0)),
            isPresented: Binding(
                get: { state.pendingPrompt != nil },
                set: { if !$0 { state.cancelFinish() } }),
            presenting: state.pendingPrompt
        ) { prompt in
            Button(role: .destructive) {
                Task { await state.finish(sessionID: prompt.sessionID, resolving: .remove) }
            } label: {
                Text(HistoryStrings.sessionPendingRemove)
            }
            Button {
                Task { await state.finish(sessionID: prompt.sessionID, resolving: .keepAsFailed) }
            } label: {
                Text(HistoryStrings.sessionPendingKeep)
            }
            Button(role: .cancel) {
                state.cancelFinish()
            } label: {
                Text(HistoryStrings.sessionPendingCancel)
            }
        } message: { _ in
            Text(HistoryStrings.sessionPendingMessage)
        }
    }

    /// The rows the list is showing, cut into months (`FR-16.6.3`).
    private var months: [SessionMonthSection] {
        SessionMonths.sections(state.summaries, calendar: calendar)
    }
}
