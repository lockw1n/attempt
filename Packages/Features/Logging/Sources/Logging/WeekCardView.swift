import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// The week: its heading, and one card per day of the run (`FR-17.8.1`).
///
/// Taking the reading rather than the state, for `SessionInProgressSection`'s reason: this is what
/// a snapshot renders, and a section that fetched its own facts would render as whatever it held
/// before the read.
struct WeekSection: View {
    /// The run these cards belong to — half of the route each one pushes.
    let runID: UUID

    /// The program's own name, as the lifter titled it.
    let programName: String

    /// The week the run is on.
    let weekNumber: Int

    /// The days, in the program's order.
    let days: [WeekDayCard]

    /// The unit the plan's loads read in (`G-3.1`).
    ///
    /// **Passed down rather than read here**, on ``ActiveSessionStore/displayUnit``'s argument: one
    /// unit per screen is one settings row read once, and a unit read per card is a chance for two
    /// numbers on one screen to mean different things.
    let unit: MassUnit

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md.points) {
            heading
            ForEach(days) { day in
                WeekDayCardView(
                    runID: runID,
                    weekNumber: weekNumber,
                    day: day,
                    unit: unit,
                    emphasis: .weekCommand(on: day, among: days))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The program's name, then which week of it this is.
    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            // The lifter's own words, so never looked up in a catalogue (`G-3.4`).
            Text(verbatim: programName)
                .font(Typography.cardTitle.font)
                .foregroundStyle(ColorToken.textPrimary)
            Text(LoggingStrings.weekHeading(week: weekNumber))
                .font(Typography.metricContext.font)
                .foregroundStyle(ColorToken.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One day of the week (`FR-17.8.1`).
///
/// **A done card collapses to its header line**, which is what keeps a six-day week scannable
/// (`DOD-17.12`): the plan is what is left to do, and a day that is done has none left. Every card
/// opens the day, done or not — this task's destination is read-only, and `T-17.11` gives it the
/// answers.
struct WeekDayCardView: View {
    /// The run the day belongs to.
    let runID: UUID

    /// The week it belongs to.
    let weekNumber: Int

    /// What this card draws.
    let day: WeekDayCard

    /// The unit the plan's loads read in (`G-3.1`).
    let unit: MassUnit

    /// How much weight this card's command takes (`FR-16.6.4`) — see
    /// ``DesignSystem/StateActionEmphasis/weekCommand(on:among:)``.
    let emphasis: StateActionEmphasis

    /// Which locale the done date is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationLink(
            value: Route.training(.day(runID: runID, week: weekNumber, dayIndex: day.dayIndex))
        ) {
            Card {
                VStack(alignment: .leading, spacing: Spacing.sm.points) {
                    header
                    if !isDone {
                        plan
                        command
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    /// Whether the day's card is collapsed to its header line.
    private var isDone: Bool {
        if case .done = day.progress { return true }
        return false
    }

    /// The day's position, its name, and where it has got to.
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            // The position first, and it is drawn on every card: a day whose routine has been
            // archived (`FR-15.2.5`) is kept and drawn nameless, and this line is then the whole of
            // what it can say about itself.
            Text(LoggingStrings.weekDay(day.dayIndex + 1))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
            if !day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: day.name)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
            }
            state
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Where the day has got to, in words.
    ///
    /// **Never by tint alone** (`G-4.5`): a finished day says the word *Done* and carries a glyph,
    /// and `G-7.3`'s green is what is added to that rather than what carries it.
    @ViewBuilder private var state: some View {
        switch day.progress {
        case .notStarted:
            EmptyView()
        case .inProgress(let done, let total):
            Text(LoggingStrings.weekDayProgress(done: done, of: total))
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.textSecondary)
        case .done(let date):
            Label {
                Text(
                    LoggingStrings.weekDayDone(
                        on: date.formatted(AppFormat.date(locale: locale))))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(Typography.caption.font)
            .foregroundStyle(ColorToken.positive)
        }
    }

    /// The day's exercises with what the routine prescribes for each.
    @ViewBuilder private var plan: some View {
        ForEach(day.plan) { line in
            PlanLineRow(line: line, unit: unit)
        }
    }

    /// **Start** on a day nothing has been logged into, **Continue** on one part-answered.
    ///
    /// Drawn inside the `NavigationLink`'s label rather than as a button of its own: the whole card
    /// pushes the day, so a second control would be a second tap target doing the same thing. What
    /// it carries is the weight (`FR-16.6.4`) and the word.
    @ViewBuilder private var command: some View {
        Text(commandLabel)
            .font(Typography.actionLabel.font)
            .foregroundStyle(emphasis == .primary ? ColorToken.onBrandAccent : ColorToken.textPrimary)
            .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
            .background(
                emphasis == .primary ? ColorToken.brandAccent : ColorToken.surfaceRaised,
                in: .rect(cornerRadius: CornerRadius.control.points)
            )
    }

    /// Which word that command carries.
    private var commandLabel: LocalizedStringResource {
        if case .inProgress = day.progress { return LoggingStrings.weekDayContinueAction }
        return LoggingStrings.weekDayStartAction
    }
}

/// One exercise of a day's plan — `Squat · 140 kg × 5 × 5` (`FR-17.8.1`).
struct PlanLineRow: View {
    /// The slot this row draws.
    let line: WeekPlanLine

    /// The unit its loads read in (`G-3.1`).
    let unit: MassUnit

    /// Which of the exercise's two names reads (`G-3.2`).
    @Environment(\.locale) private var locale

    /// `G-3.3`'s step, from the app rather than from this view.
    @Environment(\.displayPrecision) private var displayPrecision

    var body: some View {
        Text(
            LoggingStrings.weekPlanLine(
                exercise: line.exercise?.displayName(for: locale) ?? "", plan: plan)
        )
        .font(Typography.caption.font)
        .foregroundStyle(ColorToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Every target group the slot carries, joined.
    ///
    /// **Resolved to a `String` here rather than composed of `Text`s**, because the whole line is
    /// one localized format string with the lift's name in it (`G-3.4`) — a translation is free to
    /// put the plan first, which a stack of views could not honour.
    private var plan: String {
        line.targets.map(rendered).joined(
            separator: String(localized: LoggingStrings.weekPlanTargetSeparator))
    }

    /// One target group, in the lifter's unit.
    ///
    /// - Parameter target: The group.
    /// - Returns: `140 kg × 5 × 5`, or `5 × 5` where the plan named no load (`FR-15.2.2`).
    private func rendered(_ target: WeekPlanTarget) -> String {
        guard let weight = target.weight else {
            return String(
                localized: LoggingStrings.weekPlanTargetOpenLoad(
                    reps: target.reps, sets: target.sets))
        }
        let load = weight.formatted(
            AppFormat.weight(WeightDisplay(unit: unit, resolving: displayPrecision), locale: locale))
        return String(
            localized: LoggingStrings.weekPlanTarget(
                weight: load, reps: target.reps, sets: target.sets))
    }
}

/// The workout in progress that no program planned, after the week's days (`FR-17.8.3`, `Q-17.5`).
struct FreeWorkoutSection: View {
    /// What it draws.
    let card: FreeWorkoutCard

    /// Which locale the day is rendered for (`G-3.4`).
    @Environment(\.locale) private var locale

    var body: some View {
        GroupedSection(Text(LoggingStrings.weekFreeWorkoutTitle)) {
            SessionFactRow(
                label: LoggingStrings.trainInProgressDay,
                value: Text(card.date, format: AppFormat.date(locale: locale))
            )
            NavigationLink(value: Route.training(.activeSession)) {
                Text(LoggingStrings.weekDayContinueAction)
                    .font(Typography.actionLabel.font)
                    .foregroundStyle(ColorToken.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.standard.points)
                    .background(
                        ColorToken.surfaceRaised,
                        in: .rect(cornerRadius: CornerRadius.control.points)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

extension StateActionEmphasis {
    /// The weight one day's command takes on the week (`FR-16.6.4`, `FR-17.8.1`).
    ///
    /// **The screen has one accent and the week decides where it goes**: the day in progress, else
    /// the first day nothing has been logged into. Everything else is `.secondary` — a week of six
    /// filled buttons is six primary actions and therefore none.
    ///
    /// **Off the view so a test can reach it**, which is `T-16.17`'s finding: a rule written as a
    /// literal in a card is a rule nothing can ask a question of.
    ///
    /// The module prefix is not decoration: this extends a `DesignSystem` type, so the member hangs
    /// off `/DesignSystem/StateActionEmphasis` and DocC resolves from there.
    ///
    /// - Parameters:
    ///   - day: The card being drawn.
    ///   - days: Every day of the week, in the program's order.
    /// - Returns: `.primary` for the one day that spends the accent, `.secondary` otherwise.
    static func weekCommand(on day: WeekDayCard, among days: [WeekDayCard]) -> StateActionEmphasis {
        let accented =
            days.first { if case .inProgress = $0.progress { return true } else { return false } }
            ?? days.first { $0.progress == .notStarted }
        return accented?.dayIndex == day.dayIndex ? .primary : .secondary
    }
}
