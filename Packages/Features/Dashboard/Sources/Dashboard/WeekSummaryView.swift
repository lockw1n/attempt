import DesignSystem
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// Which of the week card's four states is current (`FR-1.13.1`, `FR-1.13.3`).
///
/// **Quiet is a claim about three weeks, not one** (`FR-18.9.2`). A week with nothing in it is one
/// line of the card saying so in words; the card gives way to its empty state only when this week,
/// last week and the week before all hold no working set — a new install past first launch, or a
/// lifter back from a month off. Each line's own quiet and unweighed readings are
/// ``WeekLineReading``'s.
///
/// No offline state: the sessions are local (`G-2.1`).
enum WeekSummaryScreenState: Equatable {
    /// The first read has not answered yet.
    case loading

    /// It answered, and none of the three weeks holds training done.
    case quiet

    /// Two lines to draw.
    case ready(WeekSummaries)

    /// The sessions could not be read; a retry may work.
    case failed

    /// Which state a load is in.
    ///
    /// **The failure outranks weeks already on screen**, on the other two sections' rule: a read
    /// that failed leaves the previous answer in `weeks`, and drawing it under no diagnostic
    /// presents a stale figure as a current one.
    ///
    /// - Parameter state: The weeks' load.
    /// - Returns: The state to draw.
    static func current(_ state: WeekSummaryState) -> Self {
        if state.failure != nil { return .failed }
        guard state.hasLoaded, let weeks = state.weeks else { return .loading }
        return weeks.isQuiet ? .quiet : .ready(weeks)
    }
}

/// Which of the card's two lines a reading is for.
enum WeekLineName: Equatable, CaseIterable {
    /// The week in progress.
    case thisWeek

    /// The last completed week.
    case lastWeek
}

/// What one line of the card reads (`FR-1.13.3`).
///
/// **A quiet week and an unweighable one are separate readings rather than one zero.** `FR-1.13.3`
/// forbids a derived value drawn as zero, and the two zeros here mean different things: a week with
/// no working sets in it has nothing to report, while a week of pull-ups and assisted work has a
/// real workout count and a volume ``DerivedValues/Tonnage`` deliberately cannot produce — its
/// third clause, the silent omission this card is where the copy for finally lands.
enum WeekLineReading: Equatable {
    /// Nothing in the week counts as training done.
    case quiet

    /// Training happened, and none of it carries a load that can be weighed.
    case unweighed(workouts: Int)

    /// A count and a volume, both real.
    case weighed(workouts: Int, tonnage: Weight)

    /// The reading of `summary`.
    ///
    /// - Parameter summary: One week.
    /// - Returns: How its line reads.
    static func of(_ summary: WeekSummary) -> Self {
        guard summary.workoutCount > 0 else { return .quiet }
        guard summary.tonnage > .zero else { return .unweighed(workouts: summary.workoutCount) }
        return .weighed(workouts: summary.workoutCount, tonnage: summary.tonnage)
    }
}

/// One line of the card: which week, what it reads, and how its volume moved.
struct WeekLineModel: Equatable {
    /// Which week.
    let name: WeekLineName

    /// What it reads.
    let reading: WeekLineReading

    /// How its volume moved against the week before it, or `nil` where no change is drawn.
    let change: Weight?
}

/// The card's two lines, computed in one place so that a test can read which line carries the
/// change without a host (`FR-18.9.3`).
///
/// **This week's `change` is `nil` by construction, not by data.** The comparison is
/// ``WeekSummaries/lastWeekChange``, and only the last-week line is given it; a line for the week
/// in progress that could be handed a change would be one edit away from the part-week-against-
/// whole-week reading the requirement rules out.
struct WeekLines: Equatable {
    /// The week in progress, never carrying a change.
    let thisWeek: WeekLineModel

    /// The last completed week, carrying its change where there is one.
    let lastWeek: WeekLineModel

    /// Builds the two lines from the three weeks.
    ///
    /// - Parameter weeks: What the state read.
    init(_ weeks: WeekSummaries) {
        thisWeek = WeekLineModel(name: .thisWeek, reading: .of(weeks.thisWeek), change: nil)
        lastWeek = WeekLineModel(
            name: .lastWeek, reading: .of(weeks.lastWeek), change: weeks.lastWeekChange)
    }
}

/// `FR-1.9.5`'s week summary: this week so far, and last week with how it changed.
///
/// The state is not this section's own — ``DashboardView`` owns it, because the same read decides
/// whether the screen is on `FR-1.13.2`'s first launch at all, and a section that loaded itself
/// would never run on the launch where that verdict is needed.
struct WeekSummarySection: View {
    /// The weeks' load, owned above.
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

/// What the week card draws, with no store behind it — `TR-1.12`'s renderable half.
struct WeekSummaryReading: View {
    /// Which of the four states to draw.
    let state: WeekSummaryScreenState

    /// The unit the volumes are shown in (`G-3.1`).
    let unit: MassUnit

    /// What the error state's retry does.
    let retry: () -> Void

    /// The heading and whichever state is current.
    var body: some View {
        GroupedSection(Text(DashboardStrings.weekTitle)) {
            switch state {
            case .loading:
                LoadingStateView()
            case .quiet:
                InsufficientDataView(message: Text(DashboardStrings.weekNone))
            case .failed:
                ErrorStateView(
                    message: Text(DashboardStrings.weekError),
                    retryEmphasis: .secondary,
                    retry: retry)
            case .ready(let weeks):
                let lines = WeekLines(weeks)
                WeekLine(model: lines.thisWeek, unit: unit)
                WeekLine(model: lines.lastWeek, unit: unit)
            }
        }
    }
}

/// One line of the card: the week's name over its figures, and beneath them its change
/// (`FR-18.9.2`, `FR-18.9.3`).
///
/// **The figures wrap; they do not scale.** `MetricTile` shrinks its numeral because a numeral is
/// an anchor, and this line is a phrase — `3 workouts · 12 300 kg` at `accessibility3` breaks at the
/// separator and stays legible, where a phrase scaled to half is not.
///
/// **The change sits beneath the figures, at every size** — `MetricTile`'s own order of label,
/// number, context (`G-7.5`), not beside them. Side by side, a 320 pt card has no room for both at
/// the default size: whichever text yields wraps, and a change broken as `+100` over `kg` is the
/// collision the requirement rules out. Beneath, nothing competes for the width.
///
/// **Reads to VoiceOver as one sentence** (`G-4.2`): the week's name, then its figures, then the
/// change in words — *up* and *down* rather than the arrow and sign the eye gets, so direction is
/// never in the tint alone (`G-4.5`).
struct WeekLine: View {
    /// Which week, what it reads, and its change.
    let model: WeekLineModel

    /// The unit the volume is shown in (`G-3.1`).
    let unit: MassUnit

    /// Which locale the numbers are rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    /// Name, figures, change.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs.points) {
            Text(DashboardStrings.weekLineName(for: model.name))
                .font(Typography.metricLabel.font)
                .foregroundStyle(ColorToken.textSecondary)
            switch model.reading {
            case .quiet:
                context(Text(DashboardStrings.weekLineQuiet(for: model.name)))
            case .unweighed(let workouts):
                figures(Text(DashboardStrings.weekWorkouts(workouts)))
                // The volume's absence in words rather than omitted: a line that showed a workout
                // count and simply no second number would be the blank `FR-1.13.3` exists to
                // replace.
                context(Text(DashboardStrings.weekUnweighed))
            case .weighed(let workouts, let tonnage):
                figures(
                    Text(
                        DashboardStrings.weekLine(
                            Self.workoutsText(workouts, locale: locale),
                            Self.volumeText(tonnage, unit: unit, locale: locale))))
                if let change = model.change {
                    DeltaIndicator(
                        Self.direction(of: change),
                        value: Self.magnitude(of: change, unit: unit, locale: locale))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(for: model, unit: unit, locale: locale)))
    }

    /// The line's numbers, in the numeric weight so they read as the line's anchor, wrapping
    /// rather than truncating (`G-4.1`).
    private func figures(_ text: Text) -> some View {
        text
            .font(Typography.numericValue.font)
            .foregroundStyle(ColorToken.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A line's words where there are no numbers to anchor it.
    private func context(_ text: Text) -> some View {
        text
            .font(Typography.metricContext.font)
            .foregroundStyle(ColorToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The sentence VoiceOver reads for one line (`G-4.2`).
    ///
    /// **A static function rather than a property of the body**, so that a test can read the
    /// sentence with no host: the accessibility tree of a hosted view is empty without an
    /// accessibility client, and a sentence only VoiceOver could read would be held by nobody.
    ///
    /// **Every piece is rendered for `locale`**, the one the body was given, so the noun and the
    /// figures inside the sentence agree with the sentence around them and with what the eye gets;
    /// a piece rendered for the process would not follow a locale set on the environment.
    ///
    /// - Parameters:
    ///   - model: Which week, what it reads, and its change.
    ///   - unit: The unit the volume is spoken in (`G-3.1`).
    ///   - locale: Which locale the pieces are rendered for (`G-3.4`).
    /// - Returns: The sentence.
    static func spoken(
        for model: WeekLineModel, unit: MassUnit, locale: Locale
    ) -> LocalizedStringResource {
        let name = render(DashboardStrings.weekLineName(for: model.name), locale: locale)
        var sentence: LocalizedStringResource
        switch model.reading {
        case .quiet:
            sentence = DashboardStrings.weekSpoken(
                name, render(DashboardStrings.weekLineQuiet(for: model.name), locale: locale))
        case .unweighed(let workouts):
            sentence = DashboardStrings.weekSpokenFigures(
                name,
                workoutsText(workouts, locale: locale),
                render(DashboardStrings.weekUnweighed, locale: locale))
        case .weighed(let workouts, let tonnage):
            let workouts = workoutsText(workouts, locale: locale)
            let volume = volumeText(tonnage, unit: unit, locale: locale)
            if let change = model.change {
                sentence = DashboardStrings.weekSpokenCompared(
                    name,
                    workouts,
                    volume,
                    render(
                        DashboardStrings.weekChangeSpoken(
                            direction(of: change),
                            magnitude(of: change, unit: unit, locale: locale)),
                        locale: locale))
            } else {
                sentence = DashboardStrings.weekSpokenFigures(name, workouts, volume)
            }
        }
        sentence.locale = locale
        return sentence
    }

    /// `resource`, rendered for `locale` rather than for the process.
    private static func render(_ resource: LocalizedStringResource, locale: Locale) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    /// The workout count with its noun, pluralised for `locale`.
    private static func workoutsText(_ workouts: Int, locale: Locale) -> String {
        render(DashboardStrings.weekWorkouts(workouts), locale: locale)
    }

    /// The volume, whole, in the display unit — `AppFormat.tonnage`'s one rule for both the line
    /// and its change.
    private static func volumeText(_ tonnage: Weight, unit: MassUnit, locale: Locale) -> String {
        AppFormat.tonnage(in: unit, locale: locale).format(tonnage)
    }

    /// The change's size, unsigned — the indicator writes the sign.
    private static func magnitude(of change: Weight, unit: MassUnit, locale: Locale) -> String {
        volumeText(Weight(grams: abs(change.grams)), unit: unit, locale: locale)
    }

    /// Which way the volume moved — the tiles' own rule, so two equal weeks draw the flat
    /// indicator the tiles would draw for an estimate that did not move.
    static func direction(of change: Weight) -> DeltaDirection {
        EstimatedMaxTileView.direction(of: change)
    }
}
