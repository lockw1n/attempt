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

        /// `FR-17.9.9`'s two whole-day commands, drawn under the rows they would answer for.
        @Test func dayFootCommands() throws {
            try assertSnapshots(named: "Day-foot-commands") {
                fixedEnvironment {
                    VStack(alignment: .leading, spacing: Spacing.lg.points) {
                        DayFixtures.section(DayFixtures.notStarted)
                        DayFootCommands(logRemaining: {}, skipRemaining: {})
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

    /// The days these references render (`FR-17.9`).
    ///
    /// EVERY ROW'S TRAILING MENU DRAWS AS A PLACEHOLDER, on this package's standing `ImageRenderer`
    /// note: a `Menu` is UIKit-backed. The **frame is honoured** — 44 × 60 pt, which is what these
    /// references measure the row's height against — so only the glyph is substituted, and the
    /// circle beside it renders for real. Read the yellow block as *a control of that size is here*,
    /// not as a defect, and do not replace it with an `Image` to make the picture prettier: a
    /// fixture that is not the screen is evidence about the fixture (T-16.17).
    enum DayFixtures {
        /// Two rows nobody has answered, both with a load and therefore both with a circle.
        static var notStarted: [DayRow] {
            [
                row("Back Squat", plan: planned(140_000)),
                row("Romanian Deadlift", plan: planned(100_000)),
            ]
        }

        /// The one-line answer.
        static var asPlanned: DayRow {
            row("Back Squat", plan: planned(140_000), performed: planned(140_000), answer: .logged)
        }

        /// The two-line answer — one set short, at a lighter load, and a record all the same.
        ///
        /// **The badge is pictured here rather than on the as-planned row**, so one reference shows
        /// the mark and the other shows the line without it: a set below the plan can still be the
        /// heaviest ever done at that scheme, which is the case worth a picture (`FR-1.6.3`).
        static var deviated: DayRow {
            row(
                "Bench Press",
                plan: planned(100_000),
                performed: [target(95_000, reps: 5, sets: 4)],
                answer: .logged,
                records: [
                    SchemeMark(scheme: RecordScheme(reps: 5, sets: 4), isFirstPerformance: false)
                ])
        }

        /// `FR-17.9.6`'s skip.
        static var skipped: DayRow {
            row("Barbell Row", plan: planned(80_000), answer: .skipped)
        }

        /// `FR-15.2.2`'s blank target.
        static var openLoad: DayRow {
            row("Ab Wheel", plan: [target(nil, reps: 12, sets: 3)])
        }

        /// `FR-1.2.2`'s added row: no plan at all.
        static var added: DayRow {
            row("Face Pull", plan: [])
        }

        /// The day's rows, as the screen draws them.
        ///
        /// - Parameter rows: The rows.
        /// - Returns: The section.
        static func section(_ rows: [DayRow]) -> some View {
            DayChecklistSection(
                rows: rows,
                progress: DayProgress(rows),
                unit: .kilograms,
                answer: { _ in },
                log: { _ in },
                skip: { _ in })
        }

        /// One row, over the week fixture's own catalogue row so the two files name one lift once.
        private static func row(
            _ name: String,
            plan: [WeekPlanTarget],
            performed: [WeekPlanTarget] = [],
            answer: DayRowAnswer = .unanswered,
            records: [SchemeMark] = []
        ) -> DayRow {
            DayRow(
                id: UUID(),
                exercise: WeekFixtures.line(name, grams: nil).exercise,
                plan: plan,
                performed: performed,
                answer: answer,
                records: records)
        }

        /// The fixture's standard prescription: five sets of five.
        private static func planned(_ grams: Int) -> [WeekPlanTarget] {
            [target(grams, reps: 5, sets: 5)]
        }

        /// One target group.
        private static func target(_ grams: Int?, reps: Int, sets: Int) -> WeekPlanTarget {
            WeekPlanTarget(
                id: UUID(), weight: grams.map { Weight(grams: $0) }, reps: reps, sets: sets)
        }
    }

#endif
