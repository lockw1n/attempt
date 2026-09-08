import AppNavigation
import DesignSystem
import DesignTokens
import Foundation
import Localization
import PowerliftingCore
import RepositoryInterface
import SwiftUI

/// One day of the week, read only (`TR-17.6`).
///
/// **What the day prescribes and how far through it the lifter is, and no command** — the answers
/// are `T-17.11`'s. It exists in this task because `TrainingRoute.day(runID:week:dayIndex:)` has to
/// be answered by something the moment the case compiles, and because a day reached from a card is
/// what makes the week navigable at all.
///
/// **Addressed by the stamp rather than by a session id**, which is the route's own argument: a day
/// nothing has been logged into has no session, so a session id could not name it.
public struct DayView: View {
    /// The day's own state — the plan, and what has been logged against it.
    @State private var day: DayState

    /// The workout in progress, for the unit its loads read in (`G-3.1`).
    private let store: ActiveSessionStore

    /// Builds the screen over the stamp the route carried.
    ///
    /// - Parameters:
    ///   - runID: The program run.
    ///   - week: The week number stamped on the day's session.
    ///   - dayIndex: The `ProgramDay.order` this is.
    ///   - store: The workout in progress, for the display unit.
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routine the day names.
    ///   - workouts: The day's session and its entries.
    ///   - exercises: The catalogue the plan's slots name.
    public init(
        runID: UUID,
        week: Int,
        dayIndex: Int,
        store: ActiveSessionStore,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository
    ) {
        self.store = store
        _day = State(
            initialValue: DayState(
                runID: runID,
                week: week,
                dayIndex: dayIndex,
                programs: programs,
                routines: routines,
                workouts: workouts,
                exercises: exercises))
    }

    /// The day's plan, whichever state the read is in.
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg.points) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.lg.points)
        }
        .background(ColorToken.background)
        .navigationTitle(Text(title))
        .task {
            await store.loadDisplayUnit()
            await day.load()
        }
    }

    /// The day's name where its routine has one, and its position where it has not.
    private var title: String {
        let name = day.card?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard name.isEmpty else { return name }
        return String(localized: LoggingStrings.weekDay(day.dayIndex + 1))
    }

    /// The screen's four states (`FR-1.13.1`). No offline state and no insufficient-data state, for
    /// the root's reasons.
    @ViewBuilder private var content: some View {
        switch day.phase {
        case .idle, .loading:
            LoadingStateView()
        case .failed:
            ErrorStateView(
                headline: Text(LoggingStrings.dayErrorHeadline),
                message: Text(LoggingStrings.dayErrorMessage),
                retryEmphasis: .primary,
                retry: { Task { await day.load() } }
            )
        case .ready:
            if let card = day.card, !card.plan.isEmpty {
                rows(card)
            } else {
                EmptyStateView(
                    symbolName: "archivebox",
                    headline: Text(LoggingStrings.dayEmptyHeadline),
                    message: Text(LoggingStrings.dayEmptyMessage))
            }
        }
    }

    /// One row per planned exercise, with the state each is in.
    private func rows(_ card: WeekDayCard) -> some View {
        DayPlanSection(plan: card.plan, unit: store.displayUnit, answered: day.answered)
    }
}

/// What a day prescribes, one row per exercise (`TR-17.6`).
///
/// **A view rather than a `GroupedSection` built inside the screen**, which is `T-16.17`'s finding:
/// a reference that assembles a screen's parts by hand is evidence about the parts, so the section
/// a snapshot renders has to be the section the screen draws.
struct DayPlanSection: View {
    /// The day's exercises with their plan.
    let plan: [WeekPlanLine]

    /// The unit their loads read in (`G-3.1`).
    let unit: MassUnit

    /// The exercises the day's session has marked done (`FR-15.3.4`).
    let answered: Set<UUID>

    var body: some View {
        GroupedSection(Text(LoggingStrings.dayPlanHeading)) {
            ForEach(plan) { line in
                DayPlanRow(
                    line: line,
                    unit: unit,
                    // A slot whose catalogue row has gone is never answered: there is no id to have
                    // ticked. Written as a `map` rather than a minted `UUID`, which would be a
                    // value invented per render to stand for `false`.
                    isDone: line.exercise.map { answered.contains($0.id) } ?? false)
            }
        }
    }
}

/// One planned exercise on a read-only day.
struct DayPlanRow: View {
    /// The slot.
    let line: WeekPlanLine

    /// The unit its loads read in (`G-3.1`).
    let unit: MassUnit

    /// Whether the day's session has this exercise answered (`FR-15.3.4`).
    let isDone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs.points) {
            PlanLineRow(line: line, unit: unit)
            if isDone {
                // Never by tint alone (`G-4.5`): the word carries it and the colour is added.
                Label {
                    Text(LoggingStrings.dayRowDone)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(Typography.caption.font)
                .foregroundStyle(ColorToken.positive)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One day of a week, as ``DayView`` reads it (`TR-17.6`).
///
/// **It reuses ``WeekState``'s card rather than a shape of its own**, because a day *is* one of
/// those: the same plan lines, the same three states. What it adds is which exercises the day's
/// session has answered, which the week's card only counts.
@Observable
public final class DayState {
    /// What the screen has to show. ``WeekState/Phase``'s four, for the same reason.
    public typealias Phase = WeekState.Phase

    /// The screen's read state.
    public private(set) var phase: Phase = .idle

    /// The day, or `nil` where the run or the day has gone.
    public private(set) var card: WeekDayCard?

    /// The exercises the day's session has marked done (`FR-15.3.4`).
    public private(set) var answered: Set<UUID> = []

    /// The `ProgramDay.order` this screen is over.
    public let dayIndex: Int

    /// The run the route carried.
    private let runID: UUID

    /// The week the route carried.
    private let week: Int

    /// The week this day belongs to, read whole — its read serves both the card and the answers.
    private let weekState: WeekState

    /// Builds the reading.
    ///
    /// - Parameters:
    ///   - runID: The program run.
    ///   - week: The week number.
    ///   - dayIndex: The `ProgramDay.order`.
    ///   - programs: The programs, their days and the run in force.
    ///   - routines: The routine the day names.
    ///   - workouts: The day's session and its entries.
    ///   - exercises: The catalogue the plan's slots name.
    public init(
        runID: UUID,
        week: Int,
        dayIndex: Int,
        programs: any ProgramRepository,
        routines: any RoutineRepository,
        workouts: any WorkoutRepository,
        exercises: any ExerciseRepository
    ) {
        self.runID = runID
        self.week = week
        self.dayIndex = dayIndex
        self.weekState = WeekState(
            programs: programs, routines: routines, workouts: workouts, exercises: exercises)
    }

    /// Reads the day, on every appearance.
    public func load() async {
        phase = .loading
        await weekState.load(openSession: nil)
        switch weekState.phase {
        case .failed(let diagnostic):
            phase = .failed(diagnostic)
        case .idle, .loading, .ready:
            card = day(in: weekState.reading)
            answered = card == nil ? [] : weekState.answered[dayIndex] ?? []
            phase = .ready
        }
    }

    /// The day this screen is over, or `nil` where the week that was read is not the week the route
    /// named.
    ///
    /// **The stamp is checked rather than merely carried, and it is one read that answers both
    /// halves.** ``WeekState`` reads whichever run and week are current; a restored stack decodes a
    /// stamp that was current when it was written (`Route`'s header). Without the check a day
    /// reopened after the week turned would draw the new week's plan under the old week's ticks —
    /// two halves of one screen describing two different weeks.
    ///
    /// - Parameter reading: What the week read.
    /// - Returns: The card, or `nil`.
    private func day(in reading: WeekReading) -> WeekDayCard? {
        guard case .week(let readRunID, _, let readWeek, let days) = reading,
            readRunID == runID, readWeek == week
        else {
            return nil
        }
        return days.first { $0.dayIndex == dayIndex }
    }
}
