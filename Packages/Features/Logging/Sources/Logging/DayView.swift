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
        GroupedSection(Text(LoggingStrings.dayPlanHeading)) {
            ForEach(card.plan) { line in
                DayPlanRow(
                    line: line,
                    unit: store.displayUnit,
                    isDone: day.answered.contains(line.exercise?.id ?? UUID()))
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

    /// The week this day belongs to, read whole — one query serves the card and the answers.
    private let weekState: WeekState

    /// The day's own session and its entries.
    private let workouts: any WorkoutRepository

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
        self.workouts = workouts
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
            guard case .week(_, _, _, let days) = weekState.reading else {
                card = nil
                answered = []
                phase = .ready
                return
            }
            card = days.first { $0.dayIndex == dayIndex }
            await readAnswers()
            phase = .ready
        }
    }

    /// Which of the day's exercises the session has marked done.
    ///
    /// **Nothing is reported when this read fails.** The plan is already on screen and correct; a
    /// missing tick is less wrong than a screen replaced by an error over a day the lifter can see.
    private func readAnswers() async {
        answered = []
        guard
            let session = try? await workouts.sessions(
                forProgramRunID: runID, week: week, includingDeleted: false
            ).first(where: { $0.dayIndex == dayIndex }),
            let entries = try? await workouts.entries(
                forSessionID: session.id, includingDeleted: false)
        else {
            return
        }
        answered = Set(entries.filter(\.isMarkedDone).map(\.exerciseID))
    }
}
