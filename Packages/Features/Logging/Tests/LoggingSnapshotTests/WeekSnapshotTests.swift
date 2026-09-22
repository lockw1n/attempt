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
            // The screen's own view, not an `EmptyStateView` assembled here: T-16.17's four wrong
            // references were all fixtures that had built the component by hand and inherited an
            // emphasis the screen does not pass.
            try assertSnapshots(named: "Week-empty") {
                WeekEmptyState {}
            }
        }

        /// The three card states on one screen (`FR-17.8.1`) — and the accent on exactly one of
        /// them, which is what `FR-16.6.4` is about here.
        @Test func threeStates() throws {
            try assertSnapshots(named: "Week-cards") {
                fixedEnvironment { WeekFixtures.section(days: WeekFixtures.threeStates) }
            }
        }

        /// `FR-17.8.4`'s offer at the week's foot, once every planned day is done.
        @Test func nextWeek() throws {
            // The section, not a `Card` assembled here: the headline, the message and the accent
            // the command takes are the screen's decisions (T-16.17).
            try assertSnapshots(named: "Week-next-week-card") {
                fixedEnvironment { NextWeekSection(weekNumber: 3, failed: false, start: {}) }
            }
        }

        /// The same card once the rebuild wrote nothing — the sentence sits beside the command
        /// that issued it, because the retry is another tap at the same button.
        @Test func nextWeekFailed() throws {
            try assertSnapshots(named: "Week-next-week-card-error") {
                fixedEnvironment { NextWeekSection(weekNumber: 3, failed: true, start: {}) }
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

        /// `FR-17.9.1`: a day nothing has been logged into is the plan, one row per exercise,
        /// every circle open.
        @Test func dayNotStarted() throws {
            // `DayChecklistSection` rather than rows in a `GroupedSection` assembled here, on the
            // same rule: the heading, the grouping and what each row offers are the screen's
            // decisions, and a fixture that restates them pictures itself.
            try assertSnapshots(named: "Day-not-started") {
                fixedEnvironment { DayFixtures.section(DayFixtures.notStarted) }
            }
        }

        /// `FR-17.9.3`'s one-line answer: logged exactly as prescribed.
        @Test func dayAsPlanned() throws {
            try assertSnapshots(named: "Day-as-planned") {
                fixedEnvironment { DayFixtures.section([DayFixtures.asPlanned]) }
            }
        }

        /// `FR-17.9.3`'s two-line answer: what was planned, then what was done.
        @Test func dayLogged() throws {
            try assertSnapshots(named: "Day-logged") {
                fixedEnvironment { DayFixtures.section([DayFixtures.deviated]) }
            }
        }

        /// `FR-17.9.6`: an exercise the lifter decided against, which is an answer rather than an
        /// absence.
        @Test func daySkipped() throws {
            try assertSnapshots(named: "Day-skipped") {
                fixedEnvironment { DayFixtures.section([DayFixtures.skipped]) }
            }
        }

        /// `FR-15.2.2`: a plan naming no load has no circle, because the circle would have to
        /// invent a zero.
        @Test func dayNoLoad() throws {
            try assertSnapshots(named: "Day-no-load") {
                fixedEnvironment { DayFixtures.section([DayFixtures.openLoad]) }
            }
        }

        /// `FR-1.2.2`: a row the lifter added has no plan to perform, so no circle either.
        @Test func dayAdded() throws {
            try assertSnapshots(named: "Day-added") {
                fixedEnvironment { DayFixtures.section([DayFixtures.added]) }
            }
        }

        /// `FR-17.9.8`: every row answered — the heading says so, and the foot commands the
        /// `Day-foot-commands` reference pictures are gone.
        @Test func dayDone() throws {
            try assertSnapshots(named: "Day-done") {
                fixedEnvironment {
                    DayFixtures.section([DayFixtures.asPlanned, DayFixtures.skipped])
                }
            }
        }

        /// `FR-17.9.9`'s whole-day command, drawn under the rows it would answer for — and, since
        /// `FR-18.4.4`, the only one there: **Skip remaining** is in the day's `⋯`, which no
        /// content snapshot pictures.
        @Test func dayFootCommands() throws {
            try assertSnapshots(named: "Day-foot-commands") {
                fixedEnvironment {
                    VStack(alignment: .leading, spacing: Spacing.lg.points) {
                        DayFixtures.section(DayFixtures.notStarted)
                        DayFootCommands(logRemaining: {})
                    }
                }
            }
        }

        /// `FR-18.3.1`, `FR-18.3.2` and `NFR-18.2`, on the row that is hardest for all three: the
        /// longest name the catalogue holds over a plan that names two groups.
        ///
        /// **Two rows, because the scheme column has two jobs.** The first is unanswered, which is
        /// the column on its own; the second deviated, which is the column twice under two labels.
        /// The `accessibility3` pair is where `NFR-18.2` is proved — 320 pt, narrower than any
        /// device that runs iOS 26 — and the default pair is where a truncation invisible there
        /// would be (`T-1.91`).
        @Test func dayLongNameTwoGroups() throws {
            try assertSnapshots(named: "Day-long-name") {
                fixedEnvironment { DayFixtures.section(DayFixtures.longNameTwoGroups) }
            }
        }

        /// `DOD-18.15`: an answered row that departed from its plan, drawn as a hierarchy —
        /// the name semibold, the planned numbers secondary, the did numbers primary
        /// (`FR-18.3.6`, `FR-18.3.7`) — with **a badge under each group that set a record**
        /// (`FR-18.3.8`).
        ///
        /// **The whole of what `F-21` and `F-22` asked for is in this one pair of pictures**, and
        /// both halves are invisible in every other `Day-*` reference: the others answer one group,
        /// where there is no second badge to drop and no *Planned* line to read the *Did* line
        /// against.
        @Test func dayTwoGroupRecords() throws {
            try assertSnapshots(named: "Day-two-group-records") {
                fixedEnvironment { DayFixtures.section([DayFixtures.twoGroupRecords]) }
            }
        }

        /// `FR-18.3.2`'s "the same alignment", on the row that can break it: an open-load plan
        /// (`FR-15.2.2`, `12 × 3`) answered with a real load (`24 kg × 12 × 3`).
        ///
        /// **The two lines render to very different widths**, so a shape chosen per line would
        /// put *Planned* beside its numbers and *Did* above its own — which is what this pictures
        /// not happening. No other `Day-*` fixture can: every one of them has a plan and a
        /// performance of the same rendered width.
        @Test func dayAnsweredWidthsDiffer() throws {
            try assertSnapshots(named: "Day-answered-widths") {
                fixedEnvironment { DayFixtures.section([DayFixtures.openLoadLogged]) }
            }
        }

        /// The same pair of facts on the week's card (`FR-18.3.3`, `Q-18.2` at (a)): the name left
        /// and wrapping, the scheme right, falling to the day row's shape at accessibility sizes.
        @Test func weekLongNameTwoGroups() throws {
            try assertSnapshots(named: "Week-long-name") {
                fixedEnvironment { WeekFixtures.section(days: WeekFixtures.longNames) }
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

        /// `Q-18.2`'s card: one line whose name is the longest the catalogue holds and whose plan
        /// names two groups, and one ordinary line under it so the numbers have a column to form.
        static var longNames: [WeekDayCard] {
            [
                WeekDayCard(
                    dayIndex: 0,
                    name: "Chest day",
                    plan: [
                        line(DayFixtures.longName, targets: DayFixtures.twoGroups),
                        line("Dumbbell Fly", grams: 12_000),
                    ],
                    progress: .notStarted)
            ]
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
                unit: .kilograms,
                skipRemaining: { _ in })
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
            line(
                name,
                targets: [
                    WeekPlanTarget(
                        id: UUID(), weight: grams.map { Weight(grams: $0) }, reps: 5, sets: 5)
                ])
        }

        /// The same line over a plan that names more than one group (`FR-15.2.1`).
        ///
        /// - Parameters:
        ///   - name: The lift.
        ///   - targets: What it prescribes, in order.
        /// - Returns: The line.
        static func line(_ name: String, targets: [WeekPlanTarget]) -> WeekPlanLine {
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
                targets: targets)
        }
    }

#endif
