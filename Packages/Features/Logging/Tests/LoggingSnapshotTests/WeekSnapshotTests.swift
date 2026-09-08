#if os(iOS)

    import AppNavigation
    import DesignSystem
    import DesignTokens
    import Foundation
    import PowerliftingCore
    import RepositoryInterface
    import SnapshotTesting
    import SwiftUI
    import Testing

    @testable import Logging

    // TR-1.12 for `FR-17.8`'s week, in the same four configurations as every other reference here.
    //
    // THE SECTIONS, NOT `TrainingHomeView`: it owns a `.task` that reads two stores, and
    // `ImageRenderer` has no way to run one. The card stack rather than the `ScrollView` around it,
    // which is T-16.06's rule — a `ScrollView` is UIKit-backed and records its placeholder.
    //
    // EVERY FIXTURE CARRIES A PLAN TO DRAW, which is T-16.02's: a week of cards with no exercises
    // on them is a picture of the wrong claim.
    //
    // EVERY CARD IS DIMMER HERE THAN IN THE APP, on this package's standing `NavigationLink` note:
    // a link with no `NavigationStack` above it draws as though it led nowhere, and wrapping the
    // subject in one makes it worse, a `NavigationStack` being UIKit-backed itself. The accent's
    // *placement* is what these references pin; its saturation is the simulator run's.

    @MainActor
    @Suite("The week's snapshots")
    struct WeekSnapshotTests {
        /// `FR-17.8.5`, which is also `FR-1.13.2`'s first launch: one action, and it is the plan.
        @Test func noProgram() throws {
            try assertSnapshots(named: "Week-empty") {
                EmptyStateView(
                    symbolName: "calendar",
                    headline: Text(LoggingStrings.weekEmptyHeadline),
                    message: Text(LoggingStrings.weekEmptyMessage),
                    action: StateAction(
                        Text(LoggingStrings.weekPlanAction), emphasis: .primary
                    ) {}
                )
            }
        }

        /// The three card states on one screen (`FR-17.8.1`) — and the accent on exactly one of
        /// them, which is what `FR-16.6.4` is about here.
        @Test func threeStates() throws {
            try assertSnapshots(named: "Week-cards") {
                fixedEnvironment { WeekFixtures.section(days: WeekFixtures.threeStates) }
            }
        }

        /// `FR-17.8.3`'s card for a workout no program planned.
        @Test func freeWorkout() throws {
            try assertSnapshots(named: "Week-free-workout") {
                fixedEnvironment {
                    FreeWorkoutSection(card: FreeWorkoutCard(date: WeekFixtures.day))
                }
            }
        }

        /// `DOD-17.12`: six days, three of them done and therefore collapsed to a header line. The
        /// `accessibility3` pair is the configuration worth reading — a six-day week that does not
        /// collapse is unreadable there, which is the whole reason a done card does.
        @Test func sixDays() throws {
            try assertSnapshots(named: "Week-six-days") {
                fixedEnvironment { WeekFixtures.section(days: WeekFixtures.sixDays) }
            }
        }

        /// The read-only day the week's cards open (`TR-17.6`).
        @Test func dayReadOnly() throws {
            try assertSnapshots(named: "Day-read-only") {
                fixedEnvironment {
                    GroupedSection(Text(LoggingStrings.dayPlanHeading)) {
                        DayPlanRow(
                            line: WeekFixtures.line("Back Squat", grams: 140_000),
                            unit: .kilograms,
                            isDone: true)
                        DayPlanRow(
                            line: WeekFixtures.line("Romanian Deadlift", grams: 100_000),
                            unit: .kilograms,
                            isDone: false)
                        DayPlanRow(
                            line: WeekFixtures.line("Ab Wheel", grams: nil),
                            unit: .kilograms,
                            isDone: false)
                    }
                }
            }
        }

        @Test func theFirstDayIsInsideTheFirstScreen() throws {
            // DOD-17.12, asserted on the rendering's own height rather than by eye: on a six-day
            // week half done, the first card a lifter can act on has to have its HEADER inside the
            // first screen — the plan under it may fall below the fold, which is what scrolling is
            // for, and what must not is the day's name and its command.
            //
            // WHAT IS MEASURED, and why it is not the four whole cards. The subject is the three
            // collapsed done cards plus a fourth carrying its header and its command and no plan
            // lines. That is strictly taller than "the header is on screen" and strictly shorter
            // than the real fourth card, which is the conservative side of both.
            //
            // THE BUDGET, and what is subtracted from the measurement, are
            // `SessionAboveFoldSnapshotTests`': 375 × 667 pt less the status bar, an inline
            // navigation bar and a 49 pt tab bar, and the harness's own `Spacing.lg` padding on the
            // vertical. The horizontal 32 pt is left in, which keeps this conservative — more
            // labels wrap here than on the device.
            let budget = 667.0 - 20.0 - 44.0 - 49.0
            let rendered = try Snapshot.render(
                fixedEnvironment {
                    WeekFixtures.section(
                        days: Array(WeekFixtures.sixDays.prefix(3)) + [WeekFixtures.headerOnly(3)])
                },
                appearance: .light,
                typeSize: .default
            )
            let points = Double(rendered.height) / Snapshot.scale - 2 * Spacing.lg.points
            print("DOD-17.12 four-card height: \(points) pt against a \(budget) pt budget")
            #expect(points < budget)
        }
    }

    /// The weeks these references render.
    enum WeekFixtures {
        /// The training day every card is stamped with — pinned, so a done card's date is stable.
        static let day = Date(timeIntervalSince1970: 1_757_203_200)

        /// The three states `FR-17.8.1` names, in the order a lifter meets them.
        static var threeStates: [WeekDayCard] {
            [
                card(0, "Squat day", ["Back Squat", "Leg Press"], .done(on: day)),
                card(1, "Bench day", ["Bench Press", "Row"], .inProgress(done: 1, of: 2)),
                card(2, "Pull day", ["Deadlift", "Chin-up"], .notStarted),
            ]
        }

        /// `DOD-17.12`'s six-day week: four exercises a day, three days done.
        static var sixDays: [WeekDayCard] {
            (0..<6).map { index in
                card(
                    index,
                    "Day \(index + 1)",
                    ["Back Squat", "Bench Press", "Barbell Row", "Ab Wheel"],
                    index < 3 ? .done(on: day) : .notStarted)
            }
        }

        /// A day drawn to its header and its command, with no plan under them — the height the
        /// budget above is measured to.
        ///
        /// - Parameter index: The day's position.
        /// - Returns: The card.
        static func headerOnly(_ index: Int) -> WeekDayCard {
            WeekDayCard(
                dayIndex: index, name: "Day \(index + 1)", plan: [], progress: .notStarted)
        }

        /// The week as the root draws it.
        ///
        /// - Parameter days: The cards.
        /// - Returns: The section.
        static func section(days: [WeekDayCard]) -> some View {
            WeekSection(
                runID: UUID(),
                programName: "Course #2",
                weekNumber: 3,
                days: days,
                unit: .kilograms)
        }

        /// One card.
        private static func card(
            _ index: Int, _ name: String, _ lifts: [String], _ progress: WeekDayProgress
        ) -> WeekDayCard {
            WeekDayCard(
                dayIndex: index,
                name: name,
                plan: lifts.map { line($0, grams: 140_000) },
                progress: progress)
        }

        /// One plan line — a lift and one target group.
        ///
        /// - Parameters:
        ///   - name: The lift.
        ///   - grams: Its prescribed load, or `nil` for `FR-15.2.2`'s blank target.
        /// - Returns: The line.
        static func line(_ name: String, grams: Int?) -> WeekPlanLine {
            WeekPlanLine(
                id: UUID(),
                exercise: Exercise(
                    id: UUID(),
                    createdAt: day,
                    updatedAt: day,
                    deletedAt: nil,
                    name: name,
                    ukrainianName: nil,
                    movement: .squat,
                    parentExerciseID: nil,
                    equipment: .barbell,
                    laterality: .bilateral,
                    barType: .standard,
                    implementCount: 1,
                    isCustom: false,
                    isArchived: false,
                    notes: ""),
                targets: [
                    WeekPlanTarget(
                        id: UUID(),
                        weight: grams.map { Weight(grams: $0) },
                        reps: 5,
                        sets: 5)
                ])
        }
    }

#endif
