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
/// out of T-1.09's five, so a screen-level spinner would be a fourth on top of three that already
/// exist, and a screen-level failure would suppress three self-reading sections on the strength of
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
    /// Nothing has ever been logged. One guided state instead of three apologies.
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

/// Home's root: either `FR-1.13.2`'s first launch or `FR-1.9`'s three sections.
///
/// **Nothing on Home starts, resumes or repeats a workout** (`FR-18.9.1`). `D-17.11` withdrew the
/// filled *Start workout* because it was a second door onto a tab the tab bar already reaches, and
/// `FR-1.9.2`'s last-workout card — the **Resume** beside it, and the **Repeat** that started a free
/// workout outside the run, the week and the day — is withdrawn with it. So the sections shape is
/// three readings and spends no accent at all (`FR-16.6.4`), the way `routines.routineList` does.
/// The one accent this screen can still spend is ``FirstLaunchReading``'s, on the shape that holds
/// nothing else. An open workout is reached from Train, which reads **Continue**.
///
/// **On first launch the sections are replaced rather than joined.** Every one of them draws its own
/// state, and on an install with nothing in it that is three separate apologies pointing at the same
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

    /// The sessions, for `FR-1.9.5`'s week.
    private let workouts: any WorkoutRepository

    /// The settings row: the tile selection (`FR-1.9.1`) and the display unit (`G-3.1`).
    private let settings: any SettingsRepository

    /// Where `FR-15.1.8`'s training max under each tile comes from.
    private let trainingMaxes: any TrainingMaxRepository

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
    ///   - trainingMaxes: Where `FR-15.1.8`'s training max under each tile is stored.
    public init(
        records: PersonalRecordRecomputer,
        catalogue: any ExerciseRepository,
        workouts: any WorkoutRepository,
        settings: any SettingsRepository,
        trainingMaxes: any TrainingMaxRepository
    ) {
        self.records = records
        self.catalogue = catalogue
        self.workouts = workouts
        self.settings = settings
        self.trainingMaxes = trainingMaxes
        _week = State(initialValue: WeekSummaryState(workouts: workouts))
    }

    /// Either the guided first launch or the three sections.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl.points) {
                switch DashboardScreenState.current(week) {
                case .firstLaunch:
                    firstLaunch
                case .sections:
                    sections
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .task { await week.load() }
    }

    /// `FR-1.9`'s three sections.
    ///
    /// **The week before the records.** `FR-1.9.5`'s two numbers are about the days the reader is
    /// in the middle of, where `FR-1.9.3`'s feed and `FR-1.9.1`'s tiles both reach back months —
    /// the nearer the fact, the higher it sits.
    @ViewBuilder private var sections: some View {
        WeekSummarySection(state: week, settings: settings)
        RecentRecordsSection(records: records, catalogue: catalogue, settings: settings)
        EstimatedMaxTilesSection(
            records: records,
            catalogue: catalogue,
            settings: settings,
            trainingMaxes: trainingMaxes)
    }

    /// `FR-1.13.2`'s guided state, wired to the shell.
    private var firstLaunch: some View {
        FirstLaunchReading { navigation?.showTrain() }
    }
}

/// `FR-1.13.2`: one guided state for an install with nothing in it, carrying its one action —
/// `TR-1.12`'s renderable half.
///
/// **The action is the Train tab's own empty-state offer, word for word** (`FR-17.8.5`'s **Plan
/// your week**). An install with nothing in it can be sent to exactly one place, and a screen that
/// named it differently from the screen it arrives at would read as two destinations.
///
/// **This is the only accent Home spends, and it is spent on a screen holding nothing else**
/// (`FR-16.6.4`) — `EmptyStateView`'s own contract makes the action mandatory here, and there is no
/// second command for it to outrank.
struct FirstLaunchReading: View {
    /// Selects Train, where a week is planned.
    let plan: () -> Void

    /// The heading, what the screen becomes, and the way to get there.
    var body: some View {
        EmptyStateView(
            symbolName: "figure.strengthtraining.traditional",
            headline: Text(DashboardStrings.firstLaunchHeadline),
            message: Text(DashboardStrings.firstLaunchMessage),
            action: StateAction(
                Text(DashboardStrings.planWeek), emphasis: .primary, handler: plan)
        )
        .frame(maxWidth: .infinity)
    }
}
