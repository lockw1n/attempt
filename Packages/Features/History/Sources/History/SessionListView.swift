import AppNavigation
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
    public init(
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository,
        settings: any SettingsRepository
    ) {
        _state = State(
            initialValue: SessionListState(
                workouts: workouts, exercises: exercises, settings: settings))
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
        .task { await state.load() }
        // The search's only trigger, keyed on *whether* a search is running rather than on what was
        // typed: it fires on the keystroke that starts one and on a return to a screen left
        // mid-search, and emptying the field cancels the walk rather than starting another. Every
        // keystroke in between filters the index in memory — there is no read to debounce.
        .task(id: search.isSearching) { await search.loadIfSearching() }
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

    /// The rows, and whatever the next page has to say.
    private var sessions: some View {
        LazyVStack(spacing: Spacing.md.points) {
            ForEach(state.summaries) { summary in
                NavigationLink(value: Route.history(.session(sessionID: summary.id))) {
                    SessionSummaryCard(summary: summary, unit: state.displayUnit)
                }
                .buttonStyle(.plain)
                // The paging trigger: the last row appearing is the list running out, which is
                // the only signal a `LazyVStack` gives. It fires once per row — `loadMore()`
                // refuses a second caller and refuses to run at all once the rows are exhausted.
                .onAppear {
                    guard summary.id == state.summaries.last?.id else { return }
                    Task { await state.loadMore() }
                }
            }
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
    }
}

/// One session, as `FR-1.5.1`'s four facts: the day, what was trained, how many working sets, and
/// what they weighed.
///
/// Takes the summary and the unit rather than the state, so a reference can render it without a
/// repository behind it.
struct SessionSummaryCard: View {
    /// The row.
    let summary: SessionSummary

    /// The unit the tonnage is shown in (`G-3.1`).
    let unit: MassUnit

    /// Whether the card names its own day.
    ///
    /// **True in a list, false under a heading that already says it.** In the chronological list the
    /// date is what identifies a row; in the calendar's day section it is the section's own heading,
    /// and a card repeating it prints the same date twice in a row — on screen and to VoiceOver.
    var showsDate = true

    /// Why a search put this row on screen, or `nil` where the card is not a result (`FR-1.5.4`).
    ///
    /// An option on the list's own card rather than a wrapper around it, because the explanation
    /// belongs *inside* the card: a caption floating beneath one reads as a caption on the next.
    var match: SearchMatch?

    /// Which locale the day, the names and the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// The date, the exercises, the session's note where there is one, and the two metrics.
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.md.points) {
                if showsDate {
                    Text(summary.date, format: AppFormat.date(locale: locale))
                        .font(Typography.cardTitle.font)
                        .foregroundStyle(ColorToken.textPrimary)
                }

                exercises

                if !summary.notes.isEmpty {
                    // `FR-1.2.9`'s session note, readable for the first time. Clipped rather than
                    // laid out in full: this is a summary, and a paragraph typed at the rack would
                    // otherwise be the tallest thing in the list.
                    Text(verbatim: summary.notes)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .lineLimit(2)
                }

                metrics

                if let match {
                    matched(match)
                }
            }
        }
    }

    /// Where the query was found, as one line per field in a fixed order.
    ///
    /// **Lines rather than one run-together sentence**: three short labels wrap where a joined
    /// sentence would break mid-phrase at the largest Dynamic Type size, and each is its own
    /// VoiceOver stop. The set-note match carries the note itself, being the only one of the three
    /// the card shows no other evidence of.
    ///
    /// **The block is `fixedSize`d vertically**, and the reference images are why: nested one level
    /// deeper than the card's other rows, it was offered the height left over rather than the height
    /// it wanted, and every line in it truncated to one — including the note, whose own two-line
    /// limit never got to apply. A caption reading *Matched a set no…* explains nothing, which is
    /// the whole of what this block is for.
    ///
    /// - Parameter match: Which fields matched, and the note behind a set-note match.
    /// - Returns: The caption block.
    @ViewBuilder private func matched(_ match: SearchMatch) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            if match.fields.contains(.exerciseName) {
                matchLabel(HistoryStrings.matchExercise)
            }
            if match.fields.contains(.sessionNote) {
                matchLabel(HistoryStrings.matchSessionNote)
            }
            if match.fields.contains(.setNote) {
                matchLabel(HistoryStrings.matchSetNote)
                if let note = match.setNote {
                    Text(verbatim: note)
                        .font(Typography.caption.font)
                        .foregroundStyle(ColorToken.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One "matched in" line.
    ///
    /// - Parameter text: Which field matched.
    /// - Returns: The line.
    private func matchLabel(_ text: LocalizedStringResource) -> some View {
        Text(text)
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What was trained, run together as one phrase in the locale's own list style.
    @ViewBuilder private var exercises: some View {
        if summary.exerciseNames.isEmpty {
            Text(HistoryStrings.noExercises)
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textTertiary)
        } else {
            Text(verbatim: AppFormat.list(summary.exerciseNames, locale: locale))
                .font(Typography.body.font)
                .foregroundStyle(ColorToken.textSecondary)
                .lineLimit(2)
        }
    }

    /// The two numbers, as one line.
    ///
    /// **Not `G-7.5`'s metric tiles, and the reference images are why.** Two tiles side by side in a
    /// list row wrap their numeral across three lines at the largest Dynamic Type size — a tonnage
    /// broken over three lines reads as three numbers — and they read out to VoiceOver as a label
    /// and a bare numeral each. The pattern is the dashboard's, where a number is the content; here
    /// it is a footnote on a row whose content is the day. One sentence is also one VoiceOver stop
    /// (`G-4.2`), so no accessibility override is needed to make it read properly.
    private var metrics: some View {
        Text(HistoryStrings.metricsSummary(sets: summary.setCount, volume: renderedTonnage))
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
    }

    /// The tonnage, to the whole unit.
    ///
    /// **Whole, not `G-3.3`'s default step.** A half-kilogram on a session total is noise on a
    /// four-digit number, and the step exists for a load a lifter has to put on a bar.
    private var renderedTonnage: String {
        summary.tonnage.formatted(
            AppFormat.weight(in: unit, precision: .whole, locale: locale))
    }
}
