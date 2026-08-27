import AppNavigation
import DerivedValues
import DesignSystem
import Foundation
import RepositoryInterface
import SwiftUI

/// Whether Home is a brand-new install's or a trained one's (`FR-1.13.2`).
///
/// **Two cases, because the third and fourth resolve into one of them.** A read still in flight and
/// a read that failed both draw the sections: each section carries its own loading and error state
/// out of T-1.09's five, so a screen-level spinner would be a fifth on top of four that already
/// exist, and a screen-level failure would suppress four self-reading sections on the strength of
/// one read that says nothing about whether they can draw. `FR-1.13.2` is a claim about an install
/// with no history, and only a read that answered can make it.
///
/// **The cost of that lands on the one launch `FR-1.13.2` is about**, and it is the right way round
/// rather than free: until the read answers, a brand-new install draws the sections it is about to
/// replace. What keeps it invisible is that the sections draw `LoadingStateView` first and every
/// read on an empty store returns at once — not the ordering. A screen-level loading case would
/// remove it by holding *every* launch behind the slowest read on the screen, which is the trade
/// this refuses.
enum DashboardScreenState: Equatable {
    /// Nothing has ever been logged. One guided state instead of five apologies.
    case firstLaunch

    /// There is history. Each section reports itself.
    case sections

    /// Which the screen is on.
    ///
    /// - Parameter state: The week's load, which is also the read that knows whether anything has
    ///   ever been logged.
    /// - Returns: The state to draw.
    static func current(_ state: WeekSummaryState) -> Self {
        guard state.failure == nil, state.hasLoaded, !state.hasEverTrained else { return .sections }
        return .firstLaunch
    }
}

/// Home's root: the primary action, and either `FR-1.13.2`'s first launch or `FR-1.9`'s four
/// sections.
///
/// **The "Start workout" action is a navigation and not a logging surface** (`FR-1.9.4`, `D-8`).
/// `NavigationState.startWorkout()` selects Train and drops it to its root, so the app's primary
/// action always arrives at the one screen a workout is started from — which is the duplication the
/// four-tab decision was taken to remove. It stays on screen while a workout is open, because Train's
/// root is what says a workout is open; the card below is where `FR-1.9.2`'s resume lives.
///
/// **On first launch the sections are replaced rather than joined.** Every one of them draws its own
/// state, and on an install with nothing in it that is five separate apologies pointing at the same
/// single action — the mix `FR-1.13.3` rules out applied to a whole screen at once. What replaces
/// them carries the action itself, which is what `FR-1.13.2` asks for and `EmptyStateView`'s own
/// contract makes mandatory here.
///
/// The `ScrollView`/`VStack` shape every screen in this app uses rather than a `List`, for
/// `TR-1.12`'s reason: the snapshot harness renders through `ImageRenderer`, which draws a
/// placeholder for anything UIKit-backed.
public struct DashboardView: View {
    /// The app's one recompute actor (`TR-1.6`), which values the tiles and the PR feed.
    private let records: PersonalRecordRecomputer

    /// The catalogue: what the tiles are named after, and what the picker chooses among.
    private let catalogue: any ExerciseRepository

    /// The sessions, for `FR-1.9.2`'s card.
    private let workouts: any WorkoutRepository

    /// The settings row: the tile selection (`FR-1.9.1`) and the display unit (`G-3.1`).
    private let settings: any SettingsRepository

    /// Starts a workout holding a past one's exercises. See ``LastWorkoutSection``.
    private let repeatSession: @MainActor (UUID) async -> Bool

    /// `FR-1.9.5`'s week, and the read that decides whether this is a first launch at all.
    ///
    /// Owned here rather than by the section that draws it: on first launch the section is not on
    /// screen, so a state it loaded itself would never answer the question that keeps it off.
    @State private var week: WeekSummaryState

    /// The shell's navigation position, for the primary action — which is a tab selection rather
    /// than a push, so it cannot be a `NavigationLink`.
    ///
    /// Optional and read rather than required, for `TrainingHomeView`'s reason: a preview or a
    /// snapshot has no shell above it.
    @Environment(NavigationState.self) private var navigation: NavigationState?

    /// Builds the dashboard.
    ///
    /// - Parameters:
    ///   - records: The app's one recompute actor.
    ///   - catalogue: The exercises.
    ///   - workouts: The sessions and what is under them.
    ///   - settings: The settings row.
    ///   - repeatSession: Starts a fresh workout holding a past one's exercises, reporting whether
    ///     one is now in progress.
    public init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository,
        repeatSession: @escaping @MainActor (UUID) async -> Bool
    ) {
        self.records = records
        self.catalogue = catalogue
        self.workouts = workouts
        self.settings = settings
        self.repeatSession = repeatSession
        _week = State(initialValue: WeekSummaryState(workouts: workouts))
    }

    /// The action, then either the guided first launch or the four sections.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                switch DashboardScreenState.current(week) {
                case .firstLaunch:
                    firstLaunch
                case .sections:
                    startAction
                    sections
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .task { await week.load() }
    }

    /// `FR-1.9`'s four sections, in the order `FR-1.9.4`'s action is primary to.
    ///
    /// **The week before the records.** `FR-1.9.5`'s two numbers are about the days the reader is
    /// in the middle of, where `FR-1.9.3`'s feed and `FR-1.9.1`'s tiles both reach back months —
    /// the nearer the fact, the higher it sits.
    @ViewBuilder private var sections: some View {
        LastWorkoutSection(
            workouts: workouts, catalogue: catalogue, repeatSession: repeatSession)
        WeekSummarySection(state: week, settings: settings)
        RecentRecordsSection(records: records, catalogue: catalogue, settings: settings)
        EstimatedMaxTilesSection(records: records, catalogue: catalogue, settings: settings)
    }

    /// `FR-1.13.2`'s guided state, wired to the shell.
    private var firstLaunch: some View {
        FirstLaunchReading { navigation?.startWorkout() }
    }

    /// `FR-1.9.4`'s primary action.
    private var startAction: some View {
        Button {
            navigation?.startWorkout()
        } label: {
            Text(DashboardStrings.startWorkout)
        }
        .buttonStyle(.primaryAction)
        .frame(maxWidth: .infinity)
    }
}

/// `FR-1.13.2`: one guided state for an install with nothing in it, carrying `FR-1.9.4`'s action
/// itself — `TR-1.12`'s renderable half.
///
/// **The separate "Start workout" button is not drawn above this.** The empty state's own action is
/// the same navigation, and two identical primary buttons stacked on a screen holding nothing else
/// is the first thing a new user would see.
struct FirstLaunchReading: View {
    /// Goes to Train, where a workout is started.
    let start: () -> Void

    /// The heading, what the screen becomes, and the way to get there.
    var body: some View {
        EmptyStateView(
            symbolName: "figure.strengthtraining.traditional",
            headline: Text(DashboardStrings.firstLaunchHeadline),
            message: Text(DashboardStrings.firstLaunchMessage),
            action: StateAction(Text(DashboardStrings.startWorkout), handler: start)
        )
        .frame(maxWidth: .infinity)
    }
}
