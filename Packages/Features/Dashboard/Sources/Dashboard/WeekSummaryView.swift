import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the week summary's five states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **A quiet week and an unweighable one are separate states rather than one zero.** `FR-1.13.3`
/// forbids a derived value drawn as zero, and the two zeros here mean different things: a week with
/// no working sets in it has nothing to report, while a week of pull-ups and assisted work has a
/// real workout count and a volume ``DerivedValues/Tonnage`` deliberately cannot produce — its third
/// clause, the silent omission this screen is where the copy for finally lands.
///
/// No offline state: the sessions are local (`G-2.1`).
enum WeekSummaryScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and nothing this week counts as training done.
    case quiet

    /// Training happened, and none of it carries a load that can be weighed.
    case unweighed(workouts: Int)

    /// A count and a volume, both real.
    case ready(WeekSummary)

    /// The sessions could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks a summary already on screen**, on the other two sections' rule: a read
    /// that failed leaves the previous week's numbers in `summary`, and drawing them under no
    /// diagnostic presents a stale figure as a current one.
    ///
    /// - Parameter state: The week's load.
    /// - Returns: The state to draw.
    static func current(_ state: WeekSummaryState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded, let summary = state.summary else { return .loading }
        guard summary.workoutCount > 0 else { return .quiet }
        guard summary.tonnage > .zero else { return .unweighed(workouts: summary.workoutCount) }
        return .ready(summary)
    }
}

/// `FR-1.9.5`'s this-week summary: how many workouts, and what they weighed.
///
/// The state is not this section's own — ``DashboardView`` owns it, because the same read decides
/// whether the screen is on `FR-1.13.2`'s first launch at all, and a section that loaded itself
/// would never run on the launch where that verdict is needed.
struct WeekSummarySection: View {
    /// The week's load, owned above.
    let state: WeekSummaryState

    /// Where the display unit comes from.
    let settings: any SettingsRepository

    /// The unit the volume is shown in (`G-3.1`).
    ///
    /// The section's own read, and kilograms until it lands — the same shape `RecentRecordsFeed`
    /// has, and for its reason: a tonnage is not the state's to carry.
    @State private var unit: MassUnit = .kilograms

    /// The card, and the unit read that dresses it.
    var body: some View {
        WeekSummaryReading(
            state: WeekSummaryScreenState.current(state),
            unit: unit,
            retry: { Task { await state.load() } }
        )
        .task {
            if let stored = try? await settings.settings().displayUnit { unit = stored }
        }
    }
}

/// What the week summary draws, with no store behind it — `TR-1.12`'s renderable half.
struct WeekSummaryReading: View {
    /// Which of the five states to draw.
    let state: WeekSummaryScreenState

    /// The unit the volume is shown in (`G-3.1`).
    let unit: MassUnit

    /// What the error state's retry does.
    let retry: () -> Void

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// How large the user reads at — what decides whether the two tiles sit side by side
    /// (`NFR-1.10`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The heading and whichever state is current.
    var body: some View {
        GroupedSection(Text(DashboardStrings.weekTitle)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .quiet:
                InsufficientDataView(message: Text(DashboardStrings.weekNone))
            case .failed:
                ErrorStateView(message: Text(DashboardStrings.weekError), retry: retry)
            case .unweighed(let workouts):
                workoutTile(workouts)
                // The volume in place rather than omitted: a card that showed a workout count and
                // simply no second number would be the blank `FR-1.13.3` exists to replace.
                InsufficientDataView(
                    headline: Text(DashboardStrings.weekVolume),
                    message: Text(DashboardStrings.weekUnweighed))
            case .ready(let summary):
                layout {
                    workoutTile(summary.workoutCount)
                    MetricTile(
                        label: Text(DashboardStrings.weekVolume),
                        value: Text(
                            summary.tonnage, format: AppFormat.weight(in: unit, locale: locale)))
                }
            }
        }
    }

    /// How many workouts the week held.
    private func workoutTile(_ count: Int) -> some View {
        MetricTile(
            label: Text(DashboardStrings.weekWorkouts),
            value: Text(count, format: AppFormat.count(locale: locale)))
    }

    /// Side by side, or stacked — `RecentRecordRow`'s measured switch, for its reason: at
    /// `accessibility3` a formatted tonnage beside a count wraps its numeral across three lines.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.lg.points))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg.points))
    }
}
